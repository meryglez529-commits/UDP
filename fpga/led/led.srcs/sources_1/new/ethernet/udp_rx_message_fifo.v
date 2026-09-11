`timescale 1ns / 1ps

// Four-slot committed-message store for validated UDP payloads.
// A parser may write the current candidate slot before validation, but only a
// commit advances the write pointer and makes that payload visible.
module udp_rx_message_fifo #(
    parameter integer MAX_UDP_PAYLOAD = 1472
) (
    input  wire        clk_i,
    input  wire        resetn_i,

    output wire        slot_available_o,
    input  wire        payload_write_valid_i,
    input  wire [10:0] payload_write_offset_i,
    input  wire [7:0]  payload_write_data_i,
    input  wire        commit_i,
    input  wire [10:0] commit_length_i,

    output wire        msg_valid_o,
    input  wire        msg_ready_i,
    output wire [7:0]  msg_data_o,
    output wire        msg_last_o,
    output wire [10:0] msg_len_o,
    output wire [2:0]  level_o
);

    reg [7:0]  payload_mem [0:(4*MAX_UDP_PAYLOAD)-1];
    reg [10:0] slot_length [0:3];
    reg [1:0]  slot_write_ptr;
    reg [1:0]  slot_read_ptr;
    reg [2:0]  slot_count;
    reg [10:0] read_offset;

    wire message_fire = msg_valid_o && msg_ready_i;
    wire message_release = message_fire && msg_last_o;

    assign msg_valid_o = (slot_count != 0);
    assign msg_len_o   = slot_length[slot_read_ptr];
    assign msg_last_o  = msg_valid_o &&
                         (read_offset == (slot_length[slot_read_ptr] - 1'b1));
    assign msg_data_o  = payload_mem[(slot_read_ptr * MAX_UDP_PAYLOAD) +
                                     read_offset];
    assign level_o = slot_count;

    // Reuse a slot on the same cycle that the application releases it.
    assign slot_available_o = (slot_count < 3'd4) || message_release;

    integer write_address;
    always @(posedge clk_i) begin
        if (!resetn_i) begin
            slot_write_ptr <= 2'd0;
            slot_read_ptr  <= 2'd0;
            slot_count     <= 3'd0;
            read_offset    <= 11'd0;
        end else begin
            if (payload_write_valid_i) begin
                write_address = (slot_write_ptr * MAX_UDP_PAYLOAD) +
                                payload_write_offset_i;
                payload_mem[write_address] <= payload_write_data_i;
            end

            if (message_fire) begin
                if (msg_last_o) begin
                    read_offset   <= 11'd0;
                    slot_read_ptr <= slot_read_ptr + 1'b1;
                end else begin
                    read_offset <= read_offset + 1'b1;
                end
            end

            if (commit_i) begin
                slot_length[slot_write_ptr] <= commit_length_i;
                slot_write_ptr <= slot_write_ptr + 1'b1;
            end

            case ({commit_i, message_release})
                2'b10: slot_count <= slot_count + 1'b1;
                2'b01: slot_count <= slot_count - 1'b1;
                default: slot_count <= slot_count;
            endcase
        end
    end

endmodule
