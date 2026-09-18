`timescale 1ns / 1ps

// Fixed-host UDP transport with independent CONTROL and DATA payload queues.
// Ethernet/IPv4 parsing and frame serialization are shared; payload ownership
// and reset policy remain per channel.
module udp_transport_dual_host #(
    parameter [47:0] LOCAL_MAC = 48'h02_DB_50_00_00_01,
    parameter [31:0] LOCAL_IPV4 = 32'hC0A8_0114,
    parameter [47:0] HOST_MAC = 48'h9C69_D31A_4C6D,
    parameter [31:0] HOST_IPV4 = 32'hC0A8_010A,
    parameter [15:0] CTRL_LOCAL_PORT = 16'd32000,
    parameter [15:0] CTRL_HOST_PORT = 16'd32000,
    parameter [15:0] DATA_LOCAL_PORT = 16'd32001,
    parameter [15:0] DATA_HOST_PORT = 16'd32001,
    parameter integer DATA_MAX_PAYLOAD = 8972,
    parameter integer DATA_RX_REQUIRE_UDP_CHECKSUM = 1,
    parameter integer DATA_TX_UDP_CHECKSUM_ENABLE = 1,
    parameter integer CTRL_BURST_MAX = 4,
    parameter integer LEN_W = 14
) (
    input wire clk_i,
    input wire resetn_i,
    input wire link_ready_i,
    input wire ctrl_soft_resetn_i,
    output wire ctrl_channel_resetn_o,

    input wire [7:0] rx_axis_tdata_i,
    input wire rx_axis_tvalid_i,
    output wire rx_axis_tready_o,
    input wire rx_axis_tlast_i,
    output wire [7:0] tx_axis_tdata_o,
    output wire tx_axis_tvalid_o,
    input wire tx_axis_tready_i,
    output wire tx_axis_tlast_o,

    output wire ctrl_rx_valid_o,
    input wire ctrl_rx_ready_i,
    output wire [7:0] ctrl_rx_data_o,
    output wire ctrl_rx_last_o,
    output wire [10:0] ctrl_rx_len_o,
    input wire ctrl_tx_valid_i,
    output wire ctrl_tx_ready_o,
    input wire [10:0] ctrl_tx_len_i,
    input wire ctrl_tx_data_valid_i,
    output wire ctrl_tx_data_ready_o,
    input wire [7:0] ctrl_tx_data_i,
    input wire ctrl_tx_data_last_i,
    output wire ctrl_tx_error_o,

    output wire data_rx_valid_o,
    input wire data_rx_ready_i,
    output wire [7:0] data_rx_data_o,
    output wire data_rx_last_o,
    output wire [LEN_W-1:0] data_rx_len_o,
    input wire data_tx_req_valid_i,
    output wire data_tx_req_ready_o,
    input wire [LEN_W-1:0] data_tx_len_i,
    input wire data_tx_valid_i,
    output wire data_tx_ready_o,
    input wire [7:0] data_tx_data_i,
    input wire data_tx_last_i,
    input wire data_tx_cancel_valid_i,
    output wire data_tx_cancel_ready_o,
    output wire data_tx_status_valid_o,
    input wire data_tx_status_ready_i,
    output wire [2:0] data_tx_status_o,

    output wire [2:0] ctrl_rx_level_o,
    output wire [4:0] data_rx_level_o,
    output wire tx_busy_o,
    output wire [3:0] last_drop_reason_o,
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
    localparam [1:0] CR_RUN=0, CR_DRAIN=1, CR_CLEAR=2, CR_HOLD=3;
    reg [1:0] ctrl_recovery_state;

    wire ctrl_engine_active;
    wire ctrl_enable = (ctrl_recovery_state==CR_RUN) && ctrl_soft_resetn_i;
    wire ctrl_ring_resetn = resetn_i && (ctrl_recovery_state!=CR_CLEAR);
    assign ctrl_channel_resetn_o = resetn_i && ctrl_enable;

    always @(posedge clk_i) begin
        if (!resetn_i) ctrl_recovery_state <= CR_RUN;
        else case (ctrl_recovery_state)
            CR_RUN: if (!ctrl_soft_resetn_i) ctrl_recovery_state <= CR_DRAIN;
            CR_DRAIN: if (!ctrl_engine_active) ctrl_recovery_state <= CR_CLEAR;
            CR_CLEAR: ctrl_recovery_state <= CR_HOLD;
            CR_HOLD: if (ctrl_soft_resetn_i) ctrl_recovery_state <= CR_RUN;
            default: ctrl_recovery_state <= CR_RUN;
        endcase
    end

    wire ctrl_slot_available, ctrl_write_valid, ctrl_commit;
    wire [10:0] ctrl_write_offset, ctrl_commit_len;
    wire [7:0] ctrl_write_data;
    wire data_reserve_valid, data_reserve_ready;
    wire [LEN_W-1:0] data_reserve_len, data_write_offset;
    wire data_write_valid, data_commit, data_abort;
    wire [7:0] data_write_data;
    wire arp_request, frame_event, ctrl_accept, data_accept, drop_event;
    wire [3:0] drop_reason;

    fixed_host_rx_parser_dual #(
        .LOCAL_MAC(LOCAL_MAC), .LOCAL_IPV4(LOCAL_IPV4),
        .HOST_MAC(HOST_MAC), .HOST_IPV4(HOST_IPV4),
        .CTRL_LOCAL_PORT(CTRL_LOCAL_PORT), .CTRL_HOST_PORT(CTRL_HOST_PORT),
        .DATA_LOCAL_PORT(DATA_LOCAL_PORT), .DATA_HOST_PORT(DATA_HOST_PORT),
        .DATA_MAX_PAYLOAD(DATA_MAX_PAYLOAD),
        .DATA_RX_REQUIRE_UDP_CHECKSUM(DATA_RX_REQUIRE_UDP_CHECKSUM), .LEN_W(LEN_W)
    ) parser_i (
        .clk_i(clk_i), .resetn_i(resetn_i), .link_ready_i(link_ready_i),
        .ctrl_enable_i(ctrl_enable), .rx_axis_tdata_i(rx_axis_tdata_i),
        .rx_axis_tvalid_i(rx_axis_tvalid_i), .rx_axis_tready_o(rx_axis_tready_o),
        .rx_axis_tlast_i(rx_axis_tlast_i),
        .ctrl_slot_available_i(ctrl_slot_available),
        .ctrl_write_valid_o(ctrl_write_valid), .ctrl_write_offset_o(ctrl_write_offset),
        .ctrl_write_data_o(ctrl_write_data), .ctrl_commit_o(ctrl_commit),
        .ctrl_commit_length_o(ctrl_commit_len),
        .data_reserve_valid_o(data_reserve_valid), .data_reserve_ready_i(data_reserve_ready),
        .data_reserve_len_o(data_reserve_len), .data_write_valid_o(data_write_valid),
        .data_write_offset_o(data_write_offset), .data_write_data_o(data_write_data),
        .data_commit_o(data_commit), .data_abort_o(data_abort),
        .arp_reply_request_o(arp_request), .frame_event_o(frame_event),
        .ctrl_accept_event_o(ctrl_accept), .data_accept_event_o(data_accept),
        .drop_event_o(drop_event), .drop_reason_o(drop_reason)
    );

    udp_rx_payload_ring #(.MAX_UDP_PAYLOAD(1472),.SLOT_COUNT(4)) ctrl_rx_ring_i (
        .clk_i(clk_i), .resetn_i(ctrl_ring_resetn),
        .slot_available_o(ctrl_slot_available),
        .payload_write_valid_i(ctrl_write_valid),
        .payload_write_offset_i(ctrl_write_offset), .payload_write_data_i(ctrl_write_data),
        .commit_i(ctrl_commit), .commit_length_i(ctrl_commit_len),
        .msg_valid_o(ctrl_rx_valid_o), .msg_ready_i(ctrl_rx_ready_i),
        .msg_data_o(ctrl_rx_data_o), .msg_last_o(ctrl_rx_last_o),
        .msg_len_o(ctrl_rx_len_o), .level_o(ctrl_rx_level_o)
    );

    udp_data_rx_ring #(.MAX_PAYLOAD(DATA_MAX_PAYLOAD),.LEN_W(LEN_W)) data_rx_ring_i (
        .clk_i(clk_i), .resetn_i(resetn_i),
        .reserve_valid_i(data_reserve_valid), .reserve_ready_o(data_reserve_ready),
        .reserve_len_i(data_reserve_len), .write_valid_i(data_write_valid),
        .write_offset_i(data_write_offset), .write_data_i(data_write_data),
        .commit_i(data_commit), .abort_i(data_abort),
        .msg_valid_o(data_rx_valid_o), .msg_ready_i(data_rx_ready_i),
        .msg_data_o(data_rx_data_o), .msg_last_o(data_rx_last_o),
        .msg_len_o(data_rx_len_o), .level_o(data_rx_level_o)
    );

    wire ctrl_packet_valid, ctrl_packet_release, ctrl_tx_busy;
    wire ctrl_tx_ready_int, ctrl_tx_data_ready_int, ctrl_tx_error_int;
    wire [10:0] ctrl_packet_len, ctrl_read_addr;
    wire [31:0] ctrl_packet_sum;
    wire [7:0] ctrl_read_data;
    wire ctrl_tx_accept, ctrl_tx_error_event;
    udp_tx_payload_ring #(.MAX_UDP_PAYLOAD(1472),.SLOT_COUNT(2)) ctrl_tx_ring_i (
        .clk_i(clk_i), .resetn_i(ctrl_ring_resetn), .link_ready_i(link_ready_i),
        .msg_valid_i(ctrl_tx_valid_i && ctrl_enable), .msg_ready_o(ctrl_tx_ready_int),
        .msg_len_i(ctrl_tx_len_i), .msg_data_valid_i(ctrl_tx_data_valid_i && ctrl_enable),
        .msg_data_ready_o(ctrl_tx_data_ready_int), .msg_data_i(ctrl_tx_data_i),
        .msg_data_last_i(ctrl_tx_data_last_i), .msg_error_o(ctrl_tx_error_int),
        .packet_valid_o(ctrl_packet_valid), .packet_len_o(ctrl_packet_len),
        .packet_payload_sum_o(ctrl_packet_sum), .packet_release_i(ctrl_packet_release),
        .payload_read_addr_i(ctrl_read_addr), .payload_read_data_o(ctrl_read_data),
        .busy_o(ctrl_tx_busy), .accept_event_o(ctrl_tx_accept),
        .error_event_o(ctrl_tx_error_event)
    );
    assign ctrl_tx_ready_o      = ctrl_enable && ctrl_tx_ready_int;
    assign ctrl_tx_data_ready_o = ctrl_enable && ctrl_tx_data_ready_int;
    assign ctrl_tx_error_o      = ctrl_enable && ctrl_tx_error_int;

    wire data_packet_valid, data_packet_release, data_tx_busy;
    wire [LEN_W-1:0] data_packet_len, data_read_addr;
    wire [31:0] data_packet_sum;
    wire [7:0] data_read_data;
    udp_data_tx_ring #(.MAX_PAYLOAD(DATA_MAX_PAYLOAD),.LEN_W(LEN_W)) data_tx_ring_i (
        .clk_i(clk_i), .resetn_i(resetn_i), .link_ready_i(link_ready_i),
        .req_valid_i(data_tx_req_valid_i), .req_ready_o(data_tx_req_ready_o),
        .req_len_i(data_tx_len_i), .data_valid_i(data_tx_valid_i),
        .data_ready_o(data_tx_ready_o), .data_i(data_tx_data_i),
        .data_last_i(data_tx_last_i), .cancel_valid_i(data_tx_cancel_valid_i),
        .cancel_ready_o(data_tx_cancel_ready_o), .status_valid_o(data_tx_status_valid_o),
        .status_ready_i(data_tx_status_ready_i), .status_o(data_tx_status_o),
        .packet_valid_o(data_packet_valid), .packet_len_o(data_packet_len),
        .packet_payload_sum_o(data_packet_sum), .packet_release_i(data_packet_release),
        .payload_read_addr_i(data_read_addr), .payload_read_data_o(data_read_data),
        .busy_o(data_tx_busy)
    );

    wire tx_sent_event, tx_engine_busy;
    fixed_host_tx_engine_dual #(
        .LOCAL_MAC(LOCAL_MAC), .LOCAL_IPV4(LOCAL_IPV4),
        .HOST_MAC(HOST_MAC), .HOST_IPV4(HOST_IPV4),
        .CTRL_LOCAL_PORT(CTRL_LOCAL_PORT), .CTRL_HOST_PORT(CTRL_HOST_PORT),
        .DATA_LOCAL_PORT(DATA_LOCAL_PORT), .DATA_HOST_PORT(DATA_HOST_PORT),
        .DATA_TX_UDP_CHECKSUM_ENABLE(DATA_TX_UDP_CHECKSUM_ENABLE),
        .CTRL_BURST_MAX(CTRL_BURST_MAX), .LEN_W(LEN_W)
    ) tx_engine_i (
        .clk_i(clk_i), .resetn_i(resetn_i), .link_ready_i(link_ready_i),
        .ctrl_enable_i(ctrl_enable), .arp_reply_request_i(arp_request),
        .ctrl_packet_valid_i(ctrl_packet_valid), .ctrl_packet_len_i(ctrl_packet_len),
        .ctrl_packet_sum_i(ctrl_packet_sum), .ctrl_packet_release_o(ctrl_packet_release),
        .ctrl_payload_read_addr_o(ctrl_read_addr), .ctrl_payload_read_data_i(ctrl_read_data),
        .data_packet_valid_i(data_packet_valid), .data_packet_len_i(data_packet_len),
        .data_packet_sum_i(data_packet_sum), .data_packet_release_o(data_packet_release),
        .data_payload_read_addr_o(data_read_addr), .data_payload_read_data_i(data_read_data),
        .tx_axis_tdata_o(tx_axis_tdata_o), .tx_axis_tvalid_o(tx_axis_tvalid_o),
        .tx_axis_tready_i(tx_axis_tready_i), .tx_axis_tlast_o(tx_axis_tlast_o),
        .busy_o(tx_engine_busy), .ctrl_active_o(ctrl_engine_active), .sent_event_o(tx_sent_event)
    );

    wire data_tx_status_fire = data_tx_status_valid_o && data_tx_status_ready_i;
    wire data_tx_accept_event = data_tx_status_fire && (data_tx_status_o == 3'd0);
    wire data_tx_error_event = data_tx_status_fire && (data_tx_status_o != 3'd0);

    udp_transport_stats stats_i (
        .clk_i(clk_i), .resetn_i(resetn_i), .rx_frame_event_i(frame_event),
        .rx_accept_event_i(ctrl_accept||data_accept), .rx_drop_event_i(drop_event),
        .rx_drop_reason_i(drop_reason), .tx_accept_event_i(ctrl_tx_accept||data_tx_accept_event),
        .tx_sent_event_i(tx_sent_event),
        .tx_error_event_i(ctrl_tx_error_event||data_tx_error_event),
        .last_drop_reason_o(last_drop_reason_o), .rx_frames_seen_o(rx_frames_seen_o),
        .rx_udp_accepted_o(rx_udp_accepted_o), .rx_drop_endpoint_o(rx_drop_endpoint_o),
        .rx_drop_ipv4_o(rx_drop_ipv4_o), .rx_drop_udp_o(rx_drop_udp_o),
        .rx_drop_checksum_o(rx_drop_checksum_o), .rx_drop_oversize_o(rx_drop_oversize_o),
        .rx_drop_fifo_full_o(rx_drop_fifo_full_o), .tx_accepted_o(tx_accepted_o),
        .tx_sent_o(tx_sent_o), .tx_input_error_o(tx_input_error_o)
    );
    assign tx_busy_o = ctrl_tx_busy || data_tx_busy || tx_engine_busy;
endmodule
