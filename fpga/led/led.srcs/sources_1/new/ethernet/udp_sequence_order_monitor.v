`timescale 1ns / 1ps

// Passive UPF1 sequence monitor used only by the hardware diagnostic top.
// PAYLOAD_BASE is 0 on the UDP message stream and 42 on the untagged
// Ethernet/IPv4/UDP frame stream.  The monitor never drives the observed
// ready/valid interface.
module udp_sequence_order_monitor #(
    parameter integer PAYLOAD_BASE = 0
) (
    input  wire        clk_i,
    input  wire        resetn_i,
    input  wire [7:0]  stream_data_i,
    input  wire        stream_valid_i,
    input  wire        stream_ready_i,
    input  wire        stream_last_i,

    output reg         reorder_pulse_o,
    output reg  [31:0] reorder_count_o,
    output reg  [31:0] packet_count_o,
    output reg  [31:0] current_sequence_o,
    output reg  [31:0] previous_highest_o,
    output reg  [31:0] current_run_id_o
);

    localparam integer MAGIC_0_OFFSET = PAYLOAD_BASE + 0;
    localparam integer MAGIC_1_OFFSET = PAYLOAD_BASE + 1;
    localparam integer MAGIC_2_OFFSET = PAYLOAD_BASE + 2;
    localparam integer MAGIC_3_OFFSET = PAYLOAD_BASE + 3;
    localparam integer RUN_0_OFFSET   = PAYLOAD_BASE + 4;
    localparam integer RUN_1_OFFSET   = PAYLOAD_BASE + 5;
    localparam integer RUN_2_OFFSET   = PAYLOAD_BASE + 6;
    localparam integer RUN_3_OFFSET   = PAYLOAD_BASE + 7;
    localparam integer SEQ_0_OFFSET   = PAYLOAD_BASE + 8;
    localparam integer SEQ_1_OFFSET   = PAYLOAD_BASE + 9;
    localparam integer SEQ_2_OFFSET   = PAYLOAD_BASE + 10;
    localparam integer SEQ_3_OFFSET   = PAYLOAD_BASE + 11;

    reg [11:0] byte_index;
    reg        magic_match;
    reg [31:0] captured_run_id;
    reg [31:0] captured_sequence;
    reg        have_highest;
    reg [31:0] highest_run_id;
    reg [31:0] highest_sequence;

    wire stream_transfer = stream_valid_i && stream_ready_i;
    always @(posedge clk_i) begin
        if (!resetn_i) begin
            byte_index            <= 12'd0;
            magic_match           <= 1'b1;
            captured_run_id       <= 32'd0;
            captured_sequence     <= 32'd0;
            have_highest          <= 1'b0;
            highest_run_id        <= 32'd0;
            highest_sequence      <= 32'd0;
            reorder_pulse_o       <= 1'b0;
            reorder_count_o       <= 32'd0;
            packet_count_o        <= 32'd0;
            current_sequence_o    <= 32'd0;
            previous_highest_o    <= 32'd0;
            current_run_id_o      <= 32'd0;
        end else begin
            reorder_pulse_o <= 1'b0;

            if (stream_transfer) begin
                case (byte_index)
                    MAGIC_0_OFFSET: if (stream_data_i != 8'h55) magic_match <= 1'b0; // U
                    MAGIC_1_OFFSET: if (stream_data_i != 8'h50) magic_match <= 1'b0; // P
                    MAGIC_2_OFFSET: if (stream_data_i != 8'h46) magic_match <= 1'b0; // F
                    MAGIC_3_OFFSET: if (stream_data_i != 8'h31) magic_match <= 1'b0; // 1
                    RUN_0_OFFSET: captured_run_id[31:24] <= stream_data_i;
                    RUN_1_OFFSET: captured_run_id[23:16] <= stream_data_i;
                    RUN_2_OFFSET: captured_run_id[15:8]  <= stream_data_i;
                    RUN_3_OFFSET: captured_run_id[7:0]   <= stream_data_i;
                    SEQ_0_OFFSET: captured_sequence[31:24] <= stream_data_i;
                    SEQ_1_OFFSET: captured_sequence[23:16] <= stream_data_i;
                    SEQ_2_OFFSET: captured_sequence[15:8]  <= stream_data_i;
                    SEQ_3_OFFSET: captured_sequence[7:0]   <= stream_data_i;
                    default: begin end
                endcase

                // All supported packets extend beyond the UPF1 header, so by
                // TLAST the captured fields and magic decision are stable.
                if (stream_last_i) begin
                    if (magic_match) begin
                        packet_count_o     <= packet_count_o + 1'b1;
                        current_sequence_o <= captured_sequence;
                        current_run_id_o   <= captured_run_id;

                        if (!have_highest || (captured_run_id != highest_run_id)) begin
                            have_highest     <= 1'b1;
                            highest_run_id   <= captured_run_id;
                            highest_sequence <= captured_sequence;
                            previous_highest_o <= captured_sequence;
                        end else begin
                            previous_highest_o <= highest_sequence;
                            // Signed modular comparison remains correct across
                            // a 32-bit wrap for realistic test windows (<2^31).
                            if ($signed(captured_sequence - highest_sequence) > 0) begin
                                highest_sequence <= captured_sequence;
                            end else begin
                                reorder_pulse_o <= 1'b1;
                                reorder_count_o <= reorder_count_o + 1'b1;
                            end
                        end
                    end

                    byte_index        <= 12'd0;
                    magic_match       <= 1'b1;
                    captured_run_id   <= 32'd0;
                    captured_sequence <= 32'd0;
                end else begin
                    byte_index <= byte_index + 1'b1;
                end
            end
        end
    end

endmodule
