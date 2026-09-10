`timescale 1ns / 1ps

// Board-level AD9517-only validation top.
//
// The design starts automatically after FPGA configuration and uses only the
// existing AA3 100 MHz oscillator.  It does not instantiate a GTX, Ethernet
// PCS/PMA, TEMAC, Clocking Wizard, or UDP logic.  LED1 is solid on only after
// configuration/readback/calibration/lock qualification all succeed.
module ad9517_clock_manager #(
    parameter integer SYS_CLK_FREQ_HZ      = 100000000,
    parameter integer SPI_SCLK_FREQ_HZ     = 5000000,
    parameter integer POR_CYCLES           = 1024,
    parameter integer RESET_ASSERT_CYCLES  = 100,
    parameter integer RESET_RELEASE_CYCLES = 1000,
    parameter integer SPI_TIMEOUT_CYCLES   = 2000,
    parameter integer CAL_TIMEOUT_CYCLES   = 1000000,
    parameter integer LOCK_TIMEOUT_CYCLES  = 2000000,
    parameter integer LOCK_STABLE_CYCLES   = 100000,
    parameter integer LOSS_FILTER_CYCLES   = 8,
    parameter integer ENABLE_ILA           = 1
) (
    input  wire sys_clk_i,
    output wire led1,

    output wire pll_cs_n_o,
    output wire pll_sclk_o,
    output wire pll_sdio_o,
    input  wire pll_sdo_i,
    output wire pll_ref_sel_o,
    input  wire pll_ld_i,
    output wire pll_reset_n_o
);

    localparam integer POR_TARGET = (POR_CYCLES < 1) ? 1 : POR_CYCLES;

    // Kintex-7 configuration initializes these registers.  The short local
    // POR lets the free-running board oscillator settle before any SPI work.
    reg [31:0] por_count = 32'd0;
    reg        por_reset = 1'b1;
    reg        start_pulse = 1'b0;
    reg        start_sent = 1'b0;

    always @(posedge sys_clk_i) begin
        start_pulse <= 1'b0;
        if (por_reset) begin
            if (por_count >= (POR_TARGET - 1)) begin
                por_reset <= 1'b0;
                por_count <= por_count;
            end else begin
                por_count <= por_count + 1'b1;
            end
        end else if (!start_sent) begin
            start_pulse <= 1'b1;
            start_sent  <= 1'b1;
        end
    end

    wire        spi_start;
    wire        spi_rw;
    wire [12:0] spi_addr;
    wire [7:0]  spi_write_data;
    wire        spi_busy;
    wire        spi_done;
    wire [7:0]  spi_read_data;
    wire        spi_error;

    wire [5:0]  profile_index;
    wire [12:0] profile_addr;
    wire [7:0]  profile_data;
    wire [7:0]  profile_verify_mask;
    wire        profile_valid;
    wire        profile_last;

    wire        ld_filter_enable;
    wire        pll_ld_sync;
    wire        pll_locked;
    wire        lock_acquired;
    wire        lock_lost;

    wire        busy;
    wire        clock_ready;
    wire        init_error;
    wire [3:0]  error_code;
    wire [7:0]  last_read;
    wire [12:0] last_addr;
    wire [4:0]  init_state;

    // REF_SEL is ignored by the programmed 0x01C setting; driving it low is
    // nevertheless deterministic and matches the selected REF2 profile.
    assign pll_ref_sel_o = 1'b0;

    ad9517_profile_rom u_profile_rom (
        .index_i        (profile_index),
        .addr_o         (profile_addr),
        .data_o         (profile_data),
        .verify_mask_o  (profile_verify_mask),
        .entry_valid_o  (profile_valid),
        .last_o         (profile_last)
    );

    ad9517_spi_master #(
        .CLK_FREQ_HZ  (SYS_CLK_FREQ_HZ),
        .SCLK_FREQ_HZ (SPI_SCLK_FREQ_HZ)
    ) u_spi_master (
        .clk_i             (sys_clk_i),
        .rst_i             (por_reset),
        .start_i           (spi_start),
        .rw_i              (spi_rw),
        .addr_i            (spi_addr),
        .write_data_i      (spi_write_data),
        .busy_o            (spi_busy),
        .done_o            (spi_done),
        .read_data_o       (spi_read_data),
        .error_o           (spi_error),
        .pll_cs_n_o        (pll_cs_n_o),
        .pll_sclk_o        (pll_sclk_o),
        .pll_sdio_o        (pll_sdio_o),
        .pll_sdo_i         (pll_sdo_i)
    );

    // Hold the qualifier in reset until OUT0 has been enabled.  This makes
    // the 1 ms high window explicitly post-enable rather than reusing a DLD
    // high interval observed during calibration.
    pll_ld_sync_and_filter #(
        .CLK_FREQ_HZ        (SYS_CLK_FREQ_HZ),
        .LOCK_STABLE_CYCLES (LOCK_STABLE_CYCLES),
        .LOSS_FILTER_CYCLES (LOSS_FILTER_CYCLES)
    ) u_ld_filter (
        .clk_i             (sys_clk_i),
        .rst_i             (por_reset || !ld_filter_enable),
        .pll_ld_async_i    (pll_ld_i),
        .pll_ld_sync_o     (pll_ld_sync),
        .pll_locked_o      (pll_locked),
        .lock_acquired_o   (lock_acquired),
        .lock_lost_o       (lock_lost)
    );

    ad9517_init_ctrl #(
        .RESET_ASSERT_CYCLES  (RESET_ASSERT_CYCLES),
        .RESET_RELEASE_CYCLES (RESET_RELEASE_CYCLES),
        .SPI_TIMEOUT_CYCLES   (SPI_TIMEOUT_CYCLES),
        .CAL_TIMEOUT_CYCLES   (CAL_TIMEOUT_CYCLES),
        .LOCK_TIMEOUT_CYCLES  (LOCK_TIMEOUT_CYCLES)
    ) u_init_ctrl (
        .clk_i                  (sys_clk_i),
        .rst_i                  (por_reset),
        .start_i                (start_pulse),
        .restart_i              (1'b0),
        .spi_start_o            (spi_start),
        .spi_rw_o               (spi_rw),
        .spi_addr_o             (spi_addr),
        .spi_write_data_o       (spi_write_data),
        .spi_busy_i             (spi_busy),
        .spi_done_i             (spi_done),
        .spi_error_i            (spi_error),
        .spi_read_data_i        (spi_read_data),
        .profile_index_o        (profile_index),
        .profile_addr_i         (profile_addr),
        .profile_data_i         (profile_data),
        .profile_verify_mask_i  (profile_verify_mask),
        .profile_entry_valid_i  (profile_valid),
        .profile_last_i         (profile_last),
        .pll_locked_i           (pll_locked),
        .lock_lost_i            (lock_lost),
        .ld_filter_enable_o     (ld_filter_enable),
        .busy_o                 (busy),
        .clock_ready_o          (clock_ready),
        .error_o                (init_error),
        .error_code_o           (error_code),
        .last_read_o            (last_read),
        .last_addr_o            (last_addr),
        .state_o                (init_state),
        .pll_reset_n_o          (pll_reset_n_o)
    );

    // LED1: solid means the complete digital-side sequence passed.  Before
    // that, slow blink means busy and faster blink means a latched error.
    reg [25:0] blink_count = 26'd0;
    always @(posedge sys_clk_i) begin
        if (por_reset)
            blink_count <= 26'd0;
        else
            blink_count <= blink_count + 1'b1;
    end
    assign led1 = clock_ready ? 1'b1 :
                  init_error  ? blink_count[22] :
                  busy        ? blink_count[25] : 1'b0;

    // A single 64-bit probe keeps the board test observable without exposing
    // debug-only pins.  The testbench overrides ENABLE_ILA=0; the hardware top
    // uses the default and registers ila_ad9517.xci before synthesis.
    wire [63:0] debug_bus;
    assign debug_bus = {
        8'hA5,
        init_state,
        profile_index,
        error_code,
        last_addr,
        last_read,
        busy,
        clock_ready,
        pll_locked,
        init_error,
        spi_busy,
        spi_done,
        spi_error,
        pll_ld_sync,
        pll_ld_i,
        pll_cs_n_o,
        pll_sclk_o,
        pll_sdio_o,
        pll_sdo_i,
        pll_reset_n_o,
        6'b000000
    };

    generate
        if (ENABLE_ILA != 0) begin : g_ila
            ila_ad9517 u_ila_ad9517 (
                .clk    (sys_clk_i),
                .probe0 (debug_bus)
            );
        end
    endgenerate

    wire _unused_lock_acquired = lock_acquired;

endmodule
