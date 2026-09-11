`timescale 1ns / 1ps

// First board-level composition boundary for the UDP link.
//
// AD9517 remains the single owner of the U65 configuration pins and its
// qualified clock_ready signal gates the Ethernet link.  The 125 MHz OUT0
// signal enters the dedicated MGTREFCLK pins; it is not routed through fabric
// logic.  ethernet_link_top generates its own 200 MHz independent reset clock
// from the 100 MHz system clock.
module udp_top #(
    parameter integer ENABLE_AD_ILA = 0,
    parameter [47:0] LOCAL_MAC      = 48'h02_DB_50_00_00_01,
    parameter [31:0] LOCAL_IPV4     = 32'hC0A8_0114,
    parameter [47:0] HOST_MAC       = 48'h9C69_D31A_4C6D,
    parameter [31:0] HOST_IPV4      = 32'hC0A8_010A,
    parameter [15:0] LOCAL_UDP_PORT = 16'd32000,
    parameter [15:0] HOST_UDP_PORT  = 16'd32000
) (
    input  wire        sys_clk_i,

    output wire        led1,
    output wire        pll_cs_n_o,
    output wire        pll_sclk_o,
    output wire        pll_sdio_o,
    input  wire        pll_sdo_i,
    output wire        pll_ref_sel_o,
    input  wire        pll_ld_i,
    output wire        pll_reset_n_o,

    input  wire        gtrefclk_p_i,
    input  wire        gtrefclk_n_i,
    output wire        sgmii_txp_o,
    output wire        sgmii_txn_o,
    input  wire        sgmii_rxp_i,
    input  wire        sgmii_rxn_i,

    output wire        link_clock_125m_o,
    output wire        clock_200m_locked_o,
    output wire        ad9517_clock_ready_o,
    output wire        ad9517_pll_locked_o,
    output wire        ad9517_error_o,
    output wire [3:0]  ad9517_error_code_o,
    output wire        link_ready_o,
    output wire [1:0]  link_speed_o,
    output wire [15:0] pcs_status_o,

    output wire        rx_msg_valid_o,
    input  wire        rx_msg_ready_i,
    output wire [7:0]  rx_msg_data_o,
    output wire        rx_msg_last_o,
    output wire [10:0] rx_msg_len_o,

    input  wire        tx_msg_valid_i,
    output wire        tx_msg_ready_o,
    input  wire [10:0] tx_msg_len_i,
    input  wire        tx_msg_data_valid_i,
    output wire        tx_msg_data_ready_o,
    input  wire [7:0]  tx_msg_data_i,
    input  wire        tx_msg_data_last_i,
    output wire        tx_msg_error_o,

    output wire [2:0]  rx_fifo_level_o,
    output wire        tx_busy_o,
    output wire [3:0]  last_drop_reason_o,
    output wire [31:0] rx_frames_seen_o,
    output wire [31:0] rx_udp_accepted_o,
    output wire [31:0] rx_drop_endpoint_o,
    output wire [31:0] rx_drop_ipv4_o,
    output wire [31:0] rx_drop_udp_o,
    output wire [31:0] rx_drop_checksum_o,
    output wire [31:0] rx_drop_oversize_o,
    output wire [31:0] rx_drop_fifo_full_o,
    output wire [31:0] tx_accepted_o,
    output wire [31:0] tx_sent_o,
    output wire [31:0] tx_input_error_o
);

    // AA3 is shared by the AD9517 controller and the Ethernet independent-
    // clock MMCM.  Buffer it once at the board boundary; the Clocking Wizard
    // is configured for a no-buffer input so it does not instantiate a
    // second IBUF on the same package pin.
    wire system_clock_100m_ibuf;
    wire system_clock_100m_bufg;

    IBUF system_clock_ibuf_i (
        .I (sys_clk_i),
        .O (system_clock_100m_ibuf)
    );

    BUFG system_clock_bufg_i (
        .I (system_clock_100m_ibuf),
        .O (system_clock_100m_bufg)
    );

    ad9517_clock_manager #(
        .ENABLE_ILA (ENABLE_AD_ILA)
    ) ad9517_i (
        .sys_clk_i       (system_clock_100m_bufg),
        .led1            (led1),
        .pll_cs_n_o      (pll_cs_n_o),
        .pll_sclk_o      (pll_sclk_o),
        .pll_sdio_o      (pll_sdio_o),
        .pll_sdo_i       (pll_sdo_i),
        .pll_ref_sel_o   (pll_ref_sel_o),
        .pll_ld_i        (pll_ld_i),
        .pll_reset_n_o   (pll_reset_n_o),
        .clock_ready_o   (ad9517_clock_ready_o),
        .pll_locked_o    (ad9517_pll_locked_o),
        .init_error_o    (ad9517_error_o),
        .error_code_o    (ad9517_error_code_o)
    );

    wire        link_user_resetn;
    wire [7:0]  ethernet_rx_tdata;
    wire        ethernet_rx_tvalid;
    wire        ethernet_rx_tready;
    wire        ethernet_rx_tlast;
    wire [7:0]  ethernet_tx_tdata;
    wire        ethernet_tx_tvalid;
    wire        ethernet_tx_tready;
    wire        ethernet_tx_tlast;

    ethernet_link_top ethernet_link_i (
        .reset_i             (1'b0),
        .clock_ready_i       (ad9517_clock_ready_o),
        .system_clock_100m_i (system_clock_100m_bufg),
        .gtrefclk_p_i       (gtrefclk_p_i),
        .gtrefclk_n_i       (gtrefclk_n_i),
        .sgmii_txp_o        (sgmii_txp_o),
        .sgmii_txn_o        (sgmii_txn_o),
        .sgmii_rxp_i        (sgmii_rxp_i),
        .sgmii_rxn_i        (sgmii_rxn_i),
        .user_clk_o         (link_clock_125m_o),
        .user_resetn_o      (link_user_resetn),
        .clock_200m_locked_o(clock_200m_locked_o),
        .link_ready_o       (link_ready_o),
        .link_speed_o       (link_speed_o),
        .pcs_status_o       (pcs_status_o),
        .rx_axis_tdata_o   (ethernet_rx_tdata),
        .rx_axis_tvalid_o  (ethernet_rx_tvalid),
        .rx_axis_tready_i  (ethernet_rx_tready),
        .rx_axis_tlast_o   (ethernet_rx_tlast),
        .tx_axis_tdata_i   (ethernet_tx_tdata),
        .tx_axis_tvalid_i  (ethernet_tx_tvalid),
        .tx_axis_tready_o  (ethernet_tx_tready),
        .tx_axis_tlast_i   (ethernet_tx_tlast)
    );

    udp_transport_fixed_host #(
        .LOCAL_MAC       (LOCAL_MAC),
        .LOCAL_IPV4      (LOCAL_IPV4),
        .HOST_MAC        (HOST_MAC),
        .HOST_IPV4       (HOST_IPV4),
        .LOCAL_UDP_PORT  (LOCAL_UDP_PORT),
        .HOST_UDP_PORT   (HOST_UDP_PORT),
        .MAX_UDP_PAYLOAD (1472)
    ) udp_transport_i (
        .clk_i                   (link_clock_125m_o),
        .resetn_i                (link_user_resetn),
        .link_ready_i            (link_ready_o),
        .rx_axis_tdata_i         (ethernet_rx_tdata),
        .rx_axis_tvalid_i        (ethernet_rx_tvalid),
        .rx_axis_tready_o        (ethernet_rx_tready),
        .rx_axis_tlast_i         (ethernet_rx_tlast),
        .tx_axis_tdata_o         (ethernet_tx_tdata),
        .tx_axis_tvalid_o        (ethernet_tx_tvalid),
        .tx_axis_tready_i        (ethernet_tx_tready),
        .tx_axis_tlast_o         (ethernet_tx_tlast),
        .rx_msg_valid_o          (rx_msg_valid_o),
        .rx_msg_ready_i          (rx_msg_ready_i),
        .rx_msg_data_o           (rx_msg_data_o),
        .rx_msg_last_o           (rx_msg_last_o),
        .rx_msg_len_o            (rx_msg_len_o),
        .tx_msg_valid_i          (tx_msg_valid_i),
        .tx_msg_ready_o          (tx_msg_ready_o),
        .tx_msg_len_i            (tx_msg_len_i),
        .tx_msg_data_valid_i     (tx_msg_data_valid_i),
        .tx_msg_data_ready_o     (tx_msg_data_ready_o),
        .tx_msg_data_i           (tx_msg_data_i),
        .tx_msg_data_last_i      (tx_msg_data_last_i),
        .tx_msg_error_o          (tx_msg_error_o),
        .rx_fifo_level_o         (rx_fifo_level_o),
        .tx_busy_o               (tx_busy_o),
        .last_drop_reason_o      (last_drop_reason_o),
        .rx_frames_seen_o        (rx_frames_seen_o),
        .rx_udp_accepted_o       (rx_udp_accepted_o),
        .rx_drop_endpoint_o      (rx_drop_endpoint_o),
        .rx_drop_ipv4_o          (rx_drop_ipv4_o),
        .rx_drop_udp_o           (rx_drop_udp_o),
        .rx_drop_checksum_o      (rx_drop_checksum_o),
        .rx_drop_oversize_o      (rx_drop_oversize_o),
        .rx_drop_fifo_full_o     (rx_drop_fifo_full_o),
        .tx_accepted_o           (tx_accepted_o),
        .tx_sent_o               (tx_sent_o),
        .tx_input_error_o        (tx_input_error_o)
    );

endmodule
