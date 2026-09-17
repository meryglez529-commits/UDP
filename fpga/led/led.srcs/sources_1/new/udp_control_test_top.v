`timescale 1ns / 1ps

// Board-level CONTROL-only verification image.  External ports match the
// proven UDP board constraints; all CONTROL diagnostics remain internal.
module udp_control_test_top #(
    parameter integer WATCHDOG_TIMEOUT_CYCLES = 62500000,
    parameter integer WATCHDOG_RESET_CYCLES   = 32
) (
    input  wire sys_clk_i,

    output wire led1,
    output wire pll_cs_n_o,
    output wire pll_sclk_o,
    output wire pll_sdio_o,
    input  wire pll_sdo_i,
    output wire pll_ref_sel_o,
    input  wire pll_ld_i,
    output wire pll_reset_n_o,

    input  wire gtrefclk_p_i,
    input  wire gtrefclk_n_i,
    output wire sgmii_txp_o,
    output wire sgmii_txn_o,
    input  wire sgmii_rxp_i,
    input  wire sgmii_rxn_i
);

    wire        link_clock_125m;
    wire        comm_base_resetn;
    wire        comm_soft_resetn;
    wire        comm_resetn;
    wire        watchdog_activity;
    wire [31:0] watchdog_reset_count;
    wire [1:0]  watchdog_last_reason;
    wire        rx_msg_valid;
    wire        rx_msg_ready;
    wire [7:0]  rx_msg_data;
    wire        rx_msg_last;
    wire [10:0] rx_msg_len;
    wire        tx_msg_valid;
    wire        tx_msg_ready;
    wire [10:0] tx_msg_len;
    wire        tx_msg_data_valid;
    wire        tx_msg_data_ready;
    wire [7:0]  tx_msg_data;
    wire        tx_msg_data_last;
    wire        tx_msg_error;

    wire        reg_req_valid;
    wire        reg_req_ready;
    wire        reg_req_write;
    wire [15:0] reg_req_addr;
    wire [31:0] reg_req_wdata;
    wire        reg_rsp_valid;
    wire        reg_rsp_ready;
    wire        reg_rsp_error;
    wire [31:0] reg_rsp_rdata;

    udp_top #(
        .ENABLE_AD_ILA (0),
        .LOCAL_MAC      (48'h02_DB_50_00_00_01),
        .LOCAL_IPV4     (32'hC0A8_0114),
        .HOST_MAC       (48'h9C69_D31A_4C6D),
        .HOST_IPV4      (32'hC0A8_010A),
        .LOCAL_UDP_PORT (16'd32000),
        .HOST_UDP_PORT  (16'd32000)
    ) udp_system_i (
        .sys_clk_i              (sys_clk_i),
        .comm_soft_resetn_i     (comm_soft_resetn),
        .led1                   (led1),
        .pll_cs_n_o             (pll_cs_n_o),
        .pll_sclk_o             (pll_sclk_o),
        .pll_sdio_o             (pll_sdio_o),
        .pll_sdo_i              (pll_sdo_i),
        .pll_ref_sel_o          (pll_ref_sel_o),
        .pll_ld_i               (pll_ld_i),
        .pll_reset_n_o          (pll_reset_n_o),
        .gtrefclk_p_i           (gtrefclk_p_i),
        .gtrefclk_n_i           (gtrefclk_n_i),
        .sgmii_txp_o            (sgmii_txp_o),
        .sgmii_txn_o            (sgmii_txn_o),
        .sgmii_rxp_i            (sgmii_rxp_i),
        .sgmii_rxn_i            (sgmii_rxn_i),
        .link_clock_125m_o      (link_clock_125m),
        .comm_base_resetn_o     (comm_base_resetn),
        .comm_resetn_o          (comm_resetn),
        .clock_200m_locked_o    (),
        .ad9517_clock_ready_o   (),
        .ad9517_pll_locked_o    (),
        .ad9517_error_o         (),
        .ad9517_error_code_o    (),
        .link_ready_o           (),
        .link_speed_o           (),
        .pcs_status_o           (),
        .rx_msg_valid_o         (rx_msg_valid),
        .rx_msg_ready_i         (rx_msg_ready),
        .rx_msg_data_o          (rx_msg_data),
        .rx_msg_last_o          (rx_msg_last),
        .rx_msg_len_o           (rx_msg_len),
        .tx_msg_valid_i         (tx_msg_valid),
        .tx_msg_ready_o         (tx_msg_ready),
        .tx_msg_len_i           (tx_msg_len),
        .tx_msg_data_valid_i    (tx_msg_data_valid),
        .tx_msg_data_ready_o    (tx_msg_data_ready),
        .tx_msg_data_i          (tx_msg_data),
        .tx_msg_data_last_i     (tx_msg_data_last),
        .tx_msg_error_o         (tx_msg_error),
        .rx_fifo_level_o        (),
        .tx_busy_o              (),
        .last_drop_reason_o     (),
        .rx_frames_seen_o       (),
        .rx_udp_accepted_o      (),
        .rx_drop_endpoint_o     (),
        .rx_drop_ipv4_o         (),
        .rx_drop_udp_o          (),
        .rx_drop_checksum_o     (),
        .rx_drop_oversize_o     (),
        .rx_drop_fifo_full_o    (),
        .tx_accepted_o          (),
        .tx_sent_o              (),
        .tx_input_error_o       ()
    );

    db500_udp_control control_i (
        .clk_i                (link_clock_125m),
        .resetn_i             (comm_resetn),
        .rx_msg_valid_i       (rx_msg_valid),
        .rx_msg_ready_o       (rx_msg_ready),
        .rx_msg_data_i        (rx_msg_data),
        .rx_msg_last_i        (rx_msg_last),
        .rx_msg_len_i         (rx_msg_len),
        .tx_msg_valid_o       (tx_msg_valid),
        .tx_msg_ready_i       (tx_msg_ready),
        .tx_msg_len_o         (tx_msg_len),
        .tx_msg_data_valid_o  (tx_msg_data_valid),
        .tx_msg_data_ready_i  (tx_msg_data_ready),
        .tx_msg_data_o        (tx_msg_data),
        .tx_msg_data_last_o   (tx_msg_data_last),
        .tx_msg_error_i       (tx_msg_error),
        .reg_req_valid_o      (reg_req_valid),
        .reg_req_ready_i      (reg_req_ready),
        .reg_req_write_o      (reg_req_write),
        .reg_req_addr_o       (reg_req_addr),
        .reg_req_wdata_o      (reg_req_wdata),
        .reg_rsp_valid_i      (reg_rsp_valid),
        .reg_rsp_ready_o      (reg_rsp_ready),
        .reg_rsp_error_i      (reg_rsp_error),
        .reg_rsp_rdata_i      (reg_rsp_rdata),
        .watchdog_activity_o  (watchdog_activity),
        .fault_hold_o         (),
        .oldest_id_o          (),
        .execute_id_o         (),
        .rx_seen_o            (),
        .rx_format_drop_o     (),
        .rx_window_drop_o     (),
        .rx_duplicate_o       (),
        .rx_id_conflict_o     (),
        .query_executed_o     (),
        .set_executed_o       (),
        .reg_error_o          (),
        .rsp_loaded_o         (),
        .tx_input_error_o     (),
        .last_fault_kind_o    ()
    );

    db500_ctrl_test_reg_bank test_bank_i (
        .clk_i            (link_clock_125m),
        .resetn_i         (comm_base_resetn),
        .txn_resetn_i     (comm_resetn),
        .watchdog_reset_count_i (watchdog_reset_count),
        .watchdog_last_reason_i (watchdog_last_reason),
        .reg_req_valid_i  (reg_req_valid),
        .reg_req_ready_o  (reg_req_ready),
        .reg_req_write_i  (reg_req_write),
        .reg_req_addr_i   (reg_req_addr),
        .reg_req_wdata_i  (reg_req_wdata),
        .reg_rsp_valid_o  (reg_rsp_valid),
        .reg_rsp_ready_i  (reg_rsp_ready),
        .reg_rsp_error_o  (reg_rsp_error),
        .reg_rsp_rdata_o  (reg_rsp_rdata),
        .scratch0_o       (),
        .scratch1_o       (),
        .write_count_o    ()
    );

    db500_ctrl_watchdog #(
        .WATCHDOG_TIMEOUT_CYCLES (WATCHDOG_TIMEOUT_CYCLES),
        .RESET_HOLD_CYCLES       (WATCHDOG_RESET_CYCLES)
    ) watchdog_i (
        .clk_i               (link_clock_125m),
        .base_resetn_i       (comm_base_resetn),
        .activity_event_i    (watchdog_activity),
        .soft_resetn_o       (comm_soft_resetn),
        .reset_event_o       (),
        .reset_count_o       (watchdog_reset_count),
        .last_reset_reason_o (watchdog_last_reason),
        .state_o             ()
    );

endmodule
