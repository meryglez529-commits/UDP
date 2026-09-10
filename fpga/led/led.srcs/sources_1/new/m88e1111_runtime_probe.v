`timescale 1ns / 1ps

// One-shot-per-round, read-only runtime probe for the strapped M88E1111.
// The sequence repeats after a 100 ms idle interval so that an ILA can be
// armed after volatile JTAG configuration without requiring a PHY write/VIO.
module m88e1111_runtime_probe (
    input  wire        clk,
    input  wire        mdio_in,
    output wire        mdc,
    output wire        mdio_drive_low,
    output wire [47:0] debug_bus,
    output wire [15:0] phy_id1,
    output wire [15:0] phy_id2,
    output wire [15:0] mode_reg27,
    output wire [15:0] bmcr,
    output wire [15:0] anar,
    output wire [15:0] gctrl,
    output wire [15:0] bmsr_first,
    output wire [15:0] bmsr_second
);
    // The first transaction starts 1 ms after configuration. Subsequent
    // rounds are separated by 100 ms of MDIO high-Z / MDC-low idle time.
    parameter [16:0] STARTUP_CYCLES     = 17'd100000;
    parameter [23:0] REPEAT_IDLE_CYCLES = 24'd10000000;
    // Open-drain self-test timing at the 100 MHz system clock.  It never
    // toggles MDC: the PHY cannot interpret it as a Clause 22 command.
    parameter [9:0]  SELFTEST_HOLD_CYCLES    = 10'd1000;
    parameter [5:0]  SELFTEST_MEASURE_CYCLES = 6'd40;

    localparam [2:0] PROBE_BOOT   = 3'd0;
    localparam [2:0] PROBE_START  = 3'd1;
    localparam [2:0] PROBE_WAIT   = 3'd2;
    localparam [2:0] PROBE_FINISH = 3'd3;
    localparam [2:0] PROBE_REPEAT = 3'd4;
    localparam [2:0] PROBE_SELFTEST = 3'd5;

    localparam [1:0] SELFTEST_RELEASE_INITIAL = 2'd0;
    localparam [1:0] SELFTEST_DRIVE_LOW       = 2'd1;
    localparam [1:0] SELFTEST_RELEASE_MEASURE = 2'd2;

    reg [2:0]  probe_state;
    reg [2:0]  transaction_index;
    reg [16:0] startup_counter;
    reg [23:0] repeat_counter;
    reg        start_read;
    reg        sequence_done;

    reg [1:0]  selftest_phase;
    reg [9:0]  selftest_counter;
    reg        selftest_idle_high;
    reg        selftest_low_is_low;
    reg        selftest_release_100ns_high;
    reg        selftest_release_250ns_high;
    reg        selftest_release_400ns_high;

    reg [15:0] phy_id1_r;
    reg [15:0] phy_id2_r;
    reg [15:0] mode_reg27_r;
    reg [15:0] bmcr_r;
    reg [15:0] anar_r;
    reg [15:0] gctrl_r;
    reg [15:0] bmsr_first_r;
    reg [15:0] bmsr_second_r;

    wire        reader_mdc;
    wire        reader_drive_low;
    wire        reader_busy;
    wire        reader_done;
    wire        reader_ta_error;
    wire [15:0] reader_data;
    wire [2:0]  reader_phase;
    wire [5:0]  reader_bit_index;
    wire [4:0]  scheduled_reg;
    wire        selftest_active;

    function [4:0] register_for_index;
        input [2:0] index;
        begin
            case (index)
                3'd0: register_for_index = 5'd2;   // PHYID1
                3'd1: register_for_index = 5'd3;   // PHYID2
                3'd2: register_for_index = 5'd27;  // HWCFG mode
                3'd3: register_for_index = 5'd0;   // BMCR
                3'd4: register_for_index = 5'd4;   // ANAR
                3'd5: register_for_index = 5'd9;   // 1000BASE-T control
                3'd6: register_for_index = 5'd1;   // BMSR, latch-low read
                default: register_for_index = 5'd1; // BMSR, effective read
            endcase
        end
    endfunction

    assign scheduled_reg = register_for_index(transaction_index);

    mdio_clause22_reader u_reader (
        .clk             (clk),
        .start           (start_read),
        .phy_addr        (5'h07),
        .reg_addr        (scheduled_reg),
        .mdio_in         (mdio_in),
        .mdc             (reader_mdc),
        .mdio_drive_low  (reader_drive_low),
        .busy            (reader_busy),
        .done            (reader_done),
        .ta_error        (reader_ta_error),
        .read_data       (reader_data),
        .phase           (reader_phase),
        .bit_index       (reader_bit_index)
    );

    assign phy_id1     = phy_id1_r;
    assign phy_id2     = phy_id2_r;
    assign mode_reg27  = mode_reg27_r;
    assign bmcr        = bmcr_r;
    assign anar        = anar_r;
    assign gctrl       = gctrl_r;
    assign bmsr_first  = bmsr_first_r;
    assign bmsr_second = bmsr_second_r;

    // During the self-test MDC is held low, while MDIO is either released or
    // driven low.  The usual reader remains idle until the test completes.
    assign selftest_active = (probe_state == PROBE_SELFTEST);
    assign mdc = selftest_active ? 1'b0 : reader_mdc;
    assign mdio_drive_low = selftest_active &&
                            (selftest_phase == SELFTEST_DRIVE_LOW) ? 1'b1 :
                            (selftest_active ? 1'b0 : reader_drive_low);

    // [47:43] is the one-shot/repeating open-drain self-test evidence:
    // idle release, active low, and release sampled at 100/250/400 ns.
    // [42:0] is the live MDIO reader evidence.
    assign debug_bus = {
        selftest_release_400ns_high,
        selftest_release_250ns_high,
        selftest_release_100ns_high,
        selftest_low_is_low,
        selftest_idle_high,
        probe_state,
        reader_phase,
        reader_bit_index,
        transaction_index,
        scheduled_reg,
        reader_data,
        mdio_drive_low,
        mdio_in,
        mdc,
        reader_busy,
        reader_done,
        reader_ta_error,
        sequence_done
    };

    initial begin
        probe_state       = PROBE_BOOT;
        transaction_index = 3'd0;
        startup_counter   = 17'd0;
        repeat_counter    = 24'd0;
        start_read        = 1'b0;
        sequence_done     = 1'b0;
        selftest_phase               = SELFTEST_RELEASE_INITIAL;
        selftest_counter             = 10'd0;
        selftest_idle_high           = 1'b0;
        selftest_low_is_low          = 1'b0;
        selftest_release_100ns_high  = 1'b0;
        selftest_release_250ns_high  = 1'b0;
        selftest_release_400ns_high  = 1'b0;
        phy_id1_r         = 16'd0;
        phy_id2_r         = 16'd0;
        mode_reg27_r      = 16'd0;
        bmcr_r            = 16'd0;
        anar_r            = 16'd0;
        gctrl_r           = 16'd0;
        bmsr_first_r      = 16'd0;
        bmsr_second_r     = 16'd0;
    end

    always @(posedge clk) begin
        // start_read is a single system-clock request. The reader begins its
        // 1 MHz waveform from MDC-low after seeing that request.
        start_read <= 1'b0;

        case (probe_state)
            PROBE_BOOT: begin
                if (startup_counter == (STARTUP_CYCLES - 1'b1)) begin
                    selftest_phase               <= SELFTEST_RELEASE_INITIAL;
                    selftest_counter             <= 10'd0;
                    selftest_idle_high           <= 1'b0;
                    selftest_low_is_low          <= 1'b0;
                    selftest_release_100ns_high  <= 1'b0;
                    selftest_release_250ns_high  <= 1'b0;
                    selftest_release_400ns_high  <= 1'b0;
                    probe_state <= PROBE_SELFTEST;
                end else begin
                    startup_counter <= startup_counter + 1'b1;
                end
            end

            PROBE_SELFTEST: begin
                case (selftest_phase)
                    SELFTEST_RELEASE_INITIAL: begin
                        if (selftest_counter == (SELFTEST_HOLD_CYCLES - 1'b1)) begin
                            selftest_idle_high <= mdio_in;
                            selftest_counter   <= 10'd0;
                            selftest_phase     <= SELFTEST_DRIVE_LOW;
                        end else begin
                            selftest_counter <= selftest_counter + 1'b1;
                        end
                    end

                    SELFTEST_DRIVE_LOW: begin
                        if (selftest_counter == (SELFTEST_HOLD_CYCLES - 1'b1)) begin
                            selftest_low_is_low <= ~mdio_in;
                            selftest_counter    <= 10'd0;
                            selftest_phase      <= SELFTEST_RELEASE_MEASURE;
                        end else begin
                            selftest_counter <= selftest_counter + 1'b1;
                        end
                    end

                    default: begin
                        // Counter 0 is the first 10 ns sample after release.
                        if (selftest_counter == 10'd9)
                            selftest_release_100ns_high <= mdio_in;
                        if (selftest_counter == 10'd24)
                            selftest_release_250ns_high <= mdio_in;
                        if (selftest_counter == 10'd39)
                            selftest_release_400ns_high <= mdio_in;

                        if (selftest_counter == (SELFTEST_MEASURE_CYCLES - 1'b1)) begin
                            selftest_counter <= 10'd0;
                            probe_state      <= PROBE_START;
                        end else begin
                            selftest_counter <= selftest_counter + 1'b1;
                        end
                    end
                endcase
            end

            PROBE_START: begin
                if (!reader_busy) begin
                    start_read <= 1'b1;
                    if (transaction_index == 3'd0)
                        sequence_done <= 1'b0;
                    probe_state <= PROBE_WAIT;
                end
            end

            PROBE_WAIT: begin
                if (reader_done) begin
                    case (transaction_index)
                        3'd0: phy_id1_r       <= reader_data;
                        3'd1: phy_id2_r       <= reader_data;
                        3'd2: mode_reg27_r    <= reader_data;
                        3'd3: bmcr_r          <= reader_data;
                        3'd4: anar_r          <= reader_data;
                        3'd5: gctrl_r         <= reader_data;
                        3'd6: bmsr_first_r    <= reader_data;
                        default: bmsr_second_r <= reader_data;
                    endcase
                    probe_state <= PROBE_FINISH;
                end
            end

            PROBE_FINISH: begin
                if (!reader_busy) begin
                    if (transaction_index == 3'd7) begin
                        sequence_done  <= 1'b1;
                        repeat_counter <= 24'd0;
                        probe_state    <= PROBE_REPEAT;
                    end else begin
                        transaction_index <= transaction_index + 1'b1;
                        probe_state       <= PROBE_START;
                    end
                end
            end

            PROBE_REPEAT: begin
                if (repeat_counter == (REPEAT_IDLE_CYCLES - 1'b1)) begin
                    transaction_index <= 3'd0;
                    repeat_counter    <= 24'd0;
                    selftest_phase               <= SELFTEST_RELEASE_INITIAL;
                    selftest_counter             <= 10'd0;
                    selftest_idle_high           <= 1'b0;
                    selftest_low_is_low          <= 1'b0;
                    selftest_release_100ns_high  <= 1'b0;
                    selftest_release_250ns_high  <= 1'b0;
                    selftest_release_400ns_high  <= 1'b0;
                    probe_state       <= PROBE_SELFTEST;
                end else begin
                    repeat_counter <= repeat_counter + 1'b1;
                end
            end

            default: begin
                probe_state       <= PROBE_BOOT;
                transaction_index <= 3'd0;
                startup_counter   <= 17'd0;
            end
        endcase
    end
endmodule
