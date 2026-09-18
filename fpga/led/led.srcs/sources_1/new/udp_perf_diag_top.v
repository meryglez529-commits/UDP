`timescale 1ns / 1ps

// Development-only UDP echo diagnostic image.  Three passive monitors observe
// the same UPF1 sequence number at the raw RX frame, accepted UDP payload, and
// final TX frame boundaries.  No monitor drives the packet data path.
module udp_perf_diag_top (
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
    wire [2:0]  rx_fifo_level;
    wire        tx_busy;

    wire [7:0] debug_rx_axis_tdata;
    wire       debug_rx_axis_tvalid;
    wire       debug_rx_axis_tready;
    wire       debug_rx_axis_tlast;
    wire [7:0] debug_tx_axis_tdata;
    wire       debug_tx_axis_tvalid;
    wire       debug_tx_axis_tready;
    wire       debug_tx_axis_tlast;

    wire        raw_reorder_pulse;
    wire [31:0] raw_reorder_count;
    wire [31:0] raw_packet_count;
    wire [31:0] raw_current_sequence;
    wire [31:0] raw_previous_highest;
    wire [31:0] raw_current_run_id;
    wire        msg_reorder_pulse;
    wire [31:0] msg_reorder_count;
    wire [31:0] msg_packet_count;
    wire [31:0] msg_current_sequence;
    wire [31:0] msg_previous_highest;
    wire [31:0] msg_current_run_id;
    wire        tx_reorder_pulse;
    wire [31:0] tx_reorder_count;
    wire [31:0] tx_packet_count;
    wire [31:0] tx_current_sequence;
    wire [31:0] tx_previous_highest;
    wire [31:0] tx_current_run_id;
    wire        any_reorder_pulse;

    assign any_reorder_pulse = raw_reorder_pulse |
                               msg_reorder_pulse |
                               tx_reorder_pulse;

    udp_top #(
        .ENABLE_AD_ILA (0),
        .LOCAL_MAC      (48'h02_DB_50_00_00_01),
        .LOCAL_IPV4     (32'hC0A8_0114),
        .HOST_MAC       (48'h9C69_D31A_4C6D),
        .HOST_IPV4      (32'hC0A8_010A),
        .LOCAL_UDP_PORT (16'd32000),
        .HOST_UDP_PORT  (16'd32000)
    ) udp_system_i (
        .sys_clk_i                   (sys_clk_i),
        .comm_soft_resetn_i          (1'b1),
        .led1                        (led1),
        .pll_cs_n_o                  (pll_cs_n_o),
        .pll_sclk_o                  (pll_sclk_o),
        .pll_sdio_o                  (pll_sdio_o),
        .pll_sdo_i                   (pll_sdo_i),
        .pll_ref_sel_o               (pll_ref_sel_o),
        .pll_ld_i                    (pll_ld_i),
        .pll_reset_n_o               (pll_reset_n_o),
        .gtrefclk_p_i                (gtrefclk_p_i),
        .gtrefclk_n_i                (gtrefclk_n_i),
        .sgmii_txp_o                 (sgmii_txp_o),
        .sgmii_txn_o                 (sgmii_txn_o),
        .sgmii_rxp_i                 (sgmii_rxp_i),
        .sgmii_rxn_i                 (sgmii_rxn_i),
        .link_clock_125m_o           (link_clock_125m),
        .comm_base_resetn_o          (),
        .clock_200m_locked_o         (),
        .ad9517_clock_ready_o        (),
        .ad9517_pll_locked_o         (),
        .ad9517_error_o              (),
        .ad9517_error_code_o         (),
        .link_ready_o                (link_ready),
        .link_speed_o                (),
        .pcs_status_o                (),
        .rx_msg_valid_o              (rx_msg_valid),
        .rx_msg_ready_i              (rx_msg_ready),
        .rx_msg_data_o               (rx_msg_data),
        .rx_msg_last_o               (rx_msg_last),
        .rx_msg_len_o                (rx_msg_len),
        .tx_msg_valid_i              (tx_msg_valid),
        .tx_msg_ready_o              (tx_msg_ready),
        .tx_msg_len_i                (tx_msg_len),
        .tx_msg_data_valid_i         (tx_msg_data_valid),
        .tx_msg_data_ready_o         (tx_msg_data_ready),
        .tx_msg_data_i               (tx_msg_data),
        .tx_msg_data_last_i          (tx_msg_data_last),
        .tx_msg_error_o              (),
        .data_rx_valid_o             (),
        .data_rx_ready_i             (1'b1),
        .data_rx_data_o              (),
        .data_rx_last_o              (),
        .data_rx_len_o               (),
        .data_tx_req_valid_i         (1'b0),
        .data_tx_req_ready_o         (),
        .data_tx_len_i               (14'd0),
        .data_tx_valid_i             (1'b0),
        .data_tx_ready_o             (),
        .data_tx_data_i              (8'd0),
        .data_tx_last_i              (1'b0),
        .data_tx_cancel_valid_i      (1'b0),
        .data_tx_cancel_ready_o      (),
        .data_tx_status_valid_o      (),
        .data_tx_status_ready_i      (1'b1),
        .data_tx_status_o            (),
        .rx_fifo_level_o             (rx_fifo_level),
        .data_rx_fifo_level_o        (),
        .tx_busy_o                   (tx_busy),
        .last_drop_reason_o          (),
        .rx_frames_seen_o            (),
        .rx_udp_accepted_o           (),
        .rx_drop_endpoint_o          (),
        .rx_drop_ipv4_o              (),
        .rx_drop_udp_o               (),
        .rx_drop_checksum_o          (),
        .rx_drop_oversize_o          (),
        .rx_drop_fifo_full_o         (),
        .tx_accepted_o               (),
        .tx_sent_o                   (),
        .tx_input_error_o            (),
        .debug_rx_axis_tdata_o       (debug_rx_axis_tdata),
        .debug_rx_axis_tvalid_o      (debug_rx_axis_tvalid),
        .debug_rx_axis_tready_o      (debug_rx_axis_tready),
        .debug_rx_axis_tlast_o       (debug_rx_axis_tlast),
        .debug_tx_axis_tdata_o       (debug_tx_axis_tdata),
        .debug_tx_axis_tvalid_o      (debug_tx_axis_tvalid),
        .debug_tx_axis_tready_o      (debug_tx_axis_tready),
        .debug_tx_axis_tlast_o       (debug_tx_axis_tlast)
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

    udp_sequence_order_monitor #(.PAYLOAD_BASE(42)) raw_rx_monitor_i (
        .clk_i               (link_clock_125m),
        .resetn_i            (link_ready),
        .stream_data_i       (debug_rx_axis_tdata),
        .stream_valid_i      (debug_rx_axis_tvalid),
        .stream_ready_i      (debug_rx_axis_tready),
        .stream_last_i       (debug_rx_axis_tlast),
        .reorder_pulse_o     (raw_reorder_pulse),
        .reorder_count_o     (raw_reorder_count),
        .packet_count_o      (raw_packet_count),
        .current_sequence_o  (raw_current_sequence),
        .previous_highest_o  (raw_previous_highest),
        .current_run_id_o    (raw_current_run_id)
    );

    udp_sequence_order_monitor #(.PAYLOAD_BASE(0)) rx_msg_monitor_i (
        .clk_i               (link_clock_125m),
        .resetn_i            (link_ready),
        .stream_data_i       (rx_msg_data),
        .stream_valid_i      (rx_msg_valid),
        .stream_ready_i      (rx_msg_ready),
        .stream_last_i       (rx_msg_last),
        .reorder_pulse_o     (msg_reorder_pulse),
        .reorder_count_o     (msg_reorder_count),
        .packet_count_o      (msg_packet_count),
        .current_sequence_o  (msg_current_sequence),
        .previous_highest_o  (msg_previous_highest),
        .current_run_id_o    (msg_current_run_id)
    );

    udp_sequence_order_monitor #(.PAYLOAD_BASE(42)) tx_frame_monitor_i (
        .clk_i               (link_clock_125m),
        .resetn_i            (link_ready),
        .stream_data_i       (debug_tx_axis_tdata),
        .stream_valid_i      (debug_tx_axis_tvalid),
        .stream_ready_i      (debug_tx_axis_tready),
        .stream_last_i       (debug_tx_axis_tlast),
        .reorder_pulse_o     (tx_reorder_pulse),
        .reorder_count_o     (tx_reorder_count),
        .packet_count_o      (tx_packet_count),
        .current_sequence_o  (tx_current_sequence),
        .previous_highest_o  (tx_previous_highest),
        .current_run_id_o    (tx_current_run_id)
    );

    ila_udp_sequence sequence_ila_i (
        .clk     (link_clock_125m),
        .probe0  (any_reorder_pulse),
        .probe1  (raw_reorder_pulse),
        .probe2  (raw_reorder_count),
        .probe3  (raw_current_sequence),
        .probe4  (raw_previous_highest),
        .probe5  (raw_current_run_id),
        .probe6  (raw_packet_count),
        .probe7  (msg_reorder_pulse),
        .probe8  (msg_reorder_count),
        .probe9  (msg_current_sequence),
        .probe10 (msg_previous_highest),
        .probe11 (msg_current_run_id),
        .probe12 (msg_packet_count),
        .probe13 (tx_reorder_pulse),
        .probe14 (tx_reorder_count),
        .probe15 (tx_current_sequence),
        .probe16 (tx_previous_highest),
        .probe17 (tx_current_run_id),
        .probe18 (tx_packet_count),
        .probe19 ({link_ready, tx_busy, rx_fifo_level}),
        .probe20 ({debug_rx_axis_tlast, debug_rx_axis_tready,
                   debug_rx_axis_tvalid, debug_rx_axis_tdata}),
        .probe21 ({rx_msg_last, rx_msg_ready, rx_msg_valid, rx_msg_data}),
        .probe22 ({debug_tx_axis_tlast, debug_tx_axis_tready,
                   debug_tx_axis_tvalid, debug_tx_axis_tdata})
    );

endmodule
