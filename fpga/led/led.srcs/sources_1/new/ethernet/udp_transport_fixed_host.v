`timescale 1ns / 1ps

// Stable wrapper for the fixed-host Ethernet II / ARP / IPv4 / UDP transport.
// All submodules share clk_i; this hierarchy introduces no clock-domain
// crossing and preserves the original external interface.
module udp_transport_fixed_host #(
    parameter [47:0] LOCAL_MAC        = 48'h02_DB_50_00_00_01,
    parameter [31:0] LOCAL_IPV4       = 32'hC0A8_0114,
    parameter [47:0] HOST_MAC         = 48'h9C69_D31A_4C6D,
    parameter [31:0] HOST_IPV4        = 32'hC0A8_010A,
    parameter [15:0] LOCAL_UDP_PORT   = 16'd32000,
    parameter [15:0] HOST_UDP_PORT    = 16'd32000,
    parameter integer MAX_UDP_PAYLOAD = 1472
) (
    input  wire        clk_i,
    input  wire        resetn_i,
    input  wire        link_ready_i,

    input  wire [7:0]  rx_axis_tdata_i,
    input  wire        rx_axis_tvalid_i,
    output wire        rx_axis_tready_o,
    input  wire        rx_axis_tlast_i,

    output wire [7:0]  tx_axis_tdata_o,
    output wire        tx_axis_tvalid_o,
    input  wire        tx_axis_tready_i,
    output wire        tx_axis_tlast_o,

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

    wire        rx_slot_available;
    wire        rx_payload_write_valid;
    wire [10:0] rx_payload_write_offset;
    wire [7:0]  rx_payload_write_data;
    wire        rx_commit_udp;
    wire [10:0] rx_commit_length;
    wire        arp_reply_request;
    wire        rx_frame_event;
    wire        rx_accept_event;
    wire        rx_drop_event;
    wire [3:0]  rx_drop_reason;

    wire        tx_packet_valid;
    wire [10:0] tx_packet_length;
    wire [31:0] tx_packet_payload_sum;
    wire        tx_packet_release;
    wire [10:0] tx_payload_read_addr;
    wire [7:0]  tx_payload_read_data;
    wire        tx_buffer_busy;
    wire        tx_engine_busy;
    wire        tx_accept_event;
    wire        tx_error_event;
    wire        tx_sent_event;

    fixed_host_rx_parser #(
        .LOCAL_MAC          (LOCAL_MAC),
        .LOCAL_IPV4         (LOCAL_IPV4),
        .HOST_MAC           (HOST_MAC),
        .HOST_IPV4          (HOST_IPV4),
        .LOCAL_UDP_PORT     (LOCAL_UDP_PORT),
        .HOST_UDP_PORT      (HOST_UDP_PORT),
        .MAX_UDP_PAYLOAD    (MAX_UDP_PAYLOAD)
    ) rx_parser_i (
        .clk_i                  (clk_i),
        .resetn_i               (resetn_i),
        .link_ready_i           (link_ready_i),
        .rx_axis_tdata_i        (rx_axis_tdata_i),
        .rx_axis_tvalid_i       (rx_axis_tvalid_i),
        .rx_axis_tready_o       (rx_axis_tready_o),
        .rx_axis_tlast_i        (rx_axis_tlast_i),
        .slot_available_i       (rx_slot_available),
        .payload_write_valid_o  (rx_payload_write_valid),
        .payload_write_offset_o (rx_payload_write_offset),
        .payload_write_data_o   (rx_payload_write_data),
        .commit_o               (rx_commit_udp),
        .commit_length_o        (rx_commit_length),
        .arp_reply_request_o    (arp_reply_request),
        .frame_event_o          (rx_frame_event),
        .accept_event_o         (rx_accept_event),
        .drop_event_o           (rx_drop_event),
        .drop_reason_o          (rx_drop_reason)
    );

    udp_rx_message_fifo #(
        .MAX_UDP_PAYLOAD (MAX_UDP_PAYLOAD)
    ) rx_message_fifo_i (
        .clk_i                  (clk_i),
        .resetn_i               (resetn_i),
        .slot_available_o       (rx_slot_available),
        .payload_write_valid_i  (rx_payload_write_valid),
        .payload_write_offset_i (rx_payload_write_offset),
        .payload_write_data_i   (rx_payload_write_data),
        .commit_i               (rx_commit_udp),
        .commit_length_i        (rx_commit_length),
        .msg_valid_o            (rx_msg_valid_o),
        .msg_ready_i            (rx_msg_ready_i),
        .msg_data_o             (rx_msg_data_o),
        .msg_last_o             (rx_msg_last_o),
        .msg_len_o              (rx_msg_len_o),
        .level_o                (rx_fifo_level_o)
    );

    udp_tx_message_buffer #(
        .MAX_UDP_PAYLOAD (MAX_UDP_PAYLOAD)
    ) tx_message_buffer_i (
        .clk_i                (clk_i),
        .resetn_i             (resetn_i),
        .link_ready_i         (link_ready_i),
        .msg_valid_i          (tx_msg_valid_i),
        .msg_ready_o          (tx_msg_ready_o),
        .msg_len_i            (tx_msg_len_i),
        .msg_data_valid_i     (tx_msg_data_valid_i),
        .msg_data_ready_o     (tx_msg_data_ready_o),
        .msg_data_i           (tx_msg_data_i),
        .msg_data_last_i      (tx_msg_data_last_i),
        .msg_error_o          (tx_msg_error_o),
        .packet_valid_o       (tx_packet_valid),
        .packet_len_o         (tx_packet_length),
        .packet_payload_sum_o (tx_packet_payload_sum),
        .packet_release_i     (tx_packet_release),
        .payload_read_addr_i  (tx_payload_read_addr),
        .payload_read_data_o  (tx_payload_read_data),
        .busy_o               (tx_buffer_busy),
        .accept_event_o       (tx_accept_event),
        .error_event_o        (tx_error_event)
    );

    fixed_host_tx_engine #(
        .LOCAL_MAC      (LOCAL_MAC),
        .LOCAL_IPV4     (LOCAL_IPV4),
        .HOST_MAC       (HOST_MAC),
        .HOST_IPV4      (HOST_IPV4),
        .LOCAL_UDP_PORT (LOCAL_UDP_PORT),
        .HOST_UDP_PORT  (HOST_UDP_PORT)
    ) tx_engine_i (
        .clk_i                  (clk_i),
        .resetn_i               (resetn_i),
        .link_ready_i           (link_ready_i),
        .arp_reply_request_i    (arp_reply_request),
        .packet_valid_i         (tx_packet_valid),
        .packet_len_i           (tx_packet_length),
        .packet_payload_sum_i   (tx_packet_payload_sum),
        .packet_release_o       (tx_packet_release),
        .payload_read_addr_o    (tx_payload_read_addr),
        .payload_read_data_i    (tx_payload_read_data),
        .tx_axis_tdata_o        (tx_axis_tdata_o),
        .tx_axis_tvalid_o       (tx_axis_tvalid_o),
        .tx_axis_tready_i       (tx_axis_tready_i),
        .tx_axis_tlast_o        (tx_axis_tlast_o),
        .busy_o                 (tx_engine_busy),
        .sent_event_o           (tx_sent_event)
    );

    udp_transport_stats stats_i (
        .clk_i                    (clk_i),
        .resetn_i                 (resetn_i),
        .rx_frame_event_i         (rx_frame_event),
        .rx_accept_event_i        (rx_accept_event),
        .rx_drop_event_i          (rx_drop_event),
        .rx_drop_reason_i         (rx_drop_reason),
        .tx_accept_event_i        (tx_accept_event),
        .tx_sent_event_i          (tx_sent_event),
        .tx_error_event_i         (tx_error_event),
        .last_drop_reason_o       (last_drop_reason_o),
        .rx_frames_seen_o         (rx_frames_seen_o),
        .rx_udp_accepted_o        (rx_udp_accepted_o),
        .rx_drop_endpoint_o       (rx_drop_endpoint_o),
        .rx_drop_ipv4_o           (rx_drop_ipv4_o),
        .rx_drop_udp_o            (rx_drop_udp_o),
        .rx_drop_checksum_o       (rx_drop_checksum_o),
        .rx_drop_oversize_o       (rx_drop_oversize_o),
        .rx_drop_fifo_full_o      (rx_drop_fifo_full_o),
        .tx_accepted_o            (tx_accepted_o),
        .tx_sent_o                (tx_sent_o),
        .tx_input_error_o         (tx_input_error_o)
    );

    assign tx_busy_o = tx_buffer_busy || tx_engine_busy;

endmodule
