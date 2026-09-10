`timescale 1ns / 1ps

// AD9517-4 deterministic initialization sequencer.
//
// All logic runs in clk_i.  The controller owns transaction ordering while
// ad9517_spi_master owns pin timing.  The base profile is written with OUT0
// safely powered down, read back from the active register bank, calibrated,
// and only then changed to the normal 125 MHz output setting.
module ad9517_init_ctrl #(
    parameter integer RESET_ASSERT_CYCLES  = 100,
    parameter integer RESET_RELEASE_CYCLES = 1000,
    parameter integer SPI_TIMEOUT_CYCLES   = 2000,
    parameter integer CAL_TIMEOUT_CYCLES   = 1000000,
    parameter integer LOCK_TIMEOUT_CYCLES  = 2000000
) (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        start_i,
    input  wire        restart_i,

    output reg         spi_start_o,
    output reg         spi_rw_o,
    output reg  [12:0] spi_addr_o,
    output reg  [7:0]  spi_write_data_o,
    input  wire        spi_busy_i,
    input  wire        spi_done_i,
    input  wire        spi_error_i,
    input  wire [7:0]  spi_read_data_i,

    output reg  [5:0]  profile_index_o,
    input  wire [12:0] profile_addr_i,
    input  wire [7:0]  profile_data_i,
    input  wire [7:0]  profile_verify_mask_i,
    input  wire        profile_entry_valid_i,
    input  wire        profile_last_i,

    input  wire        pll_locked_i,
    input  wire        lock_lost_i,
    output reg         ld_filter_enable_o,

    output wire        busy_o,
    output reg         clock_ready_o,
    output reg         error_o,
    output reg  [3:0]  error_code_o,
    output reg  [7:0]  last_read_o,
    output reg  [12:0] last_addr_o,
    output reg  [4:0]  state_o,
    output reg         pll_reset_n_o
);

    localparam integer RESET_ASSERT_TARGET =
        (RESET_ASSERT_CYCLES < 1) ? 1 : RESET_ASSERT_CYCLES;
    localparam integer RESET_RELEASE_TARGET =
        (RESET_RELEASE_CYCLES < 1) ? 1 : RESET_RELEASE_CYCLES;
    localparam integer SPI_TIMEOUT_TARGET =
        (SPI_TIMEOUT_CYCLES < 1) ? 1 : SPI_TIMEOUT_CYCLES;
    localparam integer CAL_TIMEOUT_TARGET =
        (CAL_TIMEOUT_CYCLES < 1) ? 1 : CAL_TIMEOUT_CYCLES;
    localparam integer LOCK_TIMEOUT_TARGET =
        (LOCK_TIMEOUT_CYCLES < 1) ? 1 : LOCK_TIMEOUT_CYCLES;

    localparam [3:0] ERR_NONE          = 4'h0;
    localparam [3:0] ERR_SPI_TIMEOUT   = 4'h1;
    localparam [3:0] ERR_SPI_ENGINE    = 4'h2;
    localparam [3:0] ERR_PART_ID       = 4'h3;
    localparam [3:0] ERR_VERIFY        = 4'h4;
    localparam [3:0] ERR_CAL_TIMEOUT   = 4'h5;
    localparam [3:0] ERR_LOCK_TIMEOUT  = 4'h6;
    localparam [3:0] ERR_RUNTIME_LOSS  = 4'h7;
    localparam [3:0] ERR_PROFILE       = 4'h8;

    localparam [4:0] ST_IDLE             = 5'd0;
    localparam [4:0] ST_RESET_ASSERT     = 5'd1;
    localparam [4:0] ST_RESET_RELEASE    = 5'd2;
    localparam [4:0] ST_SERIAL_REQ       = 5'd3;
    localparam [4:0] ST_SERIAL_WAIT      = 5'd4;
    localparam [4:0] ST_ID_REQ           = 5'd5;
    localparam [4:0] ST_ID_WAIT          = 5'd6;
    localparam [4:0] ST_READCTRL_REQ     = 5'd7;
    localparam [4:0] ST_READCTRL_WAIT    = 5'd8;
    localparam [4:0] ST_BASE_REQ         = 5'd9;
    localparam [4:0] ST_BASE_WAIT        = 5'd10;
    localparam [4:0] ST_UPDATE_BASE_REQ  = 5'd11;
    localparam [4:0] ST_UPDATE_BASE_WAIT = 5'd12;
    localparam [4:0] ST_VERIFY_REQ       = 5'd13;
    localparam [4:0] ST_VERIFY_WAIT      = 5'd14;
    localparam [4:0] ST_CAL_REQ          = 5'd15;
    localparam [4:0] ST_CAL_WAIT         = 5'd16;
    localparam [4:0] ST_UPDATE_CAL_REQ   = 5'd17;
    localparam [4:0] ST_UPDATE_CAL_WAIT  = 5'd18;
    localparam [4:0] ST_STATUS_REQ       = 5'd19;
    localparam [4:0] ST_STATUS_WAIT      = 5'd20;
    localparam [4:0] ST_OUT0_REQ         = 5'd21;
    localparam [4:0] ST_OUT0_WAIT        = 5'd22;
    localparam [4:0] ST_UPDATE_OUT_REQ   = 5'd23;
    localparam [4:0] ST_UPDATE_OUT_WAIT  = 5'd24;
    localparam [4:0] ST_WAIT_LD          = 5'd25;
    localparam [4:0] ST_READY            = 5'd26;
    localparam [4:0] ST_FAULT            = 5'd27;

    integer delay_count;
    integer transaction_count;
    integer phase_count;

    assign busy_o = (state_o != ST_IDLE) &&
                    (state_o != ST_READY) &&
                    (state_o != ST_FAULT);

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_o             <= ST_IDLE;
            spi_start_o         <= 1'b0;
            spi_rw_o            <= 1'b0;
            spi_addr_o          <= 13'h0000;
            spi_write_data_o    <= 8'h00;
            profile_index_o     <= 6'd0;
            ld_filter_enable_o  <= 1'b0;
            clock_ready_o       <= 1'b0;
            error_o             <= 1'b0;
            error_code_o        <= ERR_NONE;
            last_read_o         <= 8'h00;
            last_addr_o         <= 13'h0000;
            pll_reset_n_o       <= 1'b0;
            delay_count         <= 0;
            transaction_count   <= 0;
            phase_count         <= 0;
        end else begin
            // A request is asserted for one clk_i cycle only.  Request states
            // set it below and immediately advance to their wait state.
            spi_start_o <= 1'b0;

            case (state_o)
                ST_IDLE: begin
                    pll_reset_n_o      <= 1'b0;
                    ld_filter_enable_o <= 1'b0;
                    clock_ready_o      <= 1'b0;
                    if (start_i || restart_i) begin
                        error_o           <= 1'b0;
                        error_code_o      <= ERR_NONE;
                        profile_index_o   <= 6'd0;
                        delay_count       <= 0;
                        phase_count       <= 0;
                        state_o           <= ST_RESET_ASSERT;
                    end
                end

                ST_RESET_ASSERT: begin
                    pll_reset_n_o <= 1'b0;
                    if (delay_count >= (RESET_ASSERT_TARGET - 1)) begin
                        delay_count   <= 0;
                        pll_reset_n_o <= 1'b1;
                        state_o       <= ST_RESET_RELEASE;
                    end else begin
                        delay_count <= delay_count + 1;
                    end
                end

                ST_RESET_RELEASE: begin
                    pll_reset_n_o <= 1'b1;
                    if (delay_count >= (RESET_RELEASE_TARGET - 1)) begin
                        delay_count <= 0;
                        state_o     <= ST_SERIAL_REQ;
                    end else begin
                        delay_count <= delay_count + 1;
                    end
                end

                ST_SERIAL_REQ: begin
                    spi_rw_o         <= 1'b0;
                    spi_addr_o       <= 13'h000;
                    spi_write_data_o <= 8'h99;
                    last_addr_o      <= 13'h000;
                    spi_start_o      <= 1'b1;
                    transaction_count <= 0;
                    state_o          <= ST_SERIAL_WAIT;
                end

                ST_SERIAL_WAIT: begin
                    if (spi_done_i) begin
                        if (spi_error_i) begin
                            error_o <= 1'b1; error_code_o <= ERR_SPI_ENGINE;
                            pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                        end else begin
                            state_o <= ST_ID_REQ;
                        end
                    end else if (transaction_count >= (SPI_TIMEOUT_TARGET - 1)) begin
                        error_o <= 1'b1; error_code_o <= ERR_SPI_TIMEOUT;
                        pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                    end else transaction_count <= transaction_count + 1;
                end

                ST_ID_REQ: begin
                    spi_rw_o         <= 1'b1;
                    spi_addr_o       <= 13'h003;
                    spi_write_data_o <= 8'h00;
                    last_addr_o      <= 13'h003;
                    spi_start_o      <= 1'b1;
                    transaction_count <= 0;
                    state_o          <= ST_ID_WAIT;
                end

                ST_ID_WAIT: begin
                    if (spi_done_i) begin
                        last_read_o <= spi_read_data_i;
                        if (spi_error_i) begin
                            error_o <= 1'b1; error_code_o <= ERR_SPI_ENGINE;
                            pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                        end else if (spi_read_data_i != 8'hD3) begin
                            error_o <= 1'b1; error_code_o <= ERR_PART_ID;
                            pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                        end else state_o <= ST_READCTRL_REQ;
                    end else if (transaction_count >= (SPI_TIMEOUT_TARGET - 1)) begin
                        error_o <= 1'b1; error_code_o <= ERR_SPI_TIMEOUT;
                        pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                    end else transaction_count <= transaction_count + 1;
                end

                ST_READCTRL_REQ: begin
                    spi_rw_o         <= 1'b0;
                    spi_addr_o       <= 13'h004;
                    spi_write_data_o <= 8'h01;
                    last_addr_o      <= 13'h004;
                    spi_start_o      <= 1'b1;
                    transaction_count <= 0;
                    state_o          <= ST_READCTRL_WAIT;
                end

                ST_READCTRL_WAIT: begin
                    if (spi_done_i) begin
                        if (spi_error_i) begin
                            error_o <= 1'b1; error_code_o <= ERR_SPI_ENGINE;
                            pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                        end else begin
                            profile_index_o <= 6'd0;
                            state_o <= ST_BASE_REQ;
                        end
                    end else if (transaction_count >= (SPI_TIMEOUT_TARGET - 1)) begin
                        error_o <= 1'b1; error_code_o <= ERR_SPI_TIMEOUT;
                        pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                    end else transaction_count <= transaction_count + 1;
                end

                ST_BASE_REQ: begin
                    if (!profile_entry_valid_i) begin
                        error_o <= 1'b1; error_code_o <= ERR_PROFILE;
                        pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                    end else begin
                        spi_rw_o         <= 1'b0;
                        spi_addr_o       <= profile_addr_i;
                        spi_write_data_o <= profile_data_i;
                        last_addr_o      <= profile_addr_i;
                        spi_start_o      <= 1'b1;
                        transaction_count <= 0;
                        state_o          <= ST_BASE_WAIT;
                    end
                end

                ST_BASE_WAIT: begin
                    if (spi_done_i) begin
                        if (spi_error_i) begin
                            error_o <= 1'b1; error_code_o <= ERR_SPI_ENGINE;
                            pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                        end else if (profile_last_i) begin
                            state_o <= ST_UPDATE_BASE_REQ;
                        end else begin
                            profile_index_o <= profile_index_o + 1'b1;
                            state_o <= ST_BASE_REQ;
                        end
                    end else if (transaction_count >= (SPI_TIMEOUT_TARGET - 1)) begin
                        error_o <= 1'b1; error_code_o <= ERR_SPI_TIMEOUT;
                        pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                    end else transaction_count <= transaction_count + 1;
                end

                ST_UPDATE_BASE_REQ: begin
                    spi_rw_o         <= 1'b0;
                    spi_addr_o       <= 13'h232;
                    spi_write_data_o <= 8'h01;
                    last_addr_o      <= 13'h232;
                    spi_start_o      <= 1'b1;
                    transaction_count <= 0;
                    state_o          <= ST_UPDATE_BASE_WAIT;
                end

                ST_UPDATE_BASE_WAIT: begin
                    if (spi_done_i) begin
                        if (spi_error_i) begin
                            error_o <= 1'b1; error_code_o <= ERR_SPI_ENGINE;
                            pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                        end else begin
                            profile_index_o <= 6'd0;
                            state_o <= ST_VERIFY_REQ;
                        end
                    end else if (transaction_count >= (SPI_TIMEOUT_TARGET - 1)) begin
                        error_o <= 1'b1; error_code_o <= ERR_SPI_TIMEOUT;
                        pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                    end else transaction_count <= transaction_count + 1;
                end

                ST_VERIFY_REQ: begin
                    if (!profile_entry_valid_i) begin
                        error_o <= 1'b1; error_code_o <= ERR_PROFILE;
                        pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                    end else begin
                        spi_rw_o         <= 1'b1;
                        spi_addr_o       <= profile_addr_i;
                        spi_write_data_o <= 8'h00;
                        last_addr_o      <= profile_addr_i;
                        spi_start_o      <= 1'b1;
                        transaction_count <= 0;
                        state_o          <= ST_VERIFY_WAIT;
                    end
                end

                ST_VERIFY_WAIT: begin
                    if (spi_done_i) begin
                        last_read_o <= spi_read_data_i;
                        if (spi_error_i) begin
                            error_o <= 1'b1; error_code_o <= ERR_SPI_ENGINE;
                            pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                        end else if (((spi_read_data_i ^ profile_data_i) &
                                      profile_verify_mask_i) != 8'h00) begin
                            error_o <= 1'b1; error_code_o <= ERR_VERIFY;
                            pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                        end else if (profile_last_i) begin
                            state_o <= ST_CAL_REQ;
                        end else begin
                            profile_index_o <= profile_index_o + 1'b1;
                            state_o <= ST_VERIFY_REQ;
                        end
                    end else if (transaction_count >= (SPI_TIMEOUT_TARGET - 1)) begin
                        error_o <= 1'b1; error_code_o <= ERR_SPI_TIMEOUT;
                        pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                    end else transaction_count <= transaction_count + 1;
                end

                ST_CAL_REQ: begin
                    spi_rw_o         <= 1'b0;
                    spi_addr_o       <= 13'h018;
                    spi_write_data_o <= 8'h45;
                    last_addr_o      <= 13'h018;
                    spi_start_o      <= 1'b1;
                    transaction_count <= 0;
                    state_o          <= ST_CAL_WAIT;
                end

                ST_CAL_WAIT: begin
                    if (spi_done_i) begin
                        if (spi_error_i) begin
                            error_o <= 1'b1; error_code_o <= ERR_SPI_ENGINE;
                            pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                        end else state_o <= ST_UPDATE_CAL_REQ;
                    end else if (transaction_count >= (SPI_TIMEOUT_TARGET - 1)) begin
                        error_o <= 1'b1; error_code_o <= ERR_SPI_TIMEOUT;
                        pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                    end else transaction_count <= transaction_count + 1;
                end

                ST_UPDATE_CAL_REQ: begin
                    spi_rw_o         <= 1'b0;
                    spi_addr_o       <= 13'h232;
                    spi_write_data_o <= 8'h01;
                    last_addr_o      <= 13'h232;
                    spi_start_o      <= 1'b1;
                    transaction_count <= 0;
                    state_o          <= ST_UPDATE_CAL_WAIT;
                end

                ST_UPDATE_CAL_WAIT: begin
                    if (spi_done_i) begin
                        if (spi_error_i) begin
                            error_o <= 1'b1; error_code_o <= ERR_SPI_ENGINE;
                            pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                        end else begin
                            phase_count <= 0;
                            state_o <= ST_STATUS_REQ;
                        end
                    end else if (transaction_count >= (SPI_TIMEOUT_TARGET - 1)) begin
                        error_o <= 1'b1; error_code_o <= ERR_SPI_TIMEOUT;
                        pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                    end else transaction_count <= transaction_count + 1;
                end

                ST_STATUS_REQ: begin
                    spi_rw_o         <= 1'b1;
                    spi_addr_o       <= 13'h01F;
                    spi_write_data_o <= 8'h00;
                    last_addr_o      <= 13'h01F;
                    spi_start_o      <= 1'b1;
                    transaction_count <= 0;
                    if (phase_count < CAL_TIMEOUT_TARGET)
                        phase_count <= phase_count + 1;
                    state_o <= ST_STATUS_WAIT;
                end

                ST_STATUS_WAIT: begin
                    if (phase_count < CAL_TIMEOUT_TARGET)
                        phase_count <= phase_count + 1;

                    if (spi_done_i) begin
                        last_read_o <= spi_read_data_i;
                        if (spi_error_i) begin
                            error_o <= 1'b1; error_code_o <= ERR_SPI_ENGINE;
                            pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                        end else if (spi_read_data_i[6] && spi_read_data_i[0]) begin
                            state_o <= ST_OUT0_REQ;
                        end else if (phase_count >= (CAL_TIMEOUT_TARGET - 1)) begin
                            error_o <= 1'b1;
                            error_code_o <= spi_read_data_i[6] ?
                                            ERR_LOCK_TIMEOUT : ERR_CAL_TIMEOUT;
                            pll_reset_n_o <= 1'b0;
                            state_o <= ST_FAULT;
                        end else begin
                            state_o <= ST_STATUS_REQ;
                        end
                    end else if (transaction_count >= (SPI_TIMEOUT_TARGET - 1)) begin
                        error_o <= 1'b1; error_code_o <= ERR_SPI_TIMEOUT;
                        pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                    end else transaction_count <= transaction_count + 1;
                end

                ST_OUT0_REQ: begin
                    spi_rw_o         <= 1'b0;
                    spi_addr_o       <= 13'h0F0;
                    spi_write_data_o <= 8'h08;
                    last_addr_o      <= 13'h0F0;
                    spi_start_o      <= 1'b1;
                    transaction_count <= 0;
                    state_o          <= ST_OUT0_WAIT;
                end

                ST_OUT0_WAIT: begin
                    if (spi_done_i) begin
                        if (spi_error_i) begin
                            error_o <= 1'b1; error_code_o <= ERR_SPI_ENGINE;
                            pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                        end else state_o <= ST_UPDATE_OUT_REQ;
                    end else if (transaction_count >= (SPI_TIMEOUT_TARGET - 1)) begin
                        error_o <= 1'b1; error_code_o <= ERR_SPI_TIMEOUT;
                        pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                    end else transaction_count <= transaction_count + 1;
                end

                ST_UPDATE_OUT_REQ: begin
                    spi_rw_o         <= 1'b0;
                    spi_addr_o       <= 13'h232;
                    spi_write_data_o <= 8'h01;
                    last_addr_o      <= 13'h232;
                    spi_start_o      <= 1'b1;
                    transaction_count <= 0;
                    state_o          <= ST_UPDATE_OUT_WAIT;
                end

                ST_UPDATE_OUT_WAIT: begin
                    if (spi_done_i) begin
                        if (spi_error_i) begin
                            error_o <= 1'b1; error_code_o <= ERR_SPI_ENGINE;
                            pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                        end else begin
                            // Start a fresh 1 ms qualification window only
                            // after OUT0 has actually been enabled.
                            ld_filter_enable_o <= 1'b1;
                            phase_count <= 0;
                            state_o <= ST_WAIT_LD;
                        end
                    end else if (transaction_count >= (SPI_TIMEOUT_TARGET - 1)) begin
                        error_o <= 1'b1; error_code_o <= ERR_SPI_TIMEOUT;
                        pll_reset_n_o <= 1'b0; state_o <= ST_FAULT;
                    end else transaction_count <= transaction_count + 1;
                end

                ST_WAIT_LD: begin
                    if (pll_locked_i) begin
                        clock_ready_o <= 1'b1;
                        state_o <= ST_READY;
                    end else if (phase_count >= (LOCK_TIMEOUT_TARGET - 1)) begin
                        error_o <= 1'b1; error_code_o <= ERR_LOCK_TIMEOUT;
                        ld_filter_enable_o <= 1'b0;
                        pll_reset_n_o <= 1'b0;
                        state_o <= ST_FAULT;
                    end else phase_count <= phase_count + 1;
                end

                ST_READY: begin
                    clock_ready_o <= 1'b1;
                    if (lock_lost_i) begin
                        clock_ready_o <= 1'b0;
                        error_o <= 1'b1;
                        error_code_o <= ERR_RUNTIME_LOSS;
                        ld_filter_enable_o <= 1'b0;
                        pll_reset_n_o <= 1'b0;
                        state_o <= ST_FAULT;
                    end else if (restart_i) begin
                        clock_ready_o <= 1'b0;
                        error_o <= 1'b0;
                        error_code_o <= ERR_NONE;
                        ld_filter_enable_o <= 1'b0;
                        pll_reset_n_o <= 1'b0;
                        delay_count <= 0;
                        state_o <= ST_RESET_ASSERT;
                    end
                end

                ST_FAULT: begin
                    clock_ready_o      <= 1'b0;
                    ld_filter_enable_o <= 1'b0;
                    pll_reset_n_o      <= 1'b0;
                    if (restart_i) begin
                        error_o <= 1'b0;
                        error_code_o <= ERR_NONE;
                        delay_count <= 0;
                        state_o <= ST_RESET_ASSERT;
                    end
                end

                default: begin
                    error_o <= 1'b1;
                    error_code_o <= ERR_PROFILE;
                    clock_ready_o <= 1'b0;
                    ld_filter_enable_o <= 1'b0;
                    pll_reset_n_o <= 1'b0;
                    state_o <= ST_FAULT;
                end
            endcase
        end
    end

    // spi_busy_i is intentionally available for ILA/debug and interface
    // completeness. Completion and timeout, not a combinational busy level,
    // retire a request; this avoids coupling FSM progress to SPI internals.
    wire _unused_spi_busy = spi_busy_i;

endmodule
