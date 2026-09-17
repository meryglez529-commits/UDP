`timescale 1ns / 1ps

// Decode one complete UDP payload into one normalized CONTROL request.
// The module owns byte collection and format validation only.  It drains a
// malformed message through last so the UDP RX ring can always release it.
module db500_ctrl_rx_decoder (
    input  wire        clk_i,
    input  wire        resetn_i,

    input  wire        rx_msg_valid_i,
    output wire        rx_msg_ready_o,
    input  wire [7:0]  rx_msg_data_i,
    input  wire        rx_msg_last_i,
    input  wire [10:0] rx_msg_len_i,

    output wire        req_valid_o,
    input  wire        req_ready_i,
    output wire        req_is_set_o,
    output wire [63:0] req_id_o,
    output wire [15:0] req_addr_o,
    output wire [31:0] req_data_o,

    output reg         rx_seen_event_o,
    output reg         format_drop_event_o
);

    localparam [2:0] RX_FIRST   = 3'd0;
    localparam [2:0] RX_COLLECT = 3'd1;
    localparam [2:0] RX_DRAIN   = 3'd2;
    localparam [2:0] RX_CHECK   = 3'd3;
    localparam [2:0] RX_DELIVER = 3'd4;

    reg [2:0]   state;
    reg [3:0]   byte_index;
    reg [127:0] record;

    wire rx_fire = rx_msg_valid_i && rx_msg_ready_o;
    wire record_is_query = (record[127:120] == 8'h01);
    wire record_is_set   = (record[127:120] == 8'h02);
    wire record_valid = (record_is_query || record_is_set) &&
                        (record[119:112] == 8'h00) &&
                        (record[111:48] != 64'd0) &&
                        (record_is_set || (record[31:0] == 32'd0));

    assign rx_msg_ready_o = resetn_i &&
                            ((state == RX_FIRST) ||
                             (state == RX_COLLECT) ||
                             (state == RX_DRAIN));
    assign req_valid_o  = resetn_i && (state == RX_DELIVER);
    assign req_is_set_o = record_is_set;
    assign req_id_o     = record[111:48];
    assign req_addr_o   = record[47:32];
    assign req_data_o   = record[31:0];

    always @(posedge clk_i) begin
        if (!resetn_i) begin
            state               <= RX_FIRST;
            byte_index          <= 4'd0;
            record              <= 128'd0;
            rx_seen_event_o     <= 1'b0;
            format_drop_event_o <= 1'b0;
        end else begin
            rx_seen_event_o     <= 1'b0;
            format_drop_event_o <= 1'b0;

            case (state)
                RX_FIRST: begin
                    byte_index <= 4'd0;
                    if (rx_fire) begin
                        if (rx_msg_last_i)
                            rx_seen_event_o <= 1'b1;

                        if ((rx_msg_len_i == 11'd16) && !rx_msg_last_i) begin
                            record[127:120] <= rx_msg_data_i;
                            byte_index      <= 4'd1;
                            state           <= RX_COLLECT;
                        end else if (rx_msg_last_i) begin
                            format_drop_event_o <= 1'b1;
                        end else begin
                            state <= RX_DRAIN;
                        end
                    end
                end

                RX_COLLECT: begin
                    if (rx_fire) begin
                        record[127-(byte_index*8) -: 8] <= rx_msg_data_i;
                        if (rx_msg_last_i) begin
                            rx_seen_event_o <= 1'b1;
                            if (byte_index == 4'd15)
                                state <= RX_CHECK;
                            else begin
                                format_drop_event_o <= 1'b1;
                                state <= RX_FIRST;
                            end
                        end else if (byte_index == 4'd15) begin
                            state <= RX_DRAIN;
                        end else begin
                            byte_index <= byte_index + 1'b1;
                        end
                    end
                end

                RX_DRAIN: begin
                    if (rx_fire && rx_msg_last_i) begin
                        rx_seen_event_o     <= 1'b1;
                        format_drop_event_o <= 1'b1;
                        state               <= RX_FIRST;
                    end
                end

                RX_CHECK: begin
                    if (record_valid)
                        state <= RX_DELIVER;
                    else begin
                        format_drop_event_o <= 1'b1;
                        state <= RX_FIRST;
                    end
                end

                RX_DELIVER: begin
                    if (req_valid_o && req_ready_i)
                        state <= RX_FIRST;
                end

                default: state <= RX_FIRST;
            endcase
        end
    end

endmodule
