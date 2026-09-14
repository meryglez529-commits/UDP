`timescale 1ns / 1ps

// Committed-message ring for validated UDP payloads.
//
// The parser writes the current candidate slot speculatively.  Only commit_i
// advances the write pointer and makes the slot visible to the application.
// A frame rejected by the parser therefore needs no explicit erase: the next
// candidate simply overwrites the same uncommitted slot.
//
// The payload array has one synchronous read port and one synchronous write
// port so Vivado can implement it as Block RAM.  The read-address look-ahead
// presents one byte per clock while keeping data stable under backpressure.
module udp_rx_payload_ring #(
    parameter integer MAX_UDP_PAYLOAD = 1472,
    parameter integer SLOT_COUNT      = 4
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

    localparam integer SLOT_WIDTH = $clog2(SLOT_COUNT);
    localparam integer TOTAL_BYTES = SLOT_COUNT * MAX_UDP_PAYLOAD;
    localparam integer ADDR_WIDTH = $clog2(TOTAL_BYTES);

    (* ram_style = "block" *)
    reg [7:0] payload_mem [0:TOTAL_BYTES-1];
    reg [10:0] slot_length [0:SLOT_COUNT-1];

    reg [SLOT_WIDTH-1:0] write_slot;
    reg [SLOT_WIDTH-1:0] read_slot;
    reg [SLOT_WIDTH:0]   committed_count;
    reg [10:0]           read_offset;
    reg [7:0]            read_data;

    wire message_fire = msg_valid_o && msg_ready_i;
    wire message_release = message_fire && msg_last_o;
    wire [SLOT_WIDTH-1:0] next_read_slot = read_slot + 1'b1;
    wire [10:0] next_read_offset = message_release ? 11'd0 :
                                   (read_offset + 1'b1);

    wire [ADDR_WIDTH-1:0] write_address =
        (write_slot * MAX_UDP_PAYLOAD) + payload_write_offset_i;

    // On an accepted byte, issue the address of the following byte before the
    // clock edge.  The synchronous RAM result then becomes the next AXI-style
    // output byte immediately after that edge.  A stalled output reissues the
    // current address, so data cannot change while ready is low.
    wire [ADDR_WIDTH-1:0] current_read_address =
        (read_slot * MAX_UDP_PAYLOAD) + read_offset;
    wire [ADDR_WIDTH-1:0] advanced_read_address =
        (message_release ? (next_read_slot * MAX_UDP_PAYLOAD) :
                           (read_slot * MAX_UDP_PAYLOAD)) +
        next_read_offset;
    wire [ADDR_WIDTH-1:0] selected_read_address =
        message_fire ? advanced_read_address : current_read_address;

    assign msg_valid_o = (committed_count != 0);
    assign msg_data_o  = read_data;
    assign msg_len_o   = slot_length[read_slot];
    assign msg_last_o  = msg_valid_o &&
                         (read_offset == (slot_length[read_slot] - 1'b1));
    assign level_o = committed_count[2:0];

    // A frame can reserve a slot on the same cycle that the application
    // releases one.  Its payload does not arrive until after the UDP header,
    // so the just-released RAM location is safe before the first write.
    assign slot_available_o = (committed_count < SLOT_COUNT) ||
                              message_release;

    always @(posedge clk_i) begin
        if (payload_write_valid_i)
            payload_mem[write_address] <= payload_write_data_i;

        // No reset is applied to the BRAM output register; msg_valid_o masks
        // it until a committed descriptor exists.
        read_data <= payload_mem[selected_read_address];
    end

    always @(posedge clk_i) begin
        if (!resetn_i) begin
            write_slot      <= {SLOT_WIDTH{1'b0}};
            read_slot       <= {SLOT_WIDTH{1'b0}};
            committed_count <= {(SLOT_WIDTH+1){1'b0}};
            read_offset     <= 11'd0;
        end else begin
            if (message_fire) begin
                if (message_release) begin
                    read_offset <= 11'd0;
                    read_slot   <= next_read_slot;
                end else begin
                    read_offset <= next_read_offset;
                end
            end

            if (commit_i) begin
                slot_length[write_slot] <= commit_length_i;
                write_slot <= write_slot + 1'b1;
            end

            case ({commit_i, message_release})
                2'b10: committed_count <= committed_count + 1'b1;
                2'b01: committed_count <= committed_count - 1'b1;
                default: committed_count <= committed_count;
            endcase
        end
    end

endmodule
