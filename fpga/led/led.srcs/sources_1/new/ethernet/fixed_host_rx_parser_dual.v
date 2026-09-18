`timescale 1ns / 1ps

// Shared Ethernet/IPv4/UDP parser for independent CONTROL and DATA ports.
// The current frame is classified after the UDP ports and length are known;
// only the selected queue receives speculative payload writes and a final
// commit.  A full DATA queue never stalls the physical receive stream.
module fixed_host_rx_parser_dual #(
    parameter [47:0] LOCAL_MAC = 48'h02_DB_50_00_00_01,
    parameter [31:0] LOCAL_IPV4 = 32'hC0A8_0114,
    parameter [47:0] HOST_MAC = 48'h9C69_D31A_4C6D,
    parameter [31:0] HOST_IPV4 = 32'hC0A8_010A,
    parameter [15:0] CTRL_LOCAL_PORT = 16'd32000,
    parameter [15:0] CTRL_HOST_PORT = 16'd32000,
    parameter [15:0] DATA_LOCAL_PORT = 16'd32001,
    parameter [15:0] DATA_HOST_PORT = 16'd32001,
    parameter integer CTRL_MAX_PAYLOAD = 1472,
    parameter integer DATA_MAX_PAYLOAD = 8972,
    parameter integer DATA_RX_REQUIRE_UDP_CHECKSUM = 1,
    parameter integer LEN_W = 14
) (
    input  wire                 clk_i,
    input  wire                 resetn_i,
    input  wire                 link_ready_i,
    input  wire                 ctrl_enable_i,

    input  wire [7:0]           rx_axis_tdata_i,
    input  wire                 rx_axis_tvalid_i,
    output wire                 rx_axis_tready_o,
    input  wire                 rx_axis_tlast_i,

    input  wire                 ctrl_slot_available_i,
    output wire                 ctrl_write_valid_o,
    output wire [10:0]          ctrl_write_offset_o,
    output wire [7:0]           ctrl_write_data_o,
    output wire                 ctrl_commit_o,
    output wire [10:0]          ctrl_commit_length_o,

    output wire                 data_reserve_valid_o,
    input  wire                 data_reserve_ready_i,
    output wire [LEN_W-1:0]     data_reserve_len_o,
    output wire                 data_write_valid_o,
    output wire [LEN_W-1:0]     data_write_offset_o,
    output wire [7:0]           data_write_data_o,
    output wire                 data_commit_o,
    output wire                 data_abort_o,

    output wire                 arp_reply_request_o,
    output wire                 frame_event_o,
    output wire                 ctrl_accept_event_o,
    output wire                 data_accept_event_o,
    output reg                  drop_event_o,
    output reg  [3:0]           drop_reason_o
);

    localparam [1:0] RX_IDLE=0, RX_FRAME=1, RX_FINALIZE=2;
    localparam [1:0] TARGET_NONE=0, TARGET_CTRL=1, TARGET_DATA=2;
    localparam [3:0] DROP_NONE=0, DROP_ENDPOINT=1, DROP_IPV4=2,
                     DROP_UDP=3, DROP_CHECKSUM=4, DROP_OVERSIZE=5,
                     DROP_FIFO=6;

    function [15:0] fold_sum16;
        input [31:0] sum_i;
        reg [31:0] folded;
        begin
            folded = (sum_i & 32'hffff) + (sum_i >> 16);
            folded = (folded & 32'hffff) + (folded >> 16);
            fold_sum16 = folded[15:0];
        end
    endfunction

    reg [1:0] rx_state;
    reg [15:0] rx_byte_index, rx_frame_length;
    reg rx_frame_good, rx_have_resource, rx_data_reserved, rx_ctrl_blocked;
    reg [1:0] rx_target;
    reg [47:0] rx_dst_mac, rx_src_mac;
    reg [15:0] rx_ethertype, rx_ip_total_length, rx_ip_flags_fragment;
    reg [31:0] rx_src_ipv4, rx_dst_ipv4;
    reg [15:0] rx_udp_src_port, rx_udp_dst_port, rx_udp_length;
    reg [15:0] rx_udp_checksum_field;
    reg [15:0] rx_arp_htype, rx_arp_ptype, rx_arp_oper;
    reg [7:0] rx_arp_hlen, rx_arp_plen;
    reg [47:0] rx_arp_sha;
    reg [31:0] rx_arp_spa, rx_arp_tpa;
    reg [31:0] rx_ip_sum, rx_udp_sum;
    reg [7:0] rx_ip_word_hi, rx_udp_word_hi;
    reg [LEN_W-1:0] rx_payload_written;

    wire [15:0] rx_current_index = (rx_state == RX_IDLE) ? 16'd0 : rx_byte_index;
    wire rx_input_fire = rx_axis_tvalid_i && rx_axis_tready_o;
    wire rx_finalize = (rx_state == RX_FINALIZE) && link_ready_i;
    wire [15:0] udp_length_at_byte39 = {rx_udp_length[15:8], rx_axis_tdata_i};
    wire ports_are_ctrl = (rx_udp_src_port == CTRL_HOST_PORT) &&
                          (rx_udp_dst_port == CTRL_LOCAL_PORT);
    wire ports_are_data = (rx_udp_src_port == DATA_HOST_PORT) &&
                          (rx_udp_dst_port == DATA_LOCAL_PORT);

    assign rx_axis_tready_o = resetn_i && link_ready_i &&
                              (rx_state != RX_FINALIZE);
    assign data_reserve_valid_o = rx_input_fire &&
        (rx_current_index == 16'd39) && ports_are_data &&
        (udp_length_at_byte39 >= 16'd9) &&
        (udp_length_at_byte39 <= (DATA_MAX_PAYLOAD + 16'd8));
    assign data_reserve_len_o = udp_length_at_byte39 - 16'd8;

    wire mac_ip_endpoint_ok = (rx_dst_mac == LOCAL_MAC) &&
                              (rx_src_mac == HOST_MAC) &&
                              (rx_src_ipv4 == HOST_IPV4) &&
                              (rx_dst_ipv4 == LOCAL_IPV4);
    wire port_endpoint_ok = ((rx_target == TARGET_CTRL) &&
        (rx_udp_src_port == CTRL_HOST_PORT) &&
        (rx_udp_dst_port == CTRL_LOCAL_PORT)) ||
        ((rx_target == TARGET_DATA) &&
        (rx_udp_src_port == DATA_HOST_PORT) &&
        (rx_udp_dst_port == DATA_LOCAL_PORT));
    wire endpoint_ok = mac_ip_endpoint_ok && port_endpoint_ok;
    wire outer_length_ok = (rx_ip_total_length >= 16'd29) &&
                           (rx_frame_length >= (rx_ip_total_length + 16'd14));
    wire udp_length_ok = (rx_udp_length >= 16'd9) &&
                         (rx_ip_total_length == rx_udp_length + 16'd20) &&
                         (rx_payload_written == rx_udp_length - 16'd8);
    wire channel_length_ok = ((rx_target == TARGET_CTRL) &&
        (rx_payload_written <= CTRL_MAX_PAYLOAD)) ||
        ((rx_target == TARGET_DATA) &&
        (rx_payload_written <= DATA_MAX_PAYLOAD));
    wire [31:0] udp_sum_with_pseudo = rx_udp_sum +
        (rx_udp_length[0] ? {rx_udp_word_hi,8'h00} : 16'h0000) +
        rx_src_ipv4[31:16] + rx_src_ipv4[15:0] +
        rx_dst_ipv4[31:16] + rx_dst_ipv4[15:0] +
        16'h0011 + rx_udp_length;
    wire ip_checksum_ok = (fold_sum16(rx_ip_sum) == 16'hffff);
    wire udp_nonzero_ok = (rx_udp_checksum_field != 16'h0000) &&
                          (fold_sum16(udp_sum_with_pseudo) == 16'hffff);
    wire udp_checksum_ok = (rx_target == TARGET_DATA) ?
        ((DATA_RX_REQUIRE_UDP_CHECKSUM != 0) ? udp_nonzero_ok :
         ((rx_udp_checksum_field == 0) || udp_nonzero_ok)) : udp_nonzero_ok;
    wire ipv4_base_ok = (rx_ethertype == 16'h0800) && rx_frame_good &&
        outer_length_ok && udp_length_ok && channel_length_ok && endpoint_ok &&
        ip_checksum_ok && udp_checksum_ok;

    wire arp_request_ok = (rx_ethertype == 16'h0806) && rx_frame_good &&
        (rx_frame_length >= 16'd42) &&
        ((rx_dst_mac == 48'hffff_ffff_ffff) || (rx_dst_mac == LOCAL_MAC)) &&
        (rx_src_mac == HOST_MAC) && (rx_arp_htype == 16'h0001) &&
        (rx_arp_ptype == 16'h0800) && (rx_arp_hlen == 8'd6) &&
        (rx_arp_plen == 8'd4) && (rx_arp_oper == 16'h0001) &&
        (rx_arp_sha == HOST_MAC) && (rx_arp_spa == HOST_IPV4) &&
        (rx_arp_tpa == LOCAL_IPV4);

    wire payload_byte = rx_input_fire && (rx_state != RX_IDLE) &&
        (rx_ethertype == 16'h0800) && (rx_current_index >= 16'd42) &&
        (rx_current_index < (rx_udp_length + 16'd34));
    assign ctrl_write_valid_o = payload_byte && (rx_target == TARGET_CTRL) &&
        rx_have_resource && !rx_ctrl_blocked &&
        (rx_payload_written < CTRL_MAX_PAYLOAD);
    assign ctrl_write_offset_o = rx_payload_written[10:0];
    assign ctrl_write_data_o = rx_axis_tdata_i;
    assign data_write_valid_o = payload_byte && (rx_target == TARGET_DATA) &&
        rx_have_resource && (rx_payload_written < DATA_MAX_PAYLOAD);
    assign data_write_offset_o = rx_payload_written;
    assign data_write_data_o = rx_axis_tdata_i;

    assign ctrl_commit_o = rx_finalize && ipv4_base_ok &&
        (rx_target == TARGET_CTRL) && rx_have_resource &&
        !rx_ctrl_blocked && ctrl_enable_i;
    assign ctrl_commit_length_o = rx_payload_written[10:0];
    assign data_commit_o = rx_finalize && ipv4_base_ok &&
        (rx_target == TARGET_DATA) && rx_have_resource && rx_data_reserved;
    assign data_abort_o = rx_finalize && rx_data_reserved && !data_commit_o;
    assign arp_reply_request_o = rx_finalize && arp_request_ok;
    assign frame_event_o = rx_finalize;
    assign ctrl_accept_event_o = ctrl_commit_o;
    assign data_accept_event_o = data_commit_o;

    always @* begin
        drop_event_o = 1'b0;
        drop_reason_o = DROP_NONE;
        if (rx_finalize && (rx_ethertype == 16'h0800)) begin
            if (!rx_frame_good || !outer_length_ok || !ip_checksum_ok) begin
                drop_event_o = 1'b1; drop_reason_o = DROP_IPV4;
            end else if ((rx_target == TARGET_NONE) || !endpoint_ok) begin
                drop_event_o = 1'b1; drop_reason_o = DROP_ENDPOINT;
            end else if (!channel_length_ok) begin
                drop_event_o = 1'b1; drop_reason_o = DROP_OVERSIZE;
            end else if (!udp_length_ok) begin
                drop_event_o = 1'b1; drop_reason_o = DROP_UDP;
            end else if (!udp_checksum_ok) begin
                drop_event_o = 1'b1; drop_reason_o = DROP_CHECKSUM;
            end else if (!rx_have_resource ||
                         ((rx_target == TARGET_CTRL) && rx_ctrl_blocked)) begin
                drop_event_o = 1'b1; drop_reason_o = DROP_FIFO;
            end
        end
    end

    always @(posedge clk_i) begin
        if (!resetn_i) begin
            rx_state <= RX_IDLE; rx_byte_index <= 0; rx_frame_length <= 0;
            rx_frame_good <= 1; rx_have_resource <= 0; rx_data_reserved <= 0;
            rx_ctrl_blocked <= 0; rx_target <= TARGET_NONE;
            rx_dst_mac<=0; rx_src_mac<=0; rx_ethertype<=0; rx_ip_total_length<=0;
            rx_ip_flags_fragment<=0; rx_src_ipv4<=0; rx_dst_ipv4<=0;
            rx_udp_src_port<=0; rx_udp_dst_port<=0; rx_udp_length<=0;
            rx_udp_checksum_field<=0; rx_arp_htype<=0; rx_arp_ptype<=0;
            rx_arp_hlen<=0; rx_arp_plen<=0; rx_arp_oper<=0; rx_arp_sha<=0;
            rx_arp_spa<=0; rx_arp_tpa<=0; rx_ip_sum<=0; rx_ip_word_hi<=0;
            rx_udp_sum<=0; rx_udp_word_hi<=0; rx_payload_written<=0;
        end else if (!link_ready_i) begin
            rx_state <= RX_IDLE; rx_byte_index <= 0; rx_payload_written <= 0;
            rx_data_reserved <= 0;
        end else if (rx_state == RX_FINALIZE) begin
            rx_state <= RX_IDLE;
            rx_data_reserved <= 0;
        end else begin
            if ((rx_state != RX_IDLE) && !ctrl_enable_i)
                rx_ctrl_blocked <= 1'b1;
            if (rx_input_fire) begin
                if (rx_state == RX_IDLE) begin
                    rx_state <= rx_axis_tlast_i ? RX_FINALIZE : RX_FRAME;
                    rx_byte_index <= 1; rx_frame_length <= rx_axis_tlast_i ? 1 : 0;
                    rx_frame_good <= 1; rx_have_resource <= 0;
                    rx_data_reserved <= 0; rx_ctrl_blocked <= !ctrl_enable_i;
                    rx_target <= TARGET_NONE; rx_dst_mac <= {40'd0,rx_axis_tdata_i};
                    rx_src_mac<=0; rx_ethertype<=0; rx_ip_total_length<=0;
                    rx_ip_flags_fragment<=0; rx_src_ipv4<=0; rx_dst_ipv4<=0;
                    rx_udp_src_port<=0; rx_udp_dst_port<=0; rx_udp_length<=0;
                    rx_udp_checksum_field<=0; rx_arp_htype<=0; rx_arp_ptype<=0;
                    rx_arp_hlen<=0; rx_arp_plen<=0; rx_arp_oper<=0; rx_arp_sha<=0;
                    rx_arp_spa<=0; rx_arp_tpa<=0; rx_ip_sum<=0; rx_ip_word_hi<=0;
                    rx_udp_sum<=0; rx_udp_word_hi<=0; rx_payload_written<=0;
                end else begin
                    if (rx_axis_tlast_i) begin
                        rx_state <= RX_FINALIZE;
                        rx_frame_length <= rx_current_index + 1'b1;
                    end else rx_byte_index <= rx_byte_index + 1'b1;

                    if (rx_current_index <= 5)
                        rx_dst_mac <= {rx_dst_mac[39:0],rx_axis_tdata_i};
                    else if ((rx_current_index >= 6) && (rx_current_index <= 11))
                        rx_src_mac <= {rx_src_mac[39:0],rx_axis_tdata_i};
                    case (rx_current_index)
                        12: rx_ethertype[15:8] <= rx_axis_tdata_i;
                        13: rx_ethertype[7:0] <= rx_axis_tdata_i;
                        14: if ((rx_ethertype==16'h0800)&&(rx_axis_tdata_i!=8'h45)) rx_frame_good<=0;
                        16: rx_ip_total_length[15:8] <= rx_axis_tdata_i;
                        17: rx_ip_total_length[7:0] <= rx_axis_tdata_i;
                        20: rx_ip_flags_fragment[15:8] <= rx_axis_tdata_i;
                        21: begin
                            rx_ip_flags_fragment[7:0] <= rx_axis_tdata_i;
                            if ((rx_ethertype==16'h0800) &&
                                (({rx_ip_flags_fragment[15:8],rx_axis_tdata_i}&16'hbfff)!=0))
                                rx_frame_good<=0;
                        end
                        22: if ((rx_ethertype==16'h0800)&&(rx_axis_tdata_i==0)) rx_frame_good<=0;
                        23: if ((rx_ethertype==16'h0800)&&(rx_axis_tdata_i!=8'h11)) rx_frame_good<=0;
                        34: rx_udp_src_port[15:8] <= rx_axis_tdata_i;
                        35: rx_udp_src_port[7:0] <= rx_axis_tdata_i;
                        36: rx_udp_dst_port[15:8] <= rx_axis_tdata_i;
                        37: rx_udp_dst_port[7:0] <= rx_axis_tdata_i;
                        38: rx_udp_length[15:8] <= rx_axis_tdata_i;
                        39: begin
                            rx_udp_length[7:0] <= rx_axis_tdata_i;
                            if (ports_are_ctrl) begin
                                rx_target <= TARGET_CTRL;
                                rx_have_resource <= ctrl_enable_i && ctrl_slot_available_i;
                            end else if (ports_are_data) begin
                                rx_target <= TARGET_DATA;
                                rx_have_resource <= data_reserve_ready_i && data_reserve_valid_o;
                                rx_data_reserved <= data_reserve_ready_i && data_reserve_valid_o;
                            end else begin
                                rx_target <= TARGET_NONE;
                                rx_have_resource <= 0;
                            end
                        end
                        40: rx_udp_checksum_field[15:8] <= rx_axis_tdata_i;
                        41: rx_udp_checksum_field[7:0] <= rx_axis_tdata_i;
                        default: ;
                    endcase
                    if ((rx_current_index>=26)&&(rx_current_index<=29))
                        rx_src_ipv4 <= {rx_src_ipv4[23:0],rx_axis_tdata_i};
                    if ((rx_current_index>=30)&&(rx_current_index<=33))
                        rx_dst_ipv4 <= {rx_dst_ipv4[23:0],rx_axis_tdata_i};

                    if ((rx_ethertype==16'h0800)&&(rx_current_index==14))
                        rx_ip_word_hi <= rx_axis_tdata_i;
                    else if ((rx_ethertype==16'h0800)&&(rx_current_index>=15)&&
                             (rx_current_index<=33)) begin
                        if (!rx_current_index[0]) rx_ip_word_hi<=rx_axis_tdata_i;
                        else rx_ip_sum<=rx_ip_sum+{rx_ip_word_hi,rx_axis_tdata_i};
                    end
                    if ((rx_ethertype==16'h0800)&&(rx_current_index>=34)&&
                        ((rx_current_index<=39)||(rx_current_index<(rx_udp_length+16'd34)))) begin
                        if (!rx_current_index[0]) rx_udp_word_hi<=rx_axis_tdata_i;
                        else rx_udp_sum<=rx_udp_sum+{rx_udp_word_hi,rx_axis_tdata_i};
                    end
                    if ((rx_ethertype==16'h0800)&&(rx_current_index>=42)&&
                        (rx_current_index<(rx_udp_length+16'd34)))
                        rx_payload_written<=rx_payload_written+1'b1;

                    case (rx_current_index)
                        14: rx_arp_htype[15:8]<=rx_axis_tdata_i;
                        15: rx_arp_htype[7:0]<=rx_axis_tdata_i;
                        16: rx_arp_ptype[15:8]<=rx_axis_tdata_i;
                        17: rx_arp_ptype[7:0]<=rx_axis_tdata_i;
                        18: rx_arp_hlen<=rx_axis_tdata_i;
                        19: rx_arp_plen<=rx_axis_tdata_i;
                        20: rx_arp_oper[15:8]<=rx_axis_tdata_i;
                        21: rx_arp_oper[7:0]<=rx_axis_tdata_i;
                        default: ;
                    endcase
                    if ((rx_current_index>=22)&&(rx_current_index<=27))
                        rx_arp_sha<={rx_arp_sha[39:0],rx_axis_tdata_i};
                    if ((rx_current_index>=28)&&(rx_current_index<=31))
                        rx_arp_spa<={rx_arp_spa[23:0],rx_axis_tdata_i};
                    if ((rx_current_index>=38)&&(rx_current_index<=41))
                        rx_arp_tpa<={rx_arp_tpa[23:0],rx_axis_tdata_i};
                end
            end
        end
    end
endmodule
