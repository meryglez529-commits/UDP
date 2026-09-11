`timescale 1ns / 1ps

// Fixed-host Ethernet II / ARP / IPv4 / UDP receive parser.
// Payload writes are speculative; commit_o is the only signal that makes a
// candidate payload visible through udp_rx_message_fifo.
module fixed_host_rx_parser #(
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

    input  wire        slot_available_i,
    output wire        payload_write_valid_o,
    output wire [10:0] payload_write_offset_o,
    output wire [7:0]  payload_write_data_o,
    output wire        commit_o,
    output wire [10:0] commit_length_o,

    output wire        arp_reply_request_o,
    output wire        frame_event_o,
    output wire        accept_event_o,
    output reg         drop_event_o,
    output reg  [3:0]  drop_reason_o
);

    localparam [1:0] RX_IDLE     = 2'd0;
    localparam [1:0] RX_FRAME    = 2'd1;
    localparam [1:0] RX_FINALIZE = 2'd2;

    localparam [3:0] DROP_NONE     = 4'd0;
    localparam [3:0] DROP_ENDPOINT = 4'd1;
    localparam [3:0] DROP_IPV4     = 4'd2;
    localparam [3:0] DROP_UDP      = 4'd3;
    localparam [3:0] DROP_CHECKSUM = 4'd4;
    localparam [3:0] DROP_OVERSIZE = 4'd5;
    localparam [3:0] DROP_FIFO     = 4'd6;

    function [15:0] fold_sum16;
        input [31:0] sum_i;
        reg [31:0] folded;
        begin
            folded = (sum_i & 32'h0000_FFFF) + (sum_i >> 16);
            folded = (folded & 32'h0000_FFFF) + (folded >> 16);
            fold_sum16 = folded[15:0];
        end
    endfunction

    reg [1:0]  rx_state;
    reg [10:0] rx_byte_index;
    reg [10:0] rx_frame_length;
    reg        rx_frame_good;
    reg        rx_have_slot;

    reg [47:0] rx_dst_mac;
    reg [47:0] rx_src_mac;
    reg [15:0] rx_ethertype;
    reg [15:0] rx_ip_total_length;
    reg [15:0] rx_ip_flags_fragment;
    reg [31:0] rx_src_ipv4;
    reg [31:0] rx_dst_ipv4;
    reg [15:0] rx_udp_src_port;
    reg [15:0] rx_udp_dst_port;
    reg [15:0] rx_udp_length;
    reg [15:0] rx_udp_checksum_field;

    reg [15:0] rx_arp_htype;
    reg [15:0] rx_arp_ptype;
    reg [7:0]  rx_arp_hlen;
    reg [7:0]  rx_arp_plen;
    reg [15:0] rx_arp_oper;
    reg [47:0] rx_arp_sha;
    reg [31:0] rx_arp_spa;
    reg [31:0] rx_arp_tpa;

    reg [31:0] rx_ip_sum;
    reg [7:0]  rx_ip_word_hi;
    reg [31:0] rx_udp_sum;
    reg [7:0]  rx_udp_word_hi;
    reg [10:0] rx_payload_written;

    wire [10:0] rx_current_index = (rx_state == RX_IDLE) ?
                                     11'd0 : rx_byte_index;
    wire rx_input_fire = rx_axis_tvalid_i && rx_axis_tready_o;
    wire rx_finalize = (rx_state == RX_FINALIZE) && link_ready_i;

    assign rx_axis_tready_o = resetn_i && link_ready_i &&
                              (rx_state != RX_FINALIZE);

    wire rx_ipv4_endpoint_ok = (rx_dst_mac == LOCAL_MAC) &&
                               (rx_src_mac == HOST_MAC) &&
                               (rx_src_ipv4 == HOST_IPV4) &&
                               (rx_dst_ipv4 == LOCAL_IPV4) &&
                               (rx_udp_src_port == HOST_UDP_PORT) &&
                               (rx_udp_dst_port == LOCAL_UDP_PORT);

    wire rx_ipv4_outer_length_ok = (rx_ip_total_length >= 16'd29) &&
                                    (rx_frame_length >=
                                     (rx_ip_total_length + 16'd14));
    wire rx_udp_length_ok = (rx_udp_length >= 16'd9) &&
                            (rx_ip_total_length ==
                             (rx_udp_length + 16'd20)) &&
                            (rx_payload_written ==
                             (rx_udp_length - 16'd8));
    wire rx_ipv4_length_ok = rx_ipv4_outer_length_ok && rx_udp_length_ok;
    wire rx_ipv4_not_oversize =
        (rx_udp_length <= (MAX_UDP_PAYLOAD + 16'd8));

    wire [31:0] rx_udp_sum_with_pseudo = rx_udp_sum +
        ((rx_udp_length[0]) ? {rx_udp_word_hi, 8'h00} : 16'h0000) +
        rx_src_ipv4[31:16] + rx_src_ipv4[15:0] +
        rx_dst_ipv4[31:16] + rx_dst_ipv4[15:0] +
        16'h0011 + rx_udp_length;
    wire rx_ipv4_checksum_ok = (fold_sum16(rx_ip_sum) == 16'hFFFF);
    wire rx_udp_checksum_ok = (rx_udp_checksum_field != 16'h0000) &&
                              (fold_sum16(rx_udp_sum_with_pseudo) == 16'hFFFF);

    wire rx_ipv4_base_ok = (rx_ethertype == 16'h0800) && rx_frame_good &&
                            rx_ipv4_length_ok && rx_ipv4_not_oversize &&
                            rx_ipv4_endpoint_ok && rx_ipv4_checksum_ok &&
                            rx_udp_checksum_ok;

    wire rx_arp_request_ok = (rx_ethertype == 16'h0806) && rx_frame_good &&
                             (rx_frame_length >= 11'd42) &&
                             ((rx_dst_mac == 48'hFFFF_FFFF_FFFF) ||
                              (rx_dst_mac == LOCAL_MAC)) &&
                             (rx_src_mac == HOST_MAC) &&
                             (rx_arp_htype == 16'h0001) &&
                             (rx_arp_ptype == 16'h0800) &&
                             (rx_arp_hlen == 8'd6) &&
                             (rx_arp_plen == 8'd4) &&
                             (rx_arp_oper == 16'h0001) &&
                             (rx_arp_sha == HOST_MAC) &&
                             (rx_arp_spa == HOST_IPV4) &&
                             (rx_arp_tpa == LOCAL_IPV4);

    assign payload_write_valid_o = rx_input_fire &&
        (rx_state != RX_IDLE) && (rx_ethertype == 16'h0800) &&
        (rx_current_index >= 11'd42) &&
        (rx_current_index < (rx_udp_length + 16'd34)) &&
        rx_have_slot && (rx_payload_written < MAX_UDP_PAYLOAD);
    assign payload_write_offset_o = rx_payload_written;
    assign payload_write_data_o = rx_axis_tdata_i;

    assign commit_o = rx_finalize && rx_ipv4_base_ok && rx_have_slot;
    assign commit_length_o = rx_payload_written;
    assign arp_reply_request_o = rx_finalize && rx_arp_request_ok;
    assign frame_event_o = rx_finalize;
    assign accept_event_o = commit_o;

    always @* begin
        drop_event_o = 1'b0;
        drop_reason_o = DROP_NONE;
        if (rx_finalize && (rx_ethertype == 16'h0800)) begin
            if (!rx_frame_good || !rx_ipv4_outer_length_ok) begin
                drop_event_o = 1'b1;
                drop_reason_o = DROP_IPV4;
            end else if (!rx_ipv4_not_oversize) begin
                drop_event_o = 1'b1;
                drop_reason_o = DROP_OVERSIZE;
            end else if (!rx_udp_length_ok) begin
                drop_event_o = 1'b1;
                drop_reason_o = DROP_UDP;
            end else if (!rx_ipv4_endpoint_ok) begin
                drop_event_o = 1'b1;
                drop_reason_o = DROP_ENDPOINT;
            end else if (!rx_ipv4_checksum_ok || !rx_udp_checksum_ok) begin
                drop_event_o = 1'b1;
                drop_reason_o = DROP_CHECKSUM;
            end else if (!rx_have_slot) begin
                drop_event_o = 1'b1;
                drop_reason_o = DROP_FIFO;
            end
        end
    end

    always @(posedge clk_i) begin
        if (!resetn_i) begin
            rx_state              <= RX_IDLE;
            rx_byte_index         <= 11'd0;
            rx_frame_length       <= 11'd0;
            rx_frame_good         <= 1'b1;
            rx_have_slot          <= 1'b0;
            rx_dst_mac            <= 48'd0;
            rx_src_mac            <= 48'd0;
            rx_ethertype          <= 16'd0;
            rx_ip_total_length    <= 16'd0;
            rx_ip_flags_fragment  <= 16'd0;
            rx_src_ipv4           <= 32'd0;
            rx_dst_ipv4           <= 32'd0;
            rx_udp_src_port       <= 16'd0;
            rx_udp_dst_port       <= 16'd0;
            rx_udp_length         <= 16'd0;
            rx_udp_checksum_field <= 16'd0;
            rx_arp_htype          <= 16'd0;
            rx_arp_ptype          <= 16'd0;
            rx_arp_hlen           <= 8'd0;
            rx_arp_plen           <= 8'd0;
            rx_arp_oper           <= 16'd0;
            rx_arp_sha            <= 48'd0;
            rx_arp_spa            <= 32'd0;
            rx_arp_tpa            <= 32'd0;
            rx_ip_sum             <= 32'd0;
            rx_ip_word_hi         <= 8'd0;
            rx_udp_sum            <= 32'd0;
            rx_udp_word_hi        <= 8'd0;
            rx_payload_written    <= 11'd0;
        end else if (!link_ready_i) begin
            // Committed messages live in the FIFO; only this partial frame dies.
            rx_state           <= RX_IDLE;
            rx_byte_index      <= 11'd0;
            rx_payload_written <= 11'd0;
        end else if (rx_state == RX_FINALIZE) begin
            rx_state <= RX_IDLE;
        end else if (rx_input_fire) begin
            if (rx_state == RX_IDLE) begin
                rx_state              <= rx_axis_tlast_i ? RX_FINALIZE : RX_FRAME;
                rx_byte_index         <= 11'd1;
                rx_frame_length       <= rx_axis_tlast_i ? 11'd1 : 11'd0;
                rx_frame_good         <= 1'b1;
                rx_have_slot          <= slot_available_i;
                rx_dst_mac            <= {40'd0, rx_axis_tdata_i};
                rx_src_mac            <= 48'd0;
                rx_ethertype          <= 16'd0;
                rx_ip_total_length    <= 16'd0;
                rx_ip_flags_fragment  <= 16'd0;
                rx_src_ipv4           <= 32'd0;
                rx_dst_ipv4           <= 32'd0;
                rx_udp_src_port       <= 16'd0;
                rx_udp_dst_port       <= 16'd0;
                rx_udp_length         <= 16'd0;
                rx_udp_checksum_field <= 16'd0;
                rx_arp_htype          <= 16'd0;
                rx_arp_ptype          <= 16'd0;
                rx_arp_hlen           <= 8'd0;
                rx_arp_plen           <= 8'd0;
                rx_arp_oper           <= 16'd0;
                rx_arp_sha            <= 48'd0;
                rx_arp_spa            <= 32'd0;
                rx_arp_tpa            <= 32'd0;
                rx_ip_sum             <= 32'd0;
                rx_ip_word_hi         <= 8'd0;
                rx_udp_sum            <= 32'd0;
                rx_udp_word_hi        <= 8'd0;
                rx_payload_written    <= 11'd0;
            end else begin
                if (rx_axis_tlast_i) begin
                    rx_state        <= RX_FINALIZE;
                    rx_frame_length <= rx_current_index + 1'b1;
                end else begin
                    rx_byte_index <= rx_byte_index + 1'b1;
                end

                if (rx_current_index <= 11'd5)
                    rx_dst_mac <= {rx_dst_mac[39:0], rx_axis_tdata_i};
                else if ((rx_current_index >= 11'd6) &&
                         (rx_current_index <= 11'd11))
                    rx_src_mac <= {rx_src_mac[39:0], rx_axis_tdata_i};

                case (rx_current_index)
                    11'd12: rx_ethertype[15:8] <= rx_axis_tdata_i;
                    11'd13: rx_ethertype[7:0]  <= rx_axis_tdata_i;
                    11'd14: if ((rx_ethertype == 16'h0800) &&
                                (rx_axis_tdata_i != 8'h45))
                                rx_frame_good <= 1'b0;
                    11'd16: rx_ip_total_length[15:8] <= rx_axis_tdata_i;
                    11'd17: rx_ip_total_length[7:0]  <= rx_axis_tdata_i;
                    11'd20: rx_ip_flags_fragment[15:8] <= rx_axis_tdata_i;
                    11'd21: begin
                        rx_ip_flags_fragment[7:0] <= rx_axis_tdata_i;
                        if ((rx_ethertype == 16'h0800) &&
                            (({rx_ip_flags_fragment[15:8], rx_axis_tdata_i} &
                              16'hBFFF) != 0))
                            rx_frame_good <= 1'b0;
                    end
                    11'd22: if ((rx_ethertype == 16'h0800) &&
                                (rx_axis_tdata_i == 8'h00))
                                rx_frame_good <= 1'b0;
                    11'd23: if ((rx_ethertype == 16'h0800) &&
                                (rx_axis_tdata_i != 8'h11))
                                rx_frame_good <= 1'b0;
                    11'd34: rx_udp_src_port[15:8] <= rx_axis_tdata_i;
                    11'd35: rx_udp_src_port[7:0]  <= rx_axis_tdata_i;
                    11'd36: rx_udp_dst_port[15:8] <= rx_axis_tdata_i;
                    11'd37: rx_udp_dst_port[7:0]  <= rx_axis_tdata_i;
                    11'd38: rx_udp_length[15:8] <= rx_axis_tdata_i;
                    11'd39: rx_udp_length[7:0]  <= rx_axis_tdata_i;
                    11'd40: rx_udp_checksum_field[15:8] <= rx_axis_tdata_i;
                    11'd41: rx_udp_checksum_field[7:0]  <= rx_axis_tdata_i;
                    default: ;
                endcase

                if ((rx_current_index >= 11'd26) &&
                    (rx_current_index <= 11'd29))
                    rx_src_ipv4 <= {rx_src_ipv4[23:0], rx_axis_tdata_i};
                if ((rx_current_index >= 11'd30) &&
                    (rx_current_index <= 11'd33))
                    rx_dst_ipv4 <= {rx_dst_ipv4[23:0], rx_axis_tdata_i};

                if ((rx_ethertype == 16'h0800) &&
                    (rx_current_index == 11'd14))
                    rx_ip_word_hi <= rx_axis_tdata_i;
                else if ((rx_ethertype == 16'h0800) &&
                         (rx_current_index >= 11'd15) &&
                         (rx_current_index <= 11'd33)) begin
                    if (!rx_current_index[0])
                        rx_ip_word_hi <= rx_axis_tdata_i;
                    else
                        rx_ip_sum <= rx_ip_sum +
                                     {rx_ip_word_hi, rx_axis_tdata_i};
                end

                if ((rx_ethertype == 16'h0800) &&
                    (rx_current_index >= 11'd34) &&
                    ((rx_current_index <= 11'd39) ||
                     (rx_current_index < (rx_udp_length + 16'd34)))) begin
                    if (!rx_current_index[0])
                        rx_udp_word_hi <= rx_axis_tdata_i;
                    else
                        rx_udp_sum <= rx_udp_sum +
                                      {rx_udp_word_hi, rx_axis_tdata_i};
                end

                if ((rx_ethertype == 16'h0800) &&
                    (rx_current_index >= 11'd42) &&
                    (rx_current_index < (rx_udp_length + 16'd34)))
                    rx_payload_written <= rx_payload_written + 1'b1;

                case (rx_current_index)
                    11'd14: rx_arp_htype[15:8] <= rx_axis_tdata_i;
                    11'd15: rx_arp_htype[7:0]  <= rx_axis_tdata_i;
                    11'd16: rx_arp_ptype[15:8] <= rx_axis_tdata_i;
                    11'd17: rx_arp_ptype[7:0]  <= rx_axis_tdata_i;
                    11'd18: rx_arp_hlen <= rx_axis_tdata_i;
                    11'd19: rx_arp_plen <= rx_axis_tdata_i;
                    11'd20: rx_arp_oper[15:8] <= rx_axis_tdata_i;
                    11'd21: rx_arp_oper[7:0]  <= rx_axis_tdata_i;
                    default: ;
                endcase
                if ((rx_current_index >= 11'd22) &&
                    (rx_current_index <= 11'd27))
                    rx_arp_sha <= {rx_arp_sha[39:0], rx_axis_tdata_i};
                if ((rx_current_index >= 11'd28) &&
                    (rx_current_index <= 11'd31))
                    rx_arp_spa <= {rx_arp_spa[23:0], rx_axis_tdata_i};
                if ((rx_current_index >= 11'd38) &&
                    (rx_current_index <= 11'd41))
                    rx_arp_tpa <= {rx_arp_tpa[23:0], rx_axis_tdata_i};
            end
        end
    end

endmodule
