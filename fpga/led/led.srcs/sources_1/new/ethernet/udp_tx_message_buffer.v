`timescale 1ns / 1ps

// Single-message TX staging buffer.  A descriptor is published to the frame
// engine only after exactly the declared number of payload bytes is received.
module udp_tx_message_buffer #(
    parameter integer MAX_UDP_PAYLOAD = 1472
) (
    input  wire        clk_i,
    input  wire        resetn_i,
    input  wire        link_ready_i,

    input  wire        msg_valid_i,
    output wire        msg_ready_o,
    input  wire [10:0] msg_len_i,
    input  wire        msg_data_valid_i,
    output wire        msg_data_ready_o,
    input  wire [7:0]  msg_data_i,
    input  wire        msg_data_last_i,
    output reg         msg_error_o,

    output wire        packet_valid_o,
    output reg  [10:0] packet_len_o,
    output reg  [31:0] packet_payload_sum_o,
    input  wire        packet_release_i,
    input  wire [10:0] payload_read_addr_i,
    output wire [7:0]  payload_read_data_o,

    output wire        busy_o,
    output reg         accept_event_o,
    output wire        error_event_o
);

    localparam [1:0] TX_IDLE     = 2'd0;
    localparam [1:0] TX_COLLECT  = 2'd1;
    localparam [1:0] TX_FINALIZE = 2'd2;
    localparam [1:0] TX_READY    = 2'd3;

    reg [1:0]  state;
    reg [10:0] payload_count;
    reg [31:0] payload_sum;
    reg [7:0]  payload_word_hi;
    reg [7:0]  payload_mem [0:MAX_UDP_PAYLOAD-1];

    assign msg_ready_o = resetn_i && link_ready_i && (state == TX_IDLE);
    assign msg_data_ready_o = resetn_i && link_ready_i &&
                              (state == TX_COLLECT);
    assign packet_valid_o = (state == TX_READY);
    assign payload_read_data_o = payload_mem[payload_read_addr_i];
    assign busy_o = (state != TX_IDLE);
    assign error_event_o = msg_error_o;

    always @(posedge clk_i) begin
        if (!resetn_i) begin
            state                <= TX_IDLE;
            payload_count        <= 11'd0;
            payload_sum          <= 32'd0;
            payload_word_hi      <= 8'd0;
            packet_len_o         <= 11'd0;
            packet_payload_sum_o <= 32'd0;
            msg_error_o          <= 1'b0;
            accept_event_o       <= 1'b0;
        end else begin
            msg_error_o    <= 1'b0;
            accept_event_o <= 1'b0;

            if (!link_ready_i) begin
                state <= TX_IDLE;
            end else begin
                if (msg_valid_i && msg_ready_o) begin
                    if ((msg_len_i == 0) || (msg_len_i > MAX_UDP_PAYLOAD)) begin
                        msg_error_o <= 1'b1;
                    end else begin
                        packet_len_o    <= msg_len_i;
                        payload_count   <= 11'd0;
                        payload_sum     <= 32'd0;
                        payload_word_hi <= 8'd0;
                        state           <= TX_COLLECT;
                        accept_event_o  <= 1'b1;
                    end
                end

                if (msg_data_valid_i && msg_data_ready_o) begin
                    payload_mem[payload_count] <= msg_data_i;

                    if (!payload_count[0])
                        payload_word_hi <= msg_data_i;
                    else
                        payload_sum <= payload_sum +
                                       {payload_word_hi, msg_data_i};

                    if (msg_data_last_i !=
                        (payload_count == (packet_len_o - 1'b1))) begin
                        state       <= TX_IDLE;
                        msg_error_o <= 1'b1;
                    end else if (msg_data_last_i) begin
                        payload_count <= payload_count + 1'b1;
                        state <= TX_FINALIZE;
                    end else begin
                        payload_count <= payload_count + 1'b1;
                    end
                end

                if (state == TX_FINALIZE) begin
                    packet_payload_sum_o <= payload_sum +
                        ((packet_len_o[0]) ?
                         {payload_word_hi, 8'h00} : 16'h0000);
                    state <= TX_READY;
                end

                if ((state == TX_READY) && packet_release_i)
                    state <= TX_IDLE;
            end
        end
    end

endmodule
