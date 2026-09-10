`timescale 1ns / 1ps

// Read-only IEEE 802.3 Clause 22 MDIO master.
//
// The output is deliberately open-drain: mdio_drive_low=1 requests a zero;
// mdio_drive_low=0 releases the line. A board-level IOBUF converts that
// request to either logic 0 or high impedance, never to an actively driven 1.
// This block contains no Clause 22 write opcode or write-data path.
module mdio_clause22_reader (
    input  wire       clk,
    input  wire       start,
    input  wire [4:0] phy_addr,
    input  wire [4:0] reg_addr,
    input  wire       mdio_in,
    output reg        mdc,
    output wire       mdio_drive_low,
    output reg        busy,
    output reg        done,
    output reg        ta_error,
    output reg [15:0] read_data,
    output reg [2:0]  phase,
    output reg [5:0]  bit_index
);
    // 100 MHz / (2 * 50) = 1 MHz MDC, below the 2.5 MHz Clause 22 limit.
    localparam [5:0] MDC_HALF_PERIOD_CYCLES = 6'd50;

    localparam [2:0] PHASE_IDLE     = 3'd0;
    localparam [2:0] PHASE_PREAMBLE = 3'd1;
    localparam [2:0] PHASE_ST       = 3'd2;
    localparam [2:0] PHASE_OP       = 3'd3;
    localparam [2:0] PHASE_PHYAD    = 3'd4;
    localparam [2:0] PHASE_REGAD    = 3'd5;
    localparam [2:0] PHASE_TA       = 3'd6;
    localparam [2:0] PHASE_DATA     = 3'd7;

    reg [5:0]  mdc_divider;
    reg [15:0] read_shift;

    // Clause 22 read frame: 32x1, 01, 10, PHYAD, REGAD, Z0, DATA[15:0].
    // The master releases both turnaround bits; the PHY supplies the zero.
    assign mdio_drive_low = busy && (
        ((phase == PHASE_ST)    && (bit_index == 6'd0)) ||
        ((phase == PHASE_OP)    && (bit_index == 6'd1)) ||
        ((phase == PHASE_PHYAD) && !phy_addr[4 - bit_index]) ||
        ((phase == PHASE_REGAD) && !reg_addr[4 - bit_index])
    );

    // This project has no external reset input. Xilinx 7-series configuration
    // initializes these registers before user logic starts; the enclosing probe
    // also waits 1 ms before its first transaction.
    initial begin
        mdc         = 1'b0;
        mdc_divider = 6'd0;
        busy        = 1'b0;
        done        = 1'b0;
        ta_error    = 1'b0;
        read_data   = 16'd0;
        read_shift  = 16'd0;
        phase       = PHASE_IDLE;
        bit_index   = 6'd0;
    end

    always @(posedge clk) begin
        // done is a one-system-clock indication. Its data is retained in
        // read_data until the next successful Clause 22 read completes.
        done <= 1'b0;

        if (!busy && start) begin
            mdc         <= 1'b0;
            mdc_divider <= 6'd0;
            busy        <= 1'b1;
            ta_error    <= 1'b0;
            read_shift  <= 16'd0;
            phase       <= PHASE_PREAMBLE;
            bit_index   <= 6'd0;
        end else if (busy) begin
            if (mdc_divider == (MDC_HALF_PERIOD_CYCLES - 1'b1)) begin
                mdc_divider <= 6'd0;

                if (!mdc) begin
                    // Rising MDC edge: the PHY samples outbound bits and the
                    // master samples TA/data returned by the PHY.
                    mdc <= 1'b1;
                    if ((phase == PHASE_TA) && (bit_index == 6'd1)) begin
                        if (mdio_in != 1'b0)
                            ta_error <= 1'b1;
                    end

                    if (phase == PHASE_DATA) begin
                        read_shift <= {read_shift[14:0], mdio_in};
                        if (bit_index == 6'd15) begin
                            read_data <= {read_shift[14:0], mdio_in};
                            done      <= 1'b1;
                        end
                    end
                end else begin
                    // Falling MDC edge: advance the transmit/sample phase.
                    mdc <= 1'b0;
                    case (phase)
                        PHASE_PREAMBLE: begin
                            if (bit_index == 6'd31) begin
                                phase     <= PHASE_ST;
                                bit_index <= 6'd0;
                            end else begin
                                bit_index <= bit_index + 1'b1;
                            end
                        end
                        PHASE_ST: begin
                            if (bit_index == 6'd1) begin
                                phase     <= PHASE_OP;
                                bit_index <= 6'd0;
                            end else begin
                                bit_index <= bit_index + 1'b1;
                            end
                        end
                        PHASE_OP: begin
                            if (bit_index == 6'd1) begin
                                phase     <= PHASE_PHYAD;
                                bit_index <= 6'd0;
                            end else begin
                                bit_index <= bit_index + 1'b1;
                            end
                        end
                        PHASE_PHYAD: begin
                            if (bit_index == 6'd4) begin
                                phase     <= PHASE_REGAD;
                                bit_index <= 6'd0;
                            end else begin
                                bit_index <= bit_index + 1'b1;
                            end
                        end
                        PHASE_REGAD: begin
                            if (bit_index == 6'd4) begin
                                phase     <= PHASE_TA;
                                bit_index <= 6'd0;
                            end else begin
                                bit_index <= bit_index + 1'b1;
                            end
                        end
                        PHASE_TA: begin
                            if (bit_index == 6'd1) begin
                                phase     <= PHASE_DATA;
                                bit_index <= 6'd0;
                            end else begin
                                bit_index <= bit_index + 1'b1;
                            end
                        end
                        PHASE_DATA: begin
                            if (bit_index == 6'd15) begin
                                busy      <= 1'b0;
                                phase     <= PHASE_IDLE;
                                bit_index <= 6'd0;
                            end else begin
                                bit_index <= bit_index + 1'b1;
                            end
                        end
                        default: begin
                            busy      <= 1'b0;
                            phase     <= PHASE_IDLE;
                            bit_index <= 6'd0;
                        end
                    endcase
                end
            end else begin
                mdc_divider <= mdc_divider + 1'b1;
            end
        end else begin
            // Remain electrically idle between reads.
            mdc         <= 1'b0;
            mdc_divider <= 6'd0;
            phase       <= PHASE_IDLE;
            bit_index   <= 6'd0;
        end
    end
endmodule
