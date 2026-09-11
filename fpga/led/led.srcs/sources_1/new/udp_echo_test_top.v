`timescale 1ns / 1ps

// Board-level UDP echo image used only for Ethernet bring-up.
// The external ports intentionally match udp_top.xdc; all logical message and
// debug signals are consumed inside this wrapper.
module udp_echo_test_top (
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
    wire        link_ready;
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
        .clock_200m_locked_o    (),
        .ad9517_clock_ready_o   (),
        .ad9517_pll_locked_o    (),
        .ad9517_error_o         (),
        .ad9517_error_code_o    (),
        .link_ready_o           (link_ready),
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
        .tx_msg_error_o         (),
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

    udp_payload_echo echo_i (
        .clk_i               (link_clock_125m),
        .resetn_i            (link_ready),
        .rx_msg_valid_i      (rx_msg_valid),
        .rx_msg_ready_o      (rx_msg_ready),
        .rx_msg_data_i       (rx_msg_data),
        .rx_msg_last_i       (rx_msg_last),
        .rx_msg_len_i        (rx_msg_len),
        .tx_msg_valid_o      (tx_msg_valid),
        .tx_msg_ready_i      (tx_msg_ready),
        .tx_msg_len_o        (tx_msg_len),
        .tx_msg_data_valid_o (tx_msg_data_valid),
        .tx_msg_data_ready_i (tx_msg_data_ready),
        .tx_msg_data_o       (tx_msg_data),
        .tx_msg_data_last_o  (tx_msg_data_last)
    );

endmodule
