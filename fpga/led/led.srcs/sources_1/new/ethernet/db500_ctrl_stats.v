`timescale 1ns / 1ps

// Diagnostic-only saturating counters.  These outputs never feed protocol
// control and may be mapped into product status registers by an outer layer.
module db500_ctrl_stats (
    input  wire        clk_i,
    input  wire        resetn_i,
    input  wire        rx_seen_event_i,
    input  wire        format_drop_event_i,
    input  wire        window_drop_event_i,
    input  wire        duplicate_event_i,
    input  wire        id_conflict_event_i,
    input  wire        query_executed_event_i,
    input  wire        set_executed_event_i,
    input  wire        reg_error_event_i,
    input  wire        rsp_loaded_event_i,
    input  wire        tx_fault_event_i,

    output reg  [31:0] rx_seen_o,
    output reg  [31:0] rx_format_drop_o,
    output reg  [31:0] rx_window_drop_o,
    output reg  [31:0] rx_duplicate_o,
    output reg  [31:0] rx_id_conflict_o,
    output reg  [31:0] query_executed_o,
    output reg  [31:0] set_executed_o,
    output reg  [31:0] reg_error_o,
    output reg  [31:0] rsp_loaded_o,
    output reg  [31:0] tx_input_error_o,
    output reg  [1:0]  last_fault_kind_o
);

    function [31:0] sat_inc32;
        input [31:0] value_i;
        begin
            sat_inc32 = (&value_i) ? value_i : value_i + 1'b1;
        end
    endfunction

    always @(posedge clk_i) begin
        if (!resetn_i) begin
            rx_seen_o        <= 32'd0;
            rx_format_drop_o <= 32'd0;
            rx_window_drop_o <= 32'd0;
            rx_duplicate_o   <= 32'd0;
            rx_id_conflict_o <= 32'd0;
            query_executed_o <= 32'd0;
            set_executed_o   <= 32'd0;
            reg_error_o      <= 32'd0;
            rsp_loaded_o     <= 32'd0;
            tx_input_error_o <= 32'd0;
            last_fault_kind_o <= 2'd0;
        end else begin
            if (rx_seen_event_i)
                rx_seen_o <= sat_inc32(rx_seen_o);
            if (format_drop_event_i)
                rx_format_drop_o <= sat_inc32(rx_format_drop_o);
            if (window_drop_event_i)
                rx_window_drop_o <= sat_inc32(rx_window_drop_o);
            if (duplicate_event_i)
                rx_duplicate_o <= sat_inc32(rx_duplicate_o);
            if (id_conflict_event_i)
                rx_id_conflict_o <= sat_inc32(rx_id_conflict_o);
            if (query_executed_event_i)
                query_executed_o <= sat_inc32(query_executed_o);
            if (set_executed_event_i)
                set_executed_o <= sat_inc32(set_executed_o);
            if (reg_error_event_i)
                reg_error_o <= sat_inc32(reg_error_o);
            if (rsp_loaded_event_i)
                rsp_loaded_o <= sat_inc32(rsp_loaded_o);
            if (tx_fault_event_i)
                tx_input_error_o <= sat_inc32(tx_input_error_o);

            if (reg_error_event_i)
                last_fault_kind_o <= 2'd1;
            if (id_conflict_event_i)
                last_fault_kind_o <= 2'd2;
            if (tx_fault_event_i)
                last_fault_kind_o <= 2'd3;
        end
    end

endmodule
