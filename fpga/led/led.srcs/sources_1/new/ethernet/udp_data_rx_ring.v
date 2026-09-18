`timescale 1ns / 1ps

// Variable-length committed-message FIFO for the DATA receive channel.
// A parser reserves the complete payload before its first byte, writes one
// speculative candidate, then commits or aborts it at the Ethernet frame end.
module udp_data_rx_ring #(
    parameter integer MAX_PAYLOAD   = 8972,
    parameter integer BYTE_CAPACITY = 32768,
    parameter integer DESC_COUNT    = 16,
    parameter integer LEN_W         = 14
) (
    input  wire                 clk_i,
    input  wire                 resetn_i,

    input  wire                 reserve_valid_i,
    output wire                 reserve_ready_o,
    input  wire [LEN_W-1:0]     reserve_len_i,
    input  wire                 write_valid_i,
    input  wire [LEN_W-1:0]     write_offset_i,
    input  wire [7:0]           write_data_i,
    input  wire                 commit_i,
    input  wire                 abort_i,

    output wire                 msg_valid_o,
    input  wire                 msg_ready_i,
    output wire [7:0]           msg_data_o,
    output wire                 msg_last_o,
    output wire [LEN_W-1:0]     msg_len_o,
    output wire [$clog2(DESC_COUNT+1)-1:0] level_o
);

    localparam integer ADDR_W = $clog2(BYTE_CAPACITY);
    localparam integer DESC_W = $clog2(DESC_COUNT);
    localparam integer USED_W = $clog2(BYTE_CAPACITY + 1);

    (* ram_style = "block" *) reg [7:0] payload_mem [0:BYTE_CAPACITY-1];
    reg [ADDR_W-1:0] desc_start [0:DESC_COUNT-1];
    reg [LEN_W-1:0]  desc_len   [0:DESC_COUNT-1];

    reg [ADDR_W-1:0] alloc_ptr;
    reg [USED_W-1:0] used_bytes;
    reg [DESC_W-1:0] desc_write_ptr;
    reg [DESC_W-1:0] desc_read_ptr;
    reg [$clog2(DESC_COUNT+1)-1:0] desc_used;

    reg              candidate_active;
    reg [ADDR_W-1:0] candidate_start;
    reg [LEN_W-1:0]  candidate_len;

    reg [LEN_W-1:0]  read_offset;
    reg [7:0]        read_data;

    wire message_fire = msg_valid_o && msg_ready_i;
    wire message_release = message_fire && msg_last_o;
    wire [LEN_W-1:0] released_len = desc_len[desc_read_ptr];
    wire [USED_W:0] bytes_after_release = BYTE_CAPACITY - used_bytes +
        (message_release ? released_len : {LEN_W{1'b0}});
    wire desc_free_now = (desc_used < DESC_COUNT) || message_release;
    wire reserve_len_ok = (reserve_len_i != 0) &&
                          (reserve_len_i <= MAX_PAYLOAD);
    wire reserve_fire = reserve_valid_i && reserve_ready_o;

    assign reserve_ready_o = resetn_i && !candidate_active &&
                             reserve_len_ok && desc_free_now &&
                             (bytes_after_release >= reserve_len_i);

    wire [ADDR_W-1:0] write_address = candidate_start + write_offset_i;
    wire [DESC_W-1:0] next_desc_read_ptr = desc_read_ptr + 1'b1;
    wire [LEN_W-1:0] next_read_offset = message_release ? {LEN_W{1'b0}} :
                                       (read_offset + 1'b1);
    wire [ADDR_W-1:0] active_read_start = (desc_used != 0) ?
        desc_start[desc_read_ptr] : candidate_start;
    wire [ADDR_W-1:0] next_read_start = message_release ?
        desc_start[next_desc_read_ptr] : active_read_start;
    wire [ADDR_W-1:0] read_address =
        (message_fire ? next_read_start : active_read_start) +
        (message_fire ? next_read_offset : read_offset);

    assign msg_valid_o = (desc_used != 0);
    assign msg_data_o = read_data;
    assign msg_len_o = desc_len[desc_read_ptr];
    assign msg_last_o = msg_valid_o &&
                        (read_offset == (desc_len[desc_read_ptr] - 1'b1));
    assign level_o = desc_used;

    always @(posedge clk_i) begin
        if (write_valid_i && candidate_active &&
            (write_offset_i < candidate_len))
            payload_mem[write_address] <= write_data_i;
        read_data <= payload_mem[read_address];
    end

    always @(posedge clk_i) begin
        if (!resetn_i) begin
            alloc_ptr        <= {ADDR_W{1'b0}};
            used_bytes       <= {USED_W{1'b0}};
            desc_write_ptr   <= {DESC_W{1'b0}};
            desc_read_ptr    <= {DESC_W{1'b0}};
            desc_used        <= 0;
            candidate_active <= 1'b0;
            candidate_start  <= {ADDR_W{1'b0}};
            candidate_len    <= {LEN_W{1'b0}};
            read_offset      <= {LEN_W{1'b0}};
        end else begin
            if (reserve_fire) begin
                candidate_active <= 1'b1;
                candidate_start  <= alloc_ptr;
                candidate_len    <= reserve_len_i;
                alloc_ptr        <= alloc_ptr + reserve_len_i;
            end

            if (commit_i && candidate_active) begin
                desc_start[desc_write_ptr] <= candidate_start;
                desc_len[desc_write_ptr]   <= candidate_len;
                desc_write_ptr             <= desc_write_ptr + 1'b1;
                candidate_active           <= 1'b0;
            end else if (abort_i && candidate_active) begin
                alloc_ptr        <= candidate_start;
                candidate_active <= 1'b0;
            end

            if (message_fire) begin
                if (message_release) begin
                    desc_read_ptr <= next_desc_read_ptr;
                    read_offset   <= {LEN_W{1'b0}};
                end else begin
                    read_offset <= next_read_offset;
                end
            end

            case ({reserve_fire, (abort_i && candidate_active), message_release})
                3'b100: used_bytes <= used_bytes + reserve_len_i;
                3'b010: used_bytes <= used_bytes - candidate_len;
                3'b001: used_bytes <= used_bytes - released_len;
                3'b101: used_bytes <= used_bytes + reserve_len_i - released_len;
                3'b011: used_bytes <= used_bytes - candidate_len - released_len;
                default: used_bytes <= used_bytes;
            endcase

            case ({(commit_i && candidate_active), message_release})
                2'b10: desc_used <= desc_used + 1'b1;
                2'b01: desc_used <= desc_used - 1'b1;
                default: desc_used <= desc_used;
            endcase
        end
    end

endmodule
