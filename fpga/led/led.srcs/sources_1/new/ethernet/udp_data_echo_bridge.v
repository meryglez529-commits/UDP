`timescale 1ns / 1ps

// Board-test consumer for the transparent DATA port.  A received datagram is
// retained by the RX ring until a matching TX reservation is available, then
// streamed byte-for-byte into the TX ring.
module udp_data_echo_bridge #(
    parameter integer LEN_W = 14
) (
    input  wire             clk_i,
    input  wire             resetn_i,

    input  wire             rx_valid_i,
    output wire             rx_ready_o,
    input  wire [7:0]       rx_data_i,
    input  wire             rx_last_i,
    input  wire [LEN_W-1:0] rx_len_i,

    output wire             tx_req_valid_o,
    input  wire             tx_req_ready_i,
    output wire [LEN_W-1:0] tx_len_o,
    output wire             tx_valid_o,
    input  wire             tx_ready_i,
    output wire [7:0]       tx_data_o,
    output wire             tx_last_o,
    output wire             tx_cancel_valid_o,
    input  wire             tx_status_valid_i,
    output wire             tx_status_ready_o,
    input  wire [2:0]       tx_status_i,
    output reg  [31:0]      echoed_packets_o,
    output reg  [31:0]      tx_errors_o
);
    localparam [1:0] ST_REQUEST=2'd0, ST_STREAM=2'd1, ST_STATUS=2'd2;
    reg [1:0] state;
    reg [LEN_W-1:0] held_len;

    assign tx_req_valid_o = (state == ST_REQUEST) && rx_valid_i;
    assign tx_len_o = (state == ST_REQUEST) ? rx_len_i : held_len;
    assign rx_ready_o = (state == ST_STREAM) && tx_ready_i;
    assign tx_valid_o = (state == ST_STREAM) && rx_valid_i;
    assign tx_data_o = rx_data_i;
    assign tx_last_o = rx_last_i;
    assign tx_cancel_valid_o = 1'b0;
    assign tx_status_ready_o = (state == ST_STATUS);

    always @(posedge clk_i) begin
        if (!resetn_i) begin
            state <= ST_REQUEST;
            held_len <= {LEN_W{1'b0}};
            echoed_packets_o <= 32'd0;
            tx_errors_o <= 32'd0;
        end else begin
            case (state)
                ST_REQUEST: begin
                    if (rx_valid_i && tx_req_ready_i) begin
                        held_len <= rx_len_i;
                        state <= ST_STREAM;
                    end
                end
                ST_STREAM: begin
                    if (rx_valid_i && tx_ready_i && rx_last_i)
                        state <= ST_STATUS;
                end
                ST_STATUS: begin
                    if (tx_status_valid_i) begin
                        if (tx_status_i == 3'd0)
                            echoed_packets_o <= echoed_packets_o + 1'b1;
                        else
                            tx_errors_o <= tx_errors_o + 1'b1;
                        state <= ST_REQUEST;
                    end
                end
                default: state <= ST_REQUEST;
            endcase
        end
    end
endmodule
