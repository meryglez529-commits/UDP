`timescale 1ns / 1ps

// DB500 CONTROL V1 composition.  The wrapper only connects six single-owner
// blocks; it does not store protocol state of its own.
module db500_udp_control (
    input  wire        clk_i,
    input  wire        resetn_i,

    input  wire        rx_msg_valid_i,
    output wire        rx_msg_ready_o,
    input  wire [7:0]  rx_msg_data_i,
    input  wire        rx_msg_last_i,
    input  wire [10:0] rx_msg_len_i,

    output wire        tx_msg_valid_o,
    input  wire        tx_msg_ready_i,
    output wire [10:0] tx_msg_len_o,
    output wire        tx_msg_data_valid_o,
    input  wire        tx_msg_data_ready_i,
    output wire [7:0]  tx_msg_data_o,
    output wire        tx_msg_data_last_o,
    input  wire        tx_msg_error_i,

    output wire        reg_req_valid_o,
    input  wire        reg_req_ready_i,
    output wire        reg_req_write_o,
    output wire [15:0] reg_req_addr_o,
    output wire [31:0] reg_req_wdata_o,
    input  wire        reg_rsp_valid_i,
    output wire        reg_rsp_ready_o,
    input  wire        reg_rsp_error_i,
    input  wire [31:0] reg_rsp_rdata_i,

    output wire        watchdog_activity_o,
    output wire        fault_hold_o,
    output wire [63:0] oldest_id_o,
    output wire [63:0] execute_id_o,
    output wire [31:0] rx_seen_o,
    output wire [31:0] rx_format_drop_o,
    output wire [31:0] rx_window_drop_o,
    output wire [31:0] rx_duplicate_o,
    output wire [31:0] rx_id_conflict_o,
    output wire [31:0] query_executed_o,
    output wire [31:0] set_executed_o,
    output wire [31:0] reg_error_o,
    output wire [31:0] rsp_loaded_o,
    output wire [31:0] tx_input_error_o,
    output wire [1:0]  last_fault_kind_o
);

    wire        req_valid;
    wire        req_ready;
    wire        req_is_set;
    wire [63:0] req_id;
    wire [15:0] req_addr;
    wire [31:0] req_data;

    wire        exec_valid;
    wire        exec_ready;
    wire        exec_is_set;
    wire [15:0] exec_addr;
    wire [31:0] exec_wdata;
    wire        result_valid;
    wire        result_ready;
    wire        result_error;
    wire [31:0] result_rdata;

    wire [3:0]   slot_pending;
    wire [3:0]   slot_is_set;
    wire [3:0]   slot_error;
    wire [255:0] slot_id;
    wire [63:0]  slot_addr;
    wire [127:0] slot_data;

    wire        load_ready;
    wire        load_fire;
    wire        load_is_set;
    wire        load_error;
    wire [63:0] load_id;
    wire [15:0] load_addr;
    wire [31:0] load_data;
    wire        take_valid;
    wire [1:0]  take_slot;
    wire [63:0] take_request_id;

    wire rx_seen_event;
    wire format_drop_event;
    wire window_drop_event;
    wire duplicate_event;
    wire id_conflict_event;
    wire query_executed_event;
    wire set_executed_event;
    wire reg_error_event;
    wire tx_fault_event;

    // The watchdog deliberately observes line activity rather than only
    // successful execution.  Recovery is requested by the host stopping all
    // CONTROL traffic for the documented quiet interval.
    assign watchdog_activity_o = rx_seen_event || load_fire;

    db500_ctrl_rx_decoder rx_decoder_i (
        .clk_i               (clk_i),
        .resetn_i            (resetn_i),
        .rx_msg_valid_i      (rx_msg_valid_i),
        .rx_msg_ready_o      (rx_msg_ready_o),
        .rx_msg_data_i       (rx_msg_data_i),
        .rx_msg_last_i       (rx_msg_last_i),
        .rx_msg_len_i        (rx_msg_len_i),
        .req_valid_o         (req_valid),
        .req_ready_i         (req_ready),
        .req_is_set_o        (req_is_set),
        .req_id_o            (req_id),
        .req_addr_o          (req_addr),
        .req_data_o          (req_data),
        .rx_seen_event_o     (rx_seen_event),
        .format_drop_event_o (format_drop_event)
    );

    db500_ctrl_window window_i (
        .clk_i                    (clk_i),
        .resetn_i                 (resetn_i),
        .req_valid_i              (req_valid),
        .req_ready_o              (req_ready),
        .req_is_set_i             (req_is_set),
        .req_id_i                 (req_id),
        .req_addr_i               (req_addr),
        .req_data_i               (req_data),
        .exec_valid_o             (exec_valid),
        .exec_ready_i             (exec_ready),
        .exec_is_set_o            (exec_is_set),
        .exec_addr_o              (exec_addr),
        .exec_wdata_o             (exec_wdata),
        .result_valid_i           (result_valid),
        .result_ready_o           (result_ready),
        .result_error_i           (result_error),
        .result_rdata_i           (result_rdata),
        .slot_pending_o           (slot_pending),
        .slot_is_set_o            (slot_is_set),
        .slot_error_o             (slot_error),
        .slot_id_o                (slot_id),
        .slot_addr_o              (slot_addr),
        .slot_data_o              (slot_data),
        .take_valid_i             (take_valid),
        .take_slot_i              (take_slot),
        .take_request_id_i        (take_request_id),
        .tx_fault_event_i         (tx_fault_event),
        .window_drop_event_o      (window_drop_event),
        .duplicate_event_o        (duplicate_event),
        .id_conflict_event_o      (id_conflict_event),
        .query_executed_event_o   (query_executed_event),
        .set_executed_event_o     (set_executed_event),
        .reg_error_event_o        (reg_error_event),
        .fault_hold_o             (fault_hold_o),
        .oldest_id_o              (oldest_id_o),
        .execute_id_o             (execute_id_o)
    );

    db500_ctrl_reg_executor reg_executor_i (
        .clk_i             (clk_i),
        .resetn_i          (resetn_i),
        .exec_valid_i      (exec_valid),
        .exec_ready_o      (exec_ready),
        .exec_is_set_i     (exec_is_set),
        .exec_addr_i       (exec_addr),
        .exec_wdata_i      (exec_wdata),
        .result_valid_o    (result_valid),
        .result_ready_i    (result_ready),
        .result_error_o    (result_error),
        .result_rdata_o    (result_rdata),
        .reg_req_valid_o   (reg_req_valid_o),
        .reg_req_ready_i   (reg_req_ready_i),
        .reg_req_write_o   (reg_req_write_o),
        .reg_req_addr_o    (reg_req_addr_o),
        .reg_req_wdata_o   (reg_req_wdata_o),
        .reg_rsp_valid_i   (reg_rsp_valid_i),
        .reg_rsp_ready_o   (reg_rsp_ready_o),
        .reg_rsp_error_i   (reg_rsp_error_i),
        .reg_rsp_rdata_i   (reg_rsp_rdata_i)
    );

    db500_ctrl_rsp_select rsp_select_i (
        .clk_i             (clk_i),
        .resetn_i          (resetn_i),
        .slot_pending_i    (slot_pending),
        .slot_is_set_i     (slot_is_set),
        .slot_error_i      (slot_error),
        .slot_id_i         (slot_id),
        .slot_addr_i       (slot_addr),
        .slot_data_i       (slot_data),
        .load_ready_i      (load_ready),
        .load_fire_o       (load_fire),
        .load_is_set_o     (load_is_set),
        .load_error_o      (load_error),
        .load_id_o         (load_id),
        .load_addr_o       (load_addr),
        .load_data_o       (load_data),
        .take_valid_o      (take_valid),
        .take_slot_o       (take_slot),
        .take_request_id_o (take_request_id)
    );

    db500_ctrl_tx_encoder tx_encoder_i (
        .clk_i                   (clk_i),
        .resetn_i                (resetn_i),
        .load_ready_o            (load_ready),
        .load_fire_i             (load_fire),
        .load_is_set_i           (load_is_set),
        .load_error_i            (load_error),
        .load_id_i               (load_id),
        .load_addr_i             (load_addr),
        .load_data_i             (load_data),
        .tx_msg_valid_o          (tx_msg_valid_o),
        .tx_msg_ready_i          (tx_msg_ready_i),
        .tx_msg_len_o            (tx_msg_len_o),
        .tx_msg_data_valid_o     (tx_msg_data_valid_o),
        .tx_msg_data_ready_i     (tx_msg_data_ready_i),
        .tx_msg_data_o           (tx_msg_data_o),
        .tx_msg_data_last_o      (tx_msg_data_last_o),
        .tx_msg_error_i          (tx_msg_error_i),
        .tx_fault_event_o        (tx_fault_event)
    );

    db500_ctrl_stats stats_i (
        .clk_i                    (clk_i),
        .resetn_i                 (resetn_i),
        .rx_seen_event_i          (rx_seen_event),
        .format_drop_event_i      (format_drop_event),
        .window_drop_event_i      (window_drop_event),
        .duplicate_event_i        (duplicate_event),
        .id_conflict_event_i      (id_conflict_event),
        .query_executed_event_i   (query_executed_event),
        .set_executed_event_i     (set_executed_event),
        .reg_error_event_i        (reg_error_event),
        .rsp_loaded_event_i       (load_fire),
        .tx_fault_event_i         (tx_fault_event),
        .rx_seen_o                (rx_seen_o),
        .rx_format_drop_o         (rx_format_drop_o),
        .rx_window_drop_o         (rx_window_drop_o),
        .rx_duplicate_o           (rx_duplicate_o),
        .rx_id_conflict_o         (rx_id_conflict_o),
        .query_executed_o         (query_executed_o),
        .set_executed_o           (set_executed_o),
        .reg_error_o              (reg_error_o),
        .rsp_loaded_o             (rsp_loaded_o),
        .tx_input_error_o         (tx_input_error_o),
        .last_fault_kind_o        (last_fault_kind_o)
    );

endmodule
