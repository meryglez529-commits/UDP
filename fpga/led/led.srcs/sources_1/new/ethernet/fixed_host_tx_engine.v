`timescale 1ns / 1ps

// Serializes fixed-host ARP replies and complete UDP messages onto the TEMAC
// client stream.  ARP requests are retained while a UDP frame is in flight.
module fixed_host_tx_engine #(
    parameter [47:0] LOCAL_MAC       = 48'h02_DB_50_00_00_01,
    parameter [31:0] LOCAL_IPV4      = 32'hC0A8_0114,
    parameter [47:0] HOST_MAC        = 48'h9C69_D31A_4C6D,
    parameter [31:0] HOST_IPV4       = 32'hC0A8_010A,
    parameter [15:0] LOCAL_UDP_PORT  = 16'd32000,
    parameter [15:0] HOST_UDP_PORT   = 16'd32000
) (
    input  wire        clk_i,
    input  wire        resetn_i,
    input  wire        link_ready_i,

    input  wire        arp_reply_request_i,
    input  wire        packet_valid_i,
    input  wire [10:0] packet_len_i,
    input  wire [31:0] packet_payload_sum_i,
    output wire        packet_release_o,
    output wire [10:0] payload_read_addr_o,
    input  wire [7:0]  payload_read_data_i,

    output reg  [7:0]  tx_axis_tdata_o,
    output wire        tx_axis_tvalid_o,
    input  wire        tx_axis_tready_i,
    output wire        tx_axis_tlast_o,

    output wire        busy_o,
    output wire        sent_event_o
);

    localparam [1:0] TX_IDLE = 2'd0;
    localparam [1:0] TX_ARP  = 2'd1;
    localparam [1:0] TX_UDP  = 2'd2;

    function [15:0] fold_sum16;
        input [31:0] sum_i;
        reg [31:0] folded;
        begin
            folded = (sum_i & 32'h0000_FFFF) + (sum_i >> 16);
            folded = (folded & 32'h0000_FFFF) + (folded >> 16);
            fold_sum16 = folded[15:0];
        end
    endfunction

    function [15:0] ipv4_tx_checksum;
        input [15:0] total_length_i;
        input [15:0] identification_i;
        reg [31:0] sum;
        begin
            sum = 32'd0;
            sum = sum + 16'h4500;
            sum = sum + total_length_i;
            sum = sum + identification_i;
            sum = sum + 16'h4000;
            sum = sum + 16'h4011;
            sum = sum + LOCAL_IPV4[31:16] + LOCAL_IPV4[15:0];
            sum = sum + HOST_IPV4[31:16] + HOST_IPV4[15:0];
            ipv4_tx_checksum = ~fold_sum16(sum);
        end
    endfunction

    function [15:0] udp_tx_checksum;
        input [31:0] payload_sum_i;
        input [15:0] udp_length_i;
        reg [31:0] sum;
        reg [15:0] result;
        begin
            sum = payload_sum_i;
            sum = sum + LOCAL_IPV4[31:16] + LOCAL_IPV4[15:0];
            sum = sum + HOST_IPV4[31:16] + HOST_IPV4[15:0];
            sum = sum + 16'h0011 + udp_length_i;
            sum = sum + LOCAL_UDP_PORT + HOST_UDP_PORT + udp_length_i;
            result = ~fold_sum16(sum);
            udp_tx_checksum = (result == 16'h0000) ? 16'hFFFF : result;
        end
    endfunction

    reg [1:0]  state;
    reg [10:0] output_index;
    reg        arp_reply_pending;
    reg [15:0] ip_identification;
    reg [15:0] send_ip_identification;
    reg [15:0] send_ip_checksum;
    reg [15:0] send_udp_checksum;
    reg [10:0] send_payload_length;

    wire output_fire = tx_axis_tvalid_o && tx_axis_tready_i;
    wire [15:0] ip_total_length = send_payload_length + 16'd28;
    wire [15:0] udp_total_length = send_payload_length + 16'd8;

    assign tx_axis_tvalid_o = resetn_i && link_ready_i && (state != TX_IDLE);
    assign tx_axis_tlast_o = (state == TX_ARP) ?
                             (output_index == 11'd41) :
                             ((state == TX_UDP) &&
                              (output_index == (send_payload_length + 11'd41)));
    assign payload_read_addr_o = ((state == TX_UDP) &&
                                  (output_index >= 11'd42)) ?
                                  (output_index - 11'd42) : 11'd0;
    assign packet_release_o = output_fire && tx_axis_tlast_o &&
                              (state == TX_UDP);
    assign sent_event_o = packet_release_o;
    assign busy_o = (state != TX_IDLE) || arp_reply_pending;

    always @* begin
        tx_axis_tdata_o = 8'h00;
        if (state == TX_ARP) begin
            case (output_index)
                11'd0:  tx_axis_tdata_o = HOST_MAC[47:40];
                11'd1:  tx_axis_tdata_o = HOST_MAC[39:32];
                11'd2:  tx_axis_tdata_o = HOST_MAC[31:24];
                11'd3:  tx_axis_tdata_o = HOST_MAC[23:16];
                11'd4:  tx_axis_tdata_o = HOST_MAC[15:8];
                11'd5:  tx_axis_tdata_o = HOST_MAC[7:0];
                11'd6:  tx_axis_tdata_o = LOCAL_MAC[47:40];
                11'd7:  tx_axis_tdata_o = LOCAL_MAC[39:32];
                11'd8:  tx_axis_tdata_o = LOCAL_MAC[31:24];
                11'd9:  tx_axis_tdata_o = LOCAL_MAC[23:16];
                11'd10: tx_axis_tdata_o = LOCAL_MAC[15:8];
                11'd11: tx_axis_tdata_o = LOCAL_MAC[7:0];
                11'd12: tx_axis_tdata_o = 8'h08;
                11'd13: tx_axis_tdata_o = 8'h06;
                11'd14: tx_axis_tdata_o = 8'h00;
                11'd15: tx_axis_tdata_o = 8'h01;
                11'd16: tx_axis_tdata_o = 8'h08;
                11'd17: tx_axis_tdata_o = 8'h00;
                11'd18: tx_axis_tdata_o = 8'h06;
                11'd19: tx_axis_tdata_o = 8'h04;
                11'd20: tx_axis_tdata_o = 8'h00;
                11'd21: tx_axis_tdata_o = 8'h02;
                11'd22: tx_axis_tdata_o = LOCAL_MAC[47:40];
                11'd23: tx_axis_tdata_o = LOCAL_MAC[39:32];
                11'd24: tx_axis_tdata_o = LOCAL_MAC[31:24];
                11'd25: tx_axis_tdata_o = LOCAL_MAC[23:16];
                11'd26: tx_axis_tdata_o = LOCAL_MAC[15:8];
                11'd27: tx_axis_tdata_o = LOCAL_MAC[7:0];
                11'd28: tx_axis_tdata_o = LOCAL_IPV4[31:24];
                11'd29: tx_axis_tdata_o = LOCAL_IPV4[23:16];
                11'd30: tx_axis_tdata_o = LOCAL_IPV4[15:8];
                11'd31: tx_axis_tdata_o = LOCAL_IPV4[7:0];
                11'd32: tx_axis_tdata_o = HOST_MAC[47:40];
                11'd33: tx_axis_tdata_o = HOST_MAC[39:32];
                11'd34: tx_axis_tdata_o = HOST_MAC[31:24];
                11'd35: tx_axis_tdata_o = HOST_MAC[23:16];
                11'd36: tx_axis_tdata_o = HOST_MAC[15:8];
                11'd37: tx_axis_tdata_o = HOST_MAC[7:0];
                11'd38: tx_axis_tdata_o = HOST_IPV4[31:24];
                11'd39: tx_axis_tdata_o = HOST_IPV4[23:16];
                11'd40: tx_axis_tdata_o = HOST_IPV4[15:8];
                11'd41: tx_axis_tdata_o = HOST_IPV4[7:0];
                default: tx_axis_tdata_o = 8'h00;
            endcase
        end else if (state == TX_UDP) begin
            case (output_index)
                11'd0:  tx_axis_tdata_o = HOST_MAC[47:40];
                11'd1:  tx_axis_tdata_o = HOST_MAC[39:32];
                11'd2:  tx_axis_tdata_o = HOST_MAC[31:24];
                11'd3:  tx_axis_tdata_o = HOST_MAC[23:16];
                11'd4:  tx_axis_tdata_o = HOST_MAC[15:8];
                11'd5:  tx_axis_tdata_o = HOST_MAC[7:0];
                11'd6:  tx_axis_tdata_o = LOCAL_MAC[47:40];
                11'd7:  tx_axis_tdata_o = LOCAL_MAC[39:32];
                11'd8:  tx_axis_tdata_o = LOCAL_MAC[31:24];
                11'd9:  tx_axis_tdata_o = LOCAL_MAC[23:16];
                11'd10: tx_axis_tdata_o = LOCAL_MAC[15:8];
                11'd11: tx_axis_tdata_o = LOCAL_MAC[7:0];
                11'd12: tx_axis_tdata_o = 8'h08;
                11'd13: tx_axis_tdata_o = 8'h00;
                11'd14: tx_axis_tdata_o = 8'h45;
                11'd15: tx_axis_tdata_o = 8'h00;
                11'd16: tx_axis_tdata_o = ip_total_length[15:8];
                11'd17: tx_axis_tdata_o = ip_total_length[7:0];
                11'd18: tx_axis_tdata_o = send_ip_identification[15:8];
                11'd19: tx_axis_tdata_o = send_ip_identification[7:0];
                11'd20: tx_axis_tdata_o = 8'h40;
                11'd21: tx_axis_tdata_o = 8'h00;
                11'd22: tx_axis_tdata_o = 8'd64;
                11'd23: tx_axis_tdata_o = 8'h11;
                11'd24: tx_axis_tdata_o = send_ip_checksum[15:8];
                11'd25: tx_axis_tdata_o = send_ip_checksum[7:0];
                11'd26: tx_axis_tdata_o = LOCAL_IPV4[31:24];
                11'd27: tx_axis_tdata_o = LOCAL_IPV4[23:16];
                11'd28: tx_axis_tdata_o = LOCAL_IPV4[15:8];
                11'd29: tx_axis_tdata_o = LOCAL_IPV4[7:0];
                11'd30: tx_axis_tdata_o = HOST_IPV4[31:24];
                11'd31: tx_axis_tdata_o = HOST_IPV4[23:16];
                11'd32: tx_axis_tdata_o = HOST_IPV4[15:8];
                11'd33: tx_axis_tdata_o = HOST_IPV4[7:0];
                11'd34: tx_axis_tdata_o = LOCAL_UDP_PORT[15:8];
                11'd35: tx_axis_tdata_o = LOCAL_UDP_PORT[7:0];
                11'd36: tx_axis_tdata_o = HOST_UDP_PORT[15:8];
                11'd37: tx_axis_tdata_o = HOST_UDP_PORT[7:0];
                11'd38: tx_axis_tdata_o = udp_total_length[15:8];
                11'd39: tx_axis_tdata_o = udp_total_length[7:0];
                11'd40: tx_axis_tdata_o = send_udp_checksum[15:8];
                11'd41: tx_axis_tdata_o = send_udp_checksum[7:0];
                default: tx_axis_tdata_o = payload_read_data_i;
            endcase
        end
    end

    always @(posedge clk_i) begin
        if (!resetn_i) begin
            state                  <= TX_IDLE;
            output_index           <= 11'd0;
            arp_reply_pending      <= 1'b0;
            ip_identification      <= 16'd0;
            send_ip_identification <= 16'd0;
            send_ip_checksum       <= 16'd0;
            send_udp_checksum      <= 16'd0;
            send_payload_length    <= 11'd0;
        end else begin
            if (arp_reply_request_i)
                arp_reply_pending <= 1'b1;

            if (!link_ready_i) begin
                state             <= TX_IDLE;
                output_index      <= 11'd0;
                arp_reply_pending <= 1'b0;
            end else if (state == TX_IDLE) begin
                output_index <= 11'd0;
                if (arp_reply_pending) begin
                    state <= TX_ARP;
                    // Keep a new request that arrives as the pending one starts.
                    arp_reply_pending <= arp_reply_request_i;
                end else if (packet_valid_i) begin
                    send_payload_length    <= packet_len_i;
                    send_ip_identification <= ip_identification;
                    send_ip_checksum <= ipv4_tx_checksum(
                        packet_len_i + 16'd28, ip_identification);
                    send_udp_checksum <= udp_tx_checksum(
                        packet_payload_sum_i, packet_len_i + 16'd8);
                    state <= TX_UDP;
                end
            end else if (output_fire) begin
                if (tx_axis_tlast_o) begin
                    if (state == TX_UDP)
                        ip_identification <= ip_identification + 1'b1;
                    state        <= TX_IDLE;
                    output_index <= 11'd0;
                end else begin
                    output_index <= output_index + 1'b1;
                end
            end
        end
    end

endmodule
