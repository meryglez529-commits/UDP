`timescale 1ns / 1ps

// Saturating transport counters.  Functional blocks report one-cycle events;
// statistics never feed back into the packet datapath.
module udp_transport_stats (
    input  wire        clk_i,
    input  wire        resetn_i,

    input  wire        rx_frame_event_i,
    input  wire        rx_accept_event_i,
    input  wire        rx_drop_event_i,
    input  wire [3:0]  rx_drop_reason_i,
    input  wire        tx_accept_event_i,
    input  wire        tx_sent_event_i,
    input  wire        tx_error_event_i,

    output reg  [3:0]  last_drop_reason_o,
    output reg  [31:0] rx_frames_seen_o,
    output reg  [31:0] rx_udp_accepted_o,
    output reg  [31:0] rx_drop_endpoint_o,
    output reg  [31:0] rx_drop_ipv4_o,
    output reg  [31:0] rx_drop_udp_o,
    output reg  [31:0] rx_drop_checksum_o,
    output reg  [31:0] rx_drop_oversize_o,
    output reg  [31:0] rx_drop_fifo_full_o,
    output reg  [31:0] tx_accepted_o,
    output reg  [31:0] tx_sent_o,
    output reg  [31:0] tx_input_error_o
);

    localparam [3:0] DROP_NONE     = 4'd0;
    localparam [3:0] DROP_ENDPOINT = 4'd1;
    localparam [3:0] DROP_IPV4     = 4'd2;
    localparam [3:0] DROP_UDP      = 4'd3;
    localparam [3:0] DROP_CHECKSUM = 4'd4;
    localparam [3:0] DROP_OVERSIZE = 4'd5;
    localparam [3:0] DROP_FIFO     = 4'd6;

    function [31:0] sat_inc32;
        input [31:0] value_i;
        begin
            sat_inc32 = (&value_i) ? value_i : value_i + 1'b1;
        end
    endfunction

    always @(posedge clk_i) begin
        if (!resetn_i) begin
            last_drop_reason_o  <= DROP_NONE;
            rx_frames_seen_o    <= 32'd0;
            rx_udp_accepted_o   <= 32'd0;
            rx_drop_endpoint_o  <= 32'd0;
            rx_drop_ipv4_o      <= 32'd0;
            rx_drop_udp_o       <= 32'd0;
            rx_drop_checksum_o  <= 32'd0;
            rx_drop_oversize_o  <= 32'd0;
            rx_drop_fifo_full_o <= 32'd0;
            tx_accepted_o       <= 32'd0;
            tx_sent_o           <= 32'd0;
            tx_input_error_o    <= 32'd0;
        end else begin
            if (rx_frame_event_i)
                rx_frames_seen_o <= sat_inc32(rx_frames_seen_o);

            if (rx_accept_event_i) begin
                rx_udp_accepted_o  <= sat_inc32(rx_udp_accepted_o);
                last_drop_reason_o <= DROP_NONE;
            end

            if (rx_drop_event_i) begin
                last_drop_reason_o <= rx_drop_reason_i;
                case (rx_drop_reason_i)
                    DROP_ENDPOINT:
                        rx_drop_endpoint_o <= sat_inc32(rx_drop_endpoint_o);
                    DROP_IPV4:
                        rx_drop_ipv4_o <= sat_inc32(rx_drop_ipv4_o);
                    DROP_UDP:
                        rx_drop_udp_o <= sat_inc32(rx_drop_udp_o);
                    DROP_CHECKSUM:
                        rx_drop_checksum_o <= sat_inc32(rx_drop_checksum_o);
                    DROP_OVERSIZE:
                        rx_drop_oversize_o <= sat_inc32(rx_drop_oversize_o);
                    DROP_FIFO:
                        rx_drop_fifo_full_o <= sat_inc32(rx_drop_fifo_full_o);
                    default: ;
                endcase
            end

            if (tx_accept_event_i)
                tx_accepted_o <= sat_inc32(tx_accepted_o);
            if (tx_sent_event_i)
                tx_sent_o <= sat_inc32(tx_sent_o);
            if (tx_error_event_i)
                tx_input_error_o <= sat_inc32(tx_input_error_o);
        end
    end

endmodule
