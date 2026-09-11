`timescale 1ns / 1ps

// Development-only payload loopback for the UDP message interface.
// A received slot is held until the TX descriptor has been accepted and every
// payload byte has crossed the TX data channel.
module udp_payload_echo (
    input  wire        clk_i,
    input  wire        resetn_i,

    input  wire        rx_msg_valid_i,
    output wire        rx_msg_ready_o,
    input  wire [7:0]  rx_msg_data_i,
    input  wire        rx_msg_last_i,
    input  wire [10:0] rx_msg_len_i,

    output wire        tx_msg_valid_o,
    input  wire        tx_msg_ready_i,
    output wire [10:0] tx_msg_len_o,
    output wire        tx_msg_data_valid_o,
    input  wire        tx_msg_data_ready_i,
    output wire [7:0]  tx_msg_data_o,
    output wire        tx_msg_data_last_o
);

    localparam WAIT_DESCRIPTOR = 1'b0;
    localparam STREAM_PAYLOAD  = 1'b1;

    reg state;
    reg [10:0] message_length;

    assign tx_msg_valid_o = (state == WAIT_DESCRIPTOR) && rx_msg_valid_i;
    assign tx_msg_len_o   = (state == WAIT_DESCRIPTOR) ? rx_msg_len_i :
                                                         message_length;

    assign tx_msg_data_valid_o = (state == STREAM_PAYLOAD) && rx_msg_valid_i;
    assign tx_msg_data_o       = rx_msg_data_i;
    assign tx_msg_data_last_o  = rx_msg_last_i;
    assign rx_msg_ready_o      = (state == STREAM_PAYLOAD) &&
                                 tx_msg_data_ready_i;

    always @(posedge clk_i) begin
        if (!resetn_i) begin
            state          <= WAIT_DESCRIPTOR;
            message_length <= 11'd0;
        end else begin
            case (state)
                WAIT_DESCRIPTOR: begin
                    if (tx_msg_valid_o && tx_msg_ready_i) begin
                        message_length <= rx_msg_len_i;
                        state <= STREAM_PAYLOAD;
                    end
                end

                STREAM_PAYLOAD: begin
                    if (rx_msg_valid_i && rx_msg_ready_o && rx_msg_last_i)
                        state <= WAIT_DESCRIPTOR;
                end

                default: state <= WAIT_DESCRIPTOR;
            endcase
        end
    end

endmodule
