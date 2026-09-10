`timescale 1ns / 1ps

// One-byte, four-wire SPI master for the AD9517 serial control port.
//
// Every accepted request transfers one 16-bit long instruction followed by
// one data byte.  The instruction is {R/W, W1:W0=2'b00, address[12:0]}:
// rw_i=0 writes write_data_i and rw_i=1 reads read_data_o.  Both instruction
// and data are shifted most-significant bit first.
//
// The block remains entirely in clk_i's clock domain.  pll_sclk_o is only a
// registered output waveform; it is not used as an internal FPGA clock.  With
// the default parameters, 100 MHz clk_i is divided into a 5 MHz SPI clock.
module ad9517_spi_master #(
    parameter integer CLK_FREQ_HZ  = 100000000,
    parameter integer SCLK_FREQ_HZ =   5000000
) (
    input  wire        clk_i,
    input  wire        rst_i,

    // start_i is a one-clk_i-cycle request and is accepted only when busy_o=0.
    input  wire        start_i,
    input  wire        rw_i,          // 0: write, 1: read
    input  wire [12:0] addr_i,
    input  wire [7:0]  write_data_i,

    output reg         busy_o,
    output reg         done_o,
    output reg  [7:0]  read_data_o,
    output reg         error_o,

    // Board-level AD9517 four-wire serial interface.
    output reg         pll_cs_n_o,
    output reg         pll_sclk_o,
    output reg         pll_sdio_o,    // MOSI: FPGA -> AD9517 SDIO
    input  wire        pll_sdo_i      // MISO: AD9517 SDO -> FPGA
);

    // Number of clk_i periods in one half SCLK period.  The clock parameters
    // must describe an exact integer divider; an invalid setting is reported
    // when a request is made instead of starting a malformed transaction.
    // SCLK_DIVISOR is guarded against zero solely to keep elaboration legal
    // for an invalid parameter override; CLOCK_SETTING_VALID still rejects it.
    localparam integer SCLK_DIVISOR =
        (SCLK_FREQ_HZ > 0) ? (2 * SCLK_FREQ_HZ) : 1;
    localparam integer HALF_PERIOD_CYCLES =
        CLK_FREQ_HZ / SCLK_DIVISOR;
    localparam integer CLOCK_SETTING_VALID =
        (SCLK_FREQ_HZ > 0) &&
        (SCLK_FREQ_HZ <= 25000000) &&
        (CLK_FREQ_HZ >= SCLK_DIVISOR) &&
        ((CLK_FREQ_HZ % SCLK_DIVISOR) == 0);

    // edge_count is the number of rising SCLK edges already completed.  The
    // first 16 edges transfer the instruction and the final 8 transfer data.
    reg [4:0]  edge_count;
    reg [23:0] tx_shift;
    reg [7:0]  read_shift;
    reg        rw_latched;
    integer    half_period_count;

    always @(posedge clk_i) begin
        if (rst_i) begin
            busy_o           <= 1'b0;
            done_o           <= 1'b0;
            read_data_o      <= 8'h00;
            error_o          <= 1'b0;
            pll_cs_n_o       <= 1'b1;
            pll_sclk_o       <= 1'b0;
            pll_sdio_o       <= 1'b0;
            edge_count       <= 5'd0;
            tx_shift         <= 24'h000000;
            read_shift       <= 8'h00;
            rw_latched       <= 1'b0;
            half_period_count <= 0;
        end else begin
            // Completion and request-error indications last exactly one clk_i
            // cycle.  read_data_o retains the most recent completed read.
            done_o  <= 1'b0;
            error_o <= 1'b0;

            if (!busy_o) begin
                // Electrical idle is always CS# high and SCLK low (CPOL=0).
                pll_cs_n_o        <= 1'b1;
                pll_sclk_o        <= 1'b0;
                pll_sdio_o        <= 1'b0;
                edge_count        <= 5'd0;
                half_period_count <= 0;

                if (start_i) begin
                    if (!CLOCK_SETTING_VALID) begin
                        // Static parameter error: reject this request.  done_o
                        // is also asserted so a waiting controller can retire
                        // the failed transaction without hanging indefinitely.
                        done_o  <= 1'b1;
                        error_o <= 1'b1;
                    end else begin
                        busy_o     <= 1'b1;
                        pll_cs_n_o <= 1'b0;
                        rw_latched <= rw_i;
                        read_shift <= 8'h00;

                        // Read transactions drive zeros during the data phase;
                        // the actual return byte is received on pll_sdo_i.
                        tx_shift <= {
                            rw_i,
                            2'b00,
                            addr_i,
                            (rw_i ? 8'h00 : write_data_i)
                        };

                        // Place the very first (R/W) bit on SDIO immediately.
                        // It is therefore stable for a complete half-period
                        // before the first rising SCLK edge.
                        pll_sdio_o <= rw_i;
                    end
                end
            end else begin
                // start_i while busy is a caller protocol violation.  It does
                // not disturb the transaction already in progress.
                if (start_i)
                    error_o <= 1'b1;

                if (half_period_count == (HALF_PERIOD_CYCLES - 1)) begin
                    half_period_count <= 0;

                    if (!pll_sclk_o) begin
                        // Rising SCLK edge.  The AD9517 samples SDIO here.  On
                        // reads, SDO was launched by the AD9517 on the preceding
                        // falling edge, so it has one half-period to settle.
                        pll_sclk_o <= 1'b1;

                        if (rw_latched && (edge_count >= 5'd16))
                            read_shift <= {read_shift[6:0], pll_sdo_i};

                        edge_count <= edge_count + 1'b1;
                    end else begin
                        // Falling SCLK edge.  Change SDIO only here, providing
                        // a complete half-period of setup before the next rise.
                        pll_sclk_o <= 1'b0;

                        if (edge_count == 5'd24) begin
                            // The final bit was sampled one half-period ago.
                            // Return to idle only after bringing SCLK low.
                            pll_cs_n_o  <= 1'b1;
                            pll_sdio_o  <= 1'b0;
                            busy_o      <= 1'b0;
                            done_o      <= 1'b1;
                            edge_count  <= 5'd0;

                            if (rw_latched)
                                read_data_o <= read_shift;
                        end else begin
                            tx_shift   <= {tx_shift[22:0], 1'b0};
                            pll_sdio_o <= tx_shift[22];
                        end
                    end
                end else begin
                    half_period_count <= half_period_count + 1;
                end
            end
        end
    end

endmodule
