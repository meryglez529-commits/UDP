`timescale 1ns / 1ps

// Shared ARP/CONTROL/DATA frame scheduler and Ethernet/IPv4/UDP serializer.
// Arbitration occurs only in IDLE.  The selected descriptor and source remain
// locked until the complete frame has entered the Ethernet client FIFO.
module fixed_host_tx_engine_dual #(
    parameter [47:0] LOCAL_MAC = 48'h02_DB_50_00_00_01,
    parameter [31:0] LOCAL_IPV4 = 32'hC0A8_0114,
    parameter [47:0] HOST_MAC = 48'h9C69_D31A_4C6D,
    parameter [31:0] HOST_IPV4 = 32'hC0A8_010A,
    parameter [15:0] CTRL_LOCAL_PORT = 16'd32000,
    parameter [15:0] CTRL_HOST_PORT = 16'd32000,
    parameter [15:0] DATA_LOCAL_PORT = 16'd32001,
    parameter [15:0] DATA_HOST_PORT = 16'd32001,
    parameter integer DATA_TX_UDP_CHECKSUM_ENABLE = 1,
    parameter integer CTRL_BURST_MAX = 4,
    parameter integer LEN_W = 14
) (
    input  wire                 clk_i,
    input  wire                 resetn_i,
    input  wire                 link_ready_i,
    input  wire                 ctrl_enable_i,
    input  wire                 arp_reply_request_i,

    input  wire                 ctrl_packet_valid_i,
    input  wire [10:0]          ctrl_packet_len_i,
    input  wire [31:0]          ctrl_packet_sum_i,
    output wire                 ctrl_packet_release_o,
    output wire [10:0]          ctrl_payload_read_addr_o,
    input  wire [7:0]           ctrl_payload_read_data_i,

    input  wire                 data_packet_valid_i,
    input  wire [LEN_W-1:0]     data_packet_len_i,
    input  wire [31:0]          data_packet_sum_i,
    output wire                 data_packet_release_o,
    output wire [LEN_W-1:0]     data_payload_read_addr_o,
    input  wire [7:0]           data_payload_read_data_i,

    output reg  [7:0]           tx_axis_tdata_o,
    output wire                 tx_axis_tvalid_o,
    input  wire                 tx_axis_tready_i,
    output wire                 tx_axis_tlast_o,
    output wire                 busy_o,
    output wire                 ctrl_active_o,
    output wire                 sent_event_o
);
    localparam [1:0] ST_IDLE=0, ST_ARP=1, ST_UDP=2;
    localparam [1:0] SRC_NONE=0, SRC_CTRL=1, SRC_DATA=2;
    localparam integer BURST_W = (CTRL_BURST_MAX < 2) ? 1 : $clog2(CTRL_BURST_MAX+1);

    function [15:0] fold_sum16;
        input [31:0] sum_i;
        reg [31:0] folded;
        begin
            folded=(sum_i&32'hffff)+(sum_i>>16);
            folded=(folded&32'hffff)+(folded>>16);
            fold_sum16=folded[15:0];
        end
    endfunction

    function [15:0] ipv4_checksum;
        input [15:0] total_len;
        input [15:0] ident;
        reg [31:0] sum;
        begin
            sum=16'h4500+total_len+ident+16'h4000+16'h4011+
                LOCAL_IPV4[31:16]+LOCAL_IPV4[15:0]+
                HOST_IPV4[31:16]+HOST_IPV4[15:0];
            ipv4_checksum=~fold_sum16(sum);
        end
    endfunction

    function [15:0] udp_checksum;
        input [31:0] payload_sum;
        input [15:0] udp_len;
        input [15:0] src_port;
        input [15:0] dst_port;
        reg [31:0] sum;
        reg [15:0] result;
        begin
            sum=payload_sum+LOCAL_IPV4[31:16]+LOCAL_IPV4[15:0]+
                HOST_IPV4[31:16]+HOST_IPV4[15:0]+16'h0011+udp_len+
                src_port+dst_port+udp_len;
            result=~fold_sum16(sum);
            udp_checksum=(result==0)?16'hffff:result;
        end
    endfunction

    reg [1:0] state, send_source;
    reg [LEN_W-1:0] output_index, send_payload_len;
    reg [15:0] send_src_port, send_dst_port;
    reg [15:0] ip_identification, send_identification;
    reg [15:0] send_ip_checksum, send_udp_checksum;
    reg arp_pending;
    reg lower_rr; // 0: ARP first, 1: DATA first
    reg [BURST_W-1:0] ctrl_burst_count;

    wire ctrl_pending = ctrl_enable_i && ctrl_packet_valid_i;
    wire data_pending = data_packet_valid_i;
    wire lower_pending = arp_pending || data_pending;
    wire ctrl_quota_available = (ctrl_burst_count < CTRL_BURST_MAX);
    wire choose_ctrl = ctrl_pending && (!lower_pending || ctrl_quota_available);
    wire choose_arp = !choose_ctrl && arp_pending &&
        (!data_pending || !lower_rr);
    wire choose_data = !choose_ctrl && data_pending &&
        (!arp_pending || lower_rr);
    wire start_ctrl = (state==ST_IDLE) && link_ready_i && choose_ctrl;
    wire start_arp  = (state==ST_IDLE) && link_ready_i && choose_arp;
    wire start_data = (state==ST_IDLE) && link_ready_i && choose_data;

    wire output_fire = tx_axis_tvalid_o && tx_axis_tready_i;
    wire [15:0] ip_total_length = send_payload_len + 16'd28;
    wire [15:0] udp_total_length = send_payload_len + 16'd8;
    wire udp_last = (state==ST_UDP) &&
                    (output_index == (send_payload_len + 16'd41));

    assign tx_axis_tvalid_o = resetn_i && link_ready_i && (state != ST_IDLE);
    assign tx_axis_tlast_o = (state==ST_ARP) ? (output_index==16'd41) : udp_last;
    assign ctrl_packet_release_o = output_fire && udp_last &&
                                   (send_source==SRC_CTRL);
    assign data_packet_release_o = output_fire && udp_last &&
                                   (send_source==SRC_DATA);
    assign sent_event_o = ctrl_packet_release_o || data_packet_release_o;
    assign ctrl_active_o = ((state==ST_UDP)&&(send_source==SRC_CTRL)) || start_ctrl;
    assign busy_o = (state!=ST_IDLE) || arp_pending;

    wire [LEN_W-1:0] payload_offset = (output_index>=42) ?
        ((output_fire && !tx_axis_tlast_o) ? output_index-41 : output_index-42) : 0;
    assign ctrl_payload_read_addr_o = payload_offset[10:0];
    assign data_payload_read_addr_o = payload_offset;

    always @* begin
        tx_axis_tdata_o=8'h00;
        if (state==ST_ARP) begin
            case(output_index)
                0:tx_axis_tdata_o=HOST_MAC[47:40]; 1:tx_axis_tdata_o=HOST_MAC[39:32];
                2:tx_axis_tdata_o=HOST_MAC[31:24]; 3:tx_axis_tdata_o=HOST_MAC[23:16];
                4:tx_axis_tdata_o=HOST_MAC[15:8];  5:tx_axis_tdata_o=HOST_MAC[7:0];
                6:tx_axis_tdata_o=LOCAL_MAC[47:40]; 7:tx_axis_tdata_o=LOCAL_MAC[39:32];
                8:tx_axis_tdata_o=LOCAL_MAC[31:24]; 9:tx_axis_tdata_o=LOCAL_MAC[23:16];
                10:tx_axis_tdata_o=LOCAL_MAC[15:8]; 11:tx_axis_tdata_o=LOCAL_MAC[7:0];
                12:tx_axis_tdata_o=8'h08; 13:tx_axis_tdata_o=8'h06;
                14:tx_axis_tdata_o=0; 15:tx_axis_tdata_o=1; 16:tx_axis_tdata_o=8'h08;
                17:tx_axis_tdata_o=0; 18:tx_axis_tdata_o=6; 19:tx_axis_tdata_o=4;
                20:tx_axis_tdata_o=0; 21:tx_axis_tdata_o=2;
                22:tx_axis_tdata_o=LOCAL_MAC[47:40]; 23:tx_axis_tdata_o=LOCAL_MAC[39:32];
                24:tx_axis_tdata_o=LOCAL_MAC[31:24]; 25:tx_axis_tdata_o=LOCAL_MAC[23:16];
                26:tx_axis_tdata_o=LOCAL_MAC[15:8]; 27:tx_axis_tdata_o=LOCAL_MAC[7:0];
                28:tx_axis_tdata_o=LOCAL_IPV4[31:24]; 29:tx_axis_tdata_o=LOCAL_IPV4[23:16];
                30:tx_axis_tdata_o=LOCAL_IPV4[15:8]; 31:tx_axis_tdata_o=LOCAL_IPV4[7:0];
                32:tx_axis_tdata_o=HOST_MAC[47:40]; 33:tx_axis_tdata_o=HOST_MAC[39:32];
                34:tx_axis_tdata_o=HOST_MAC[31:24]; 35:tx_axis_tdata_o=HOST_MAC[23:16];
                36:tx_axis_tdata_o=HOST_MAC[15:8]; 37:tx_axis_tdata_o=HOST_MAC[7:0];
                38:tx_axis_tdata_o=HOST_IPV4[31:24]; 39:tx_axis_tdata_o=HOST_IPV4[23:16];
                40:tx_axis_tdata_o=HOST_IPV4[15:8]; 41:tx_axis_tdata_o=HOST_IPV4[7:0];
                default:tx_axis_tdata_o=0;
            endcase
        end else if (state==ST_UDP) begin
            case(output_index)
                0:tx_axis_tdata_o=HOST_MAC[47:40]; 1:tx_axis_tdata_o=HOST_MAC[39:32];
                2:tx_axis_tdata_o=HOST_MAC[31:24]; 3:tx_axis_tdata_o=HOST_MAC[23:16];
                4:tx_axis_tdata_o=HOST_MAC[15:8]; 5:tx_axis_tdata_o=HOST_MAC[7:0];
                6:tx_axis_tdata_o=LOCAL_MAC[47:40]; 7:tx_axis_tdata_o=LOCAL_MAC[39:32];
                8:tx_axis_tdata_o=LOCAL_MAC[31:24]; 9:tx_axis_tdata_o=LOCAL_MAC[23:16];
                10:tx_axis_tdata_o=LOCAL_MAC[15:8]; 11:tx_axis_tdata_o=LOCAL_MAC[7:0];
                12:tx_axis_tdata_o=8'h08; 13:tx_axis_tdata_o=0; 14:tx_axis_tdata_o=8'h45;
                15:tx_axis_tdata_o=0; 16:tx_axis_tdata_o=ip_total_length[15:8];
                17:tx_axis_tdata_o=ip_total_length[7:0]; 18:tx_axis_tdata_o=send_identification[15:8];
                19:tx_axis_tdata_o=send_identification[7:0]; 20:tx_axis_tdata_o=8'h40;
                21:tx_axis_tdata_o=0; 22:tx_axis_tdata_o=8'd64; 23:tx_axis_tdata_o=8'h11;
                24:tx_axis_tdata_o=send_ip_checksum[15:8]; 25:tx_axis_tdata_o=send_ip_checksum[7:0];
                26:tx_axis_tdata_o=LOCAL_IPV4[31:24]; 27:tx_axis_tdata_o=LOCAL_IPV4[23:16];
                28:tx_axis_tdata_o=LOCAL_IPV4[15:8]; 29:tx_axis_tdata_o=LOCAL_IPV4[7:0];
                30:tx_axis_tdata_o=HOST_IPV4[31:24]; 31:tx_axis_tdata_o=HOST_IPV4[23:16];
                32:tx_axis_tdata_o=HOST_IPV4[15:8]; 33:tx_axis_tdata_o=HOST_IPV4[7:0];
                34:tx_axis_tdata_o=send_src_port[15:8]; 35:tx_axis_tdata_o=send_src_port[7:0];
                36:tx_axis_tdata_o=send_dst_port[15:8]; 37:tx_axis_tdata_o=send_dst_port[7:0];
                38:tx_axis_tdata_o=udp_total_length[15:8]; 39:tx_axis_tdata_o=udp_total_length[7:0];
                40:tx_axis_tdata_o=send_udp_checksum[15:8]; 41:tx_axis_tdata_o=send_udp_checksum[7:0];
                default: tx_axis_tdata_o=(send_source==SRC_CTRL)?
                    ctrl_payload_read_data_i:data_payload_read_data_i;
            endcase
        end
    end

    always @(posedge clk_i) begin
        if (!resetn_i) begin
            state<=ST_IDLE; send_source<=SRC_NONE; output_index<=0;
            send_payload_len<=0; send_src_port<=0; send_dst_port<=0;
            ip_identification<=0; send_identification<=0;
            send_ip_checksum<=0; send_udp_checksum<=0;
            arp_pending<=0; lower_rr<=0; ctrl_burst_count<=0;
        end else begin
            if (arp_reply_request_i) arp_pending<=1'b1;
            if (!link_ready_i) begin
                state<=ST_IDLE; send_source<=SRC_NONE; output_index<=0;
                arp_pending<=0; ctrl_burst_count<=0; lower_rr<=0;
            end else if (state==ST_IDLE) begin
                output_index<=0;
                if (!ctrl_pending && !lower_pending) ctrl_burst_count<=0;
                if (start_arp) begin
                    state<=ST_ARP; send_source<=SRC_NONE;
                    arp_pending<=arp_reply_request_i; lower_rr<=1'b1;
                    ctrl_burst_count<=0;
                end else if (start_ctrl) begin
                    state<=ST_UDP; send_source<=SRC_CTRL;
                    send_payload_len<=ctrl_packet_len_i;
                    send_src_port<=CTRL_LOCAL_PORT; send_dst_port<=CTRL_HOST_PORT;
                    send_identification<=ip_identification;
                    send_ip_checksum<=ipv4_checksum(ctrl_packet_len_i+16'd28,ip_identification);
                    send_udp_checksum<=udp_checksum(ctrl_packet_sum_i,
                        ctrl_packet_len_i+16'd8,CTRL_LOCAL_PORT,CTRL_HOST_PORT);
                    if (lower_pending) ctrl_burst_count<=ctrl_burst_count+1'b1;
                    else ctrl_burst_count<=0;
                end else if (start_data) begin
                    state<=ST_UDP; send_source<=SRC_DATA;
                    send_payload_len<=data_packet_len_i;
                    send_src_port<=DATA_LOCAL_PORT; send_dst_port<=DATA_HOST_PORT;
                    send_identification<=ip_identification;
                    send_ip_checksum<=ipv4_checksum(data_packet_len_i+16'd28,ip_identification);
                    send_udp_checksum<=(DATA_TX_UDP_CHECKSUM_ENABLE!=0)?
                        udp_checksum(data_packet_sum_i,data_packet_len_i+16'd8,
                                     DATA_LOCAL_PORT,DATA_HOST_PORT):16'h0000;
                    lower_rr<=1'b0; ctrl_burst_count<=0;
                end
            end else if (output_fire) begin
                if (tx_axis_tlast_o) begin
                    if (state==ST_UDP) ip_identification<=ip_identification+1'b1;
                    state<=ST_IDLE; send_source<=SRC_NONE; output_index<=0;
                end else output_index<=output_index+1'b1;
            end
        end
    end
endmodule
