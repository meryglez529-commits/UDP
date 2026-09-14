`timescale 1ns / 1ps

// Multi-message TX payload ring.
//
// The application owns the write slot from descriptor acceptance until the
// declared final byte is accepted.  A valid message is then committed for the
// frame engine.  Independent read and write slots allow the application to
// fill the next datagram while the current one is being encapsulated.
module udp_tx_payload_ring #(
    parameter integer MAX_UDP_PAYLOAD = 1472,
    parameter integer SLOT_COUNT      = 2
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
    output wire [10:0] packet_len_o,
    output wire [31:0] packet_payload_sum_o,
    input  wire        packet_release_i,
    input  wire [10:0] payload_read_addr_i,
    output reg  [7:0]  payload_read_data_o,

    output wire        busy_o,
    output reg         accept_event_o,
    output wire        error_event_o
);

    localparam integer SLOT_WIDTH = $clog2(SLOT_COUNT);
    localparam integer TOTAL_BYTES = SLOT_COUNT * MAX_UDP_PAYLOAD;
    localparam integer ADDR_WIDTH = $clog2(TOTAL_BYTES);

    localparam WRITE_IDLE    = 1'b0;
    localparam WRITE_COLLECT = 1'b1;

    (* ram_style = "block" *)
    reg [7:0] payload_mem [0:TOTAL_BYTES-1];
    reg [10:0] slot_length [0:SLOT_COUNT-1];
    reg [31:0] slot_payload_sum [0:SLOT_COUNT-1];

    reg write_state;
    reg [SLOT_WIDTH-1:0] write_slot;
    reg [SLOT_WIDTH-1:0] read_slot;
    reg [SLOT_WIDTH:0]   committed_count;
    reg [10:0]           declared_length;
    reg [10:0]           payload_count;
    reg [31:0]           payload_sum;
    reg [7:0]            payload_word_hi;

    wire packet_release = packet_release_i && packet_valid_o;
    wire slot_free_now = (committed_count < SLOT_COUNT) || packet_release;
    wire descriptor_fire = msg_valid_i && msg_ready_o;
    wire payload_fire = msg_data_valid_i && msg_data_ready_o;
    wire expected_last = (payload_count == (declared_length - 1'b1));
    wire payload_protocol_ok = (msg_data_last_i == expected_last);
    wire write_commit = payload_fire && payload_protocol_ok &&
                        msg_data_last_i;

    wire [31:0] payload_sum_after_byte = payload_count[0] ?
        (payload_sum + {payload_word_hi, msg_data_i}) : payload_sum;
    wire [31:0] final_payload_sum = payload_sum_after_byte +
        ((declared_length[0]) ? {msg_data_i, 8'h00} : 16'h0000);

    wire [ADDR_WIDTH-1:0] write_address =
        (write_slot * MAX_UDP_PAYLOAD) + payload_count;
    wire [ADDR_WIDTH-1:0] read_address =
        (read_slot * MAX_UDP_PAYLOAD) + payload_read_addr_i;

    assign msg_ready_o = resetn_i && link_ready_i &&
                         (write_state == WRITE_IDLE) && slot_free_now;
    assign msg_data_ready_o = resetn_i && link_ready_i &&
                              (write_state == WRITE_COLLECT);

    assign packet_valid_o = (committed_count != 0);
    assign packet_len_o = slot_length[read_slot];
    assign packet_payload_sum_o = slot_payload_sum[read_slot];
    assign busy_o = (write_state != WRITE_IDLE) || packet_valid_o;
    assign error_event_o = msg_error_o;

    always @(posedge clk_i) begin
        if (payload_fire)
            payload_mem[write_address] <= msg_data_i;

        // The frame engine supplies a look-ahead address.  Registering the
        // result here provides the synchronous Block RAM read required by the
        // ring design.
        payload_read_data_o <= payload_mem[read_address];
    end

    always @(posedge clk_i) begin
        if (!resetn_i) begin
            write_state      <= WRITE_IDLE;
            write_slot       <= {SLOT_WIDTH{1'b0}};
            read_slot        <= {SLOT_WIDTH{1'b0}};
            committed_count  <= {(SLOT_WIDTH+1){1'b0}};
            declared_length  <= 11'd0;
            payload_count    <= 11'd0;
            payload_sum      <= 32'd0;
            payload_word_hi  <= 8'd0;
            msg_error_o      <= 1'b0;
            accept_event_o   <= 1'b0;
        end else begin
            msg_error_o    <= 1'b0;
            accept_event_o <= 1'b0;

            if (!link_ready_i) begin
                write_state     <= WRITE_IDLE;
                write_slot      <= {SLOT_WIDTH{1'b0}};
                read_slot       <= {SLOT_WIDTH{1'b0}};
                committed_count <= {(SLOT_WIDTH+1){1'b0}};
                payload_count   <= 11'd0;
                payload_sum     <= 32'd0;
            end else begin
                if (descriptor_fire) begin
                    if ((msg_len_i == 0) ||
                        (msg_len_i > MAX_UDP_PAYLOAD)) begin
                        msg_error_o <= 1'b1;
                    end else begin
                        declared_length <= msg_len_i;
                        payload_count   <= 11'd0;
                        payload_sum     <= 32'd0;
                        payload_word_hi <= 8'd0;
                        write_state     <= WRITE_COLLECT;
                        accept_event_o  <= 1'b1;
                    end
                end

                if (payload_fire) begin
                    if (!payload_count[0])
                        payload_word_hi <= msg_data_i;
                    else
                        payload_sum <= payload_sum_after_byte;

                    if (!payload_protocol_ok) begin
                        write_state    <= WRITE_IDLE;
                        payload_count  <= 11'd0;
                        msg_error_o    <= 1'b1;
                    end else if (msg_data_last_i) begin
                        slot_length[write_slot] <= declared_length;
                        slot_payload_sum[write_slot] <= final_payload_sum;
                        write_slot    <= write_slot + 1'b1;
                        write_state   <= WRITE_IDLE;
                        payload_count <= 11'd0;
                    end else begin
                        payload_count <= payload_count + 1'b1;
                    end
                end

                if (packet_release)
                    read_slot <= read_slot + 1'b1;

                case ({write_commit, packet_release})
                    2'b10: committed_count <= committed_count + 1'b1;
                    2'b01: committed_count <= committed_count - 1'b1;
                    default: committed_count <= committed_count;
                endcase
            end
        end
    end

endmodule
