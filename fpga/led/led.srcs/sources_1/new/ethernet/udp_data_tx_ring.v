`timescale 1ns / 1ps

// Variable-length DATA transmit FIFO.  Success means that the complete local
// payload has been committed; storage is released later when the frame engine
// copies the last payload byte into the Ethernet client FIFO.
module udp_data_tx_ring #(
    parameter integer MAX_PAYLOAD   = 8972,
    parameter integer BYTE_CAPACITY = 32768,
    parameter integer DESC_COUNT    = 16,
    parameter integer LEN_W         = 14
) (
    input  wire                 clk_i,
    input  wire                 resetn_i,
    input  wire                 link_ready_i,

    input  wire                 req_valid_i,
    output wire                 req_ready_o,
    input  wire [LEN_W-1:0]     req_len_i,
    input  wire                 data_valid_i,
    output wire                 data_ready_o,
    input  wire [7:0]           data_i,
    input  wire                 data_last_i,
    input  wire                 cancel_valid_i,
    output wire                 cancel_ready_o,
    output wire                 status_valid_o,
    input  wire                 status_ready_i,
    output wire [2:0]           status_o,

    output wire                 packet_valid_o,
    output wire [LEN_W-1:0]     packet_len_o,
    output wire [31:0]          packet_payload_sum_o,
    input  wire                 packet_release_i,
    input  wire [LEN_W-1:0]     payload_read_addr_i,
    output reg  [7:0]           payload_read_data_o,
    output wire                 busy_o
);

    localparam [2:0] STATUS_COMMITTED  = 3'd0;
    localparam [2:0] STATUS_BAD_LENGTH = 3'd1;
    localparam [2:0] STATUS_BAD_LAST   = 3'd2;
    localparam [2:0] STATUS_CANCELLED  = 3'd3;
    localparam [1:0] ST_IDLE    = 2'd0;
    localparam [1:0] ST_COLLECT = 2'd1;
    localparam [1:0] ST_DRAIN   = 2'd2;

    localparam integer ADDR_W = $clog2(BYTE_CAPACITY);
    localparam integer DESC_W = $clog2(DESC_COUNT);
    localparam integer USED_W = $clog2(BYTE_CAPACITY + 1);

    (* ram_style = "block" *) reg [7:0] payload_mem [0:BYTE_CAPACITY-1];
    reg [ADDR_W-1:0] desc_start [0:DESC_COUNT-1];
    reg [LEN_W-1:0]  desc_len [0:DESC_COUNT-1];
    reg [31:0]       desc_sum [0:DESC_COUNT-1];

    reg [ADDR_W-1:0] alloc_ptr;
    reg [USED_W-1:0] used_bytes;
    reg [DESC_W-1:0] desc_write_ptr;
    reg [DESC_W-1:0] desc_read_ptr;
    reg [$clog2(DESC_COUNT+1)-1:0] desc_used;

    reg [1:0] state;
    reg [ADDR_W-1:0] candidate_start;
    reg [LEN_W-1:0] declared_len;
    reg [LEN_W-1:0] byte_count;
    reg [31:0] payload_sum;
    reg [7:0] payload_word_hi;
    reg status_pending;
    reg [2:0] status_value;

    wire packet_release = packet_release_i && packet_valid_o;
    wire [LEN_W-1:0] released_len = desc_len[desc_read_ptr];
    wire [USED_W:0] bytes_after_release = BYTE_CAPACITY - used_bytes +
        (packet_release ? released_len : {LEN_W{1'b0}});
    wire desc_free_now = (desc_used < DESC_COUNT) || packet_release;
    wire req_len_ok = (req_len_i != 0) && (req_len_i <= MAX_PAYLOAD);
    wire req_fire = req_valid_i && req_ready_o;
    wire data_fire = data_valid_i && data_ready_o;
    wire cancel_fire = cancel_valid_i && cancel_ready_o;
    wire expected_last = (byte_count == (declared_len - 1'b1));
    wire commit_fire = data_fire && expected_last && data_last_i;
    wire protocol_error = data_fire && (data_last_i != expected_last);
    wire [31:0] sum_after_byte = byte_count[0] ?
        payload_sum + {payload_word_hi, data_i} : payload_sum;
    wire [31:0] final_sum = sum_after_byte +
        ((declared_len[0]) ? {data_i, 8'h00} : 16'h0000);
    wire [ADDR_W-1:0] write_address = candidate_start + byte_count;
    wire [ADDR_W-1:0] read_address =
        ((desc_used != 0) ? desc_start[desc_read_ptr] : candidate_start) +
        payload_read_addr_i;

    assign req_ready_o = resetn_i && link_ready_i && (state == ST_IDLE) &&
                         !status_pending &&
                         (!req_len_ok || (desc_free_now &&
                          (bytes_after_release >= req_len_i)));
    assign data_ready_o = resetn_i && link_ready_i &&
                          ((state == ST_COLLECT) || (state == ST_DRAIN)) &&
                          !cancel_valid_i;
    assign cancel_ready_o = resetn_i && link_ready_i &&
                            ((state == ST_COLLECT) || (state == ST_DRAIN));
    assign status_valid_o = status_pending;
    assign status_o = status_value;
    assign packet_valid_o = (desc_used != 0);
    assign packet_len_o = desc_len[desc_read_ptr];
    assign packet_payload_sum_o = desc_sum[desc_read_ptr];
    assign busy_o = (state != ST_IDLE) || status_pending || packet_valid_o;

    always @(posedge clk_i) begin
        if (data_fire && (state == ST_COLLECT) && !protocol_error)
            payload_mem[write_address] <= data_i;
        payload_read_data_o <= payload_mem[read_address];
    end

    always @(posedge clk_i) begin
        if (!resetn_i) begin
            alloc_ptr       <= 0;
            used_bytes      <= 0;
            desc_write_ptr  <= 0;
            desc_read_ptr   <= 0;
            desc_used       <= 0;
            state           <= ST_IDLE;
            candidate_start <= 0;
            declared_len    <= 0;
            byte_count      <= 0;
            payload_sum     <= 0;
            payload_word_hi <= 0;
            status_pending  <= 1'b0;
            status_value    <= STATUS_COMMITTED;
        end else if (!link_ready_i) begin
            alloc_ptr       <= 0;
            used_bytes      <= 0;
            desc_write_ptr  <= 0;
            desc_read_ptr   <= 0;
            desc_used       <= 0;
            state           <= ST_IDLE;
            byte_count      <= 0;
            payload_sum     <= 0;
            status_pending  <= 1'b0;
        end else begin
            if (status_pending && status_ready_i)
                status_pending <= 1'b0;

            if (req_fire) begin
                if (!req_len_ok) begin
                    status_pending <= 1'b1;
                    status_value   <= STATUS_BAD_LENGTH;
                end else begin
                    candidate_start <= alloc_ptr;
                    alloc_ptr       <= alloc_ptr + req_len_i;
                    declared_len    <= req_len_i;
                    byte_count      <= 0;
                    payload_sum     <= 0;
                    payload_word_hi <= 0;
                    state           <= ST_COLLECT;
                end
            end

            if (cancel_fire) begin
                if (state == ST_COLLECT) begin
                    alloc_ptr      <= candidate_start;
                    status_pending <= 1'b1;
                    status_value   <= STATUS_CANCELLED;
                end
                state      <= ST_IDLE;
                byte_count <= 0;
            end else if (data_fire) begin
                if (state == ST_DRAIN) begin
                    if (data_last_i)
                        state <= ST_IDLE;
                end else if (protocol_error) begin
                    alloc_ptr      <= candidate_start;
                    status_pending <= 1'b1;
                    status_value   <= STATUS_BAD_LAST;
                    byte_count     <= 0;
                    state          <= data_last_i ? ST_IDLE : ST_DRAIN;
                end else if (commit_fire) begin
                    desc_start[desc_write_ptr] <= candidate_start;
                    desc_len[desc_write_ptr]   <= declared_len;
                    desc_sum[desc_write_ptr]   <= final_sum;
                    desc_write_ptr             <= desc_write_ptr + 1'b1;
                    status_pending             <= 1'b1;
                    status_value               <= STATUS_COMMITTED;
                    byte_count                 <= 0;
                    state                      <= ST_IDLE;
                end else begin
                    if (!byte_count[0])
                        payload_word_hi <= data_i;
                    else
                        payload_sum <= sum_after_byte;
                    byte_count <= byte_count + 1'b1;
                end
            end

            if (packet_release)
                desc_read_ptr <= desc_read_ptr + 1'b1;

            case ({(req_fire && req_len_ok),
                   (cancel_fire && (state == ST_COLLECT)) || protocol_error,
                   packet_release})
                3'b100: used_bytes <= used_bytes + req_len_i;
                3'b010: used_bytes <= used_bytes - declared_len;
                3'b001: used_bytes <= used_bytes - released_len;
                3'b101: used_bytes <= used_bytes + req_len_i - released_len;
                3'b011: used_bytes <= used_bytes - declared_len - released_len;
                default: used_bytes <= used_bytes;
            endcase

            case ({commit_fire, packet_release})
                2'b10: desc_used <= desc_used + 1'b1;
                2'b01: desc_used <= desc_used - 1'b1;
                default: desc_used <= desc_used;
            endcase
        end
    end

endmodule
