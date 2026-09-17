`timescale 1ns / 1ps

// Four-slot ordered delivery window for CONTROL requests.
// This module is the sole writer of A, E, slot tags, saved results, replay
// pending bits and fault_hold.  Full 64-bit tags protect ring-slot reuse.
module db500_ctrl_window (
    input  wire         clk_i,
    input  wire         resetn_i,

    input  wire         req_valid_i,
    output wire         req_ready_o,
    input  wire         req_is_set_i,
    input  wire [63:0]  req_id_i,
    input  wire [15:0]  req_addr_i,
    input  wire [31:0]  req_data_i,

    output wire         exec_valid_o,
    input  wire         exec_ready_i,
    output wire         exec_is_set_o,
    output wire [15:0]  exec_addr_o,
    output wire [31:0]  exec_wdata_o,

    input  wire         result_valid_i,
    output wire         result_ready_o,
    input  wire         result_error_i,
    input  wire [31:0]  result_rdata_i,

    output wire [3:0]   slot_pending_o,
    output wire [3:0]   slot_is_set_o,
    output wire [3:0]   slot_error_o,
    output wire [255:0] slot_id_o,
    output wire [63:0]  slot_addr_o,
    output wire [127:0] slot_data_o,

    input  wire         take_valid_i,
    input  wire [1:0]   take_slot_i,
    input  wire [63:0]  take_request_id_i,
    input  wire         tx_fault_event_i,

    output reg          window_drop_event_o,
    output reg          duplicate_event_o,
    output reg          id_conflict_event_o,
    output reg          query_executed_event_o,
    output reg          set_executed_event_o,
    output reg          reg_error_event_o,

    output reg          fault_hold_o,
    output wire [63:0]  oldest_id_o,
    output wire [63:0]  execute_id_o
);

    localparam [2:0] SLOT_EMPTY   = 3'd0;
    localparam [2:0] SLOT_QUEUED  = 3'd1;
    localparam [2:0] SLOT_OFFERED = 3'd2;
    localparam [2:0] SLOT_RUNNING = 3'd3;
    localparam [2:0] SLOT_DONE    = 3'd4;

    reg [63:0] oldest_id;
    reg [63:0] execute_id;
    reg [63:0] slot_id [0:3];
    reg        slot_is_set [0:3];
    reg [15:0] slot_addr [0:3];
    reg [31:0] slot_request_data [0:3];
    reg [31:0] slot_read_data [0:3];
    reg        slot_error [0:3];
    reg        slot_pending [0:3];
    reg [2:0]  slot_state [0:3];

    reg [63:0] oldest_id_n;
    reg [63:0] execute_id_n;
    reg [63:0] slot_id_n [0:3];
    reg        slot_is_set_n [0:3];
    reg [15:0] slot_addr_n [0:3];
    reg [31:0] slot_request_data_n [0:3];
    reg [31:0] slot_read_data_n [0:3];
    reg        slot_error_n [0:3];
    reg        slot_pending_n [0:3];
    reg [2:0]  slot_state_n [0:3];
    reg        fault_hold_n;

    reg [63:0] candidate_oldest;
    reg [1:0]  request_slot;
    reg        target_retained;
    reg        request_conflict;
    reg        retire_conflict;
    reg        block_new_offer;
    integer i;

    wire [1:0] execute_slot = execute_id[1:0] - 1'b1;
    wire [64:0] request_ext = {1'b0, req_id_i};
    wire [64:0] execute_plus_three = {1'b0, execute_id} + 65'd3;
    wire [64:0] oldest_plus_three = {1'b0, oldest_id} + 65'd3;
    wire req_fire = req_valid_i && req_ready_o;
    wire exec_fire = exec_valid_o && exec_ready_i;
    wire result_fire = result_valid_i && result_ready_o;

    assign req_ready_o = resetn_i;

    assign exec_valid_o = resetn_i &&
                          (slot_state[execute_slot] == SLOT_OFFERED) &&
                          (slot_id[execute_slot] == execute_id);
    assign exec_is_set_o = slot_is_set[execute_slot];
    assign exec_addr_o   = slot_addr[execute_slot];
    assign exec_wdata_o  = slot_request_data[execute_slot];

    assign result_ready_o = resetn_i &&
                            (slot_state[execute_slot] == SLOT_RUNNING) &&
                            (slot_id[execute_slot] == execute_id);

    assign oldest_id_o  = oldest_id;
    assign execute_id_o = execute_id;

    genvar g;
    generate
        for (g = 0; g < 4; g = g + 1) begin : flatten_slots
            assign slot_pending_o[g] = (slot_state[g] == SLOT_DONE) && slot_pending[g];
            assign slot_is_set_o[g]  = slot_is_set[g];
            assign slot_error_o[g]   = slot_error[g];
            assign slot_id_o[g*64 +: 64] = slot_id[g];
            assign slot_addr_o[g*16 +: 16] = slot_addr[g];
            assign slot_data_o[g*32 +: 32] = slot_is_set[g] ?
                                              slot_request_data[g] :
                                              (slot_error[g] ? 32'd0 : slot_read_data[g]);
        end
    endgenerate

    always @* begin
        oldest_id_n  = oldest_id;
        execute_id_n = execute_id;
        fault_hold_n = fault_hold_o;
        for (i = 0; i < 4; i = i + 1) begin
            slot_id_n[i]           = slot_id[i];
            slot_is_set_n[i]       = slot_is_set[i];
            slot_addr_n[i]         = slot_addr[i];
            slot_request_data_n[i] = slot_request_data[i];
            slot_read_data_n[i]    = slot_read_data[i];
            slot_error_n[i]        = slot_error[i];
            slot_pending_n[i]      = slot_pending[i];
            slot_state_n[i]        = slot_state[i];
        end

        window_drop_event_o    = 1'b0;
        duplicate_event_o      = 1'b0;
        id_conflict_event_o    = 1'b0;
        query_executed_event_o = 1'b0;
        set_executed_event_o   = 1'b0;
        reg_error_event_o      = 1'b0;

        candidate_oldest = oldest_id;
        request_slot      = req_id_i[1:0] - 1'b1;
        target_retained   = 1'b0;
        request_conflict  = 1'b0;
        retire_conflict   = 1'b0;
        block_new_offer   = fault_hold_o || tx_fault_event_i;

        if (tx_fault_event_i)
            fault_hold_n = 1'b1;

        // A take consumes only one pending send request.  The result and its
        // tag remain owned by the window until A advances.
        if (take_valid_i &&
            (slot_state[take_slot_i] == SLOT_DONE) &&
            (slot_id[take_slot_i] == take_request_id_i))
            slot_pending_n[take_slot_i] = 1'b0;

        if (req_fire) begin
            if ((req_id_i < oldest_id) || (request_ext > execute_plus_three)) begin
                window_drop_event_o = 1'b1;
            end else begin
                if (request_ext > oldest_plus_three)
                    candidate_oldest = req_id_i - 64'd3;

                for (i = 0; i < 4; i = i + 1)
                    if ((slot_state[i] != SLOT_EMPTY) &&
                        (slot_id[i] < candidate_oldest) &&
                        (slot_state[i] != SLOT_DONE))
                        retire_conflict = 1'b1;

                target_retained = (slot_state[request_slot] != SLOT_EMPTY) &&
                                  (slot_id[request_slot] >= candidate_oldest);

                if (retire_conflict ||
                    (target_retained &&
                     ((slot_id[request_slot] != req_id_i) ||
                      (slot_is_set[request_slot] != req_is_set_i) ||
                      (slot_addr[request_slot] != req_addr_i) ||
                      (slot_request_data[request_slot] != req_data_i))) ||
                    (!target_retained && (req_id_i < execute_id)))
                    request_conflict = 1'b1;

                if (request_conflict) begin
                    id_conflict_event_o = 1'b1;
                    fault_hold_n        = 1'b1;
                    block_new_offer     = 1'b1;
                end else if (target_retained) begin
                    duplicate_event_o = 1'b1;
                    if (slot_state[request_slot] == SLOT_DONE)
                        slot_pending_n[request_slot] = 1'b1;
                end else begin
                    for (i = 0; i < 4; i = i + 1) begin
                        if ((slot_state_n[i] != SLOT_EMPTY) &&
                            (slot_id_n[i] < candidate_oldest)) begin
                            slot_state_n[i]   = SLOT_EMPTY;
                            slot_pending_n[i] = 1'b0;
                        end
                    end
                    oldest_id_n = candidate_oldest;

                    slot_id_n[request_slot]           = req_id_i;
                    slot_is_set_n[request_slot]       = req_is_set_i;
                    slot_addr_n[request_slot]         = req_addr_i;
                    slot_request_data_n[request_slot] = req_data_i;
                    slot_read_data_n[request_slot]    = 32'd0;
                    slot_error_n[request_slot]        = 1'b0;
                    slot_pending_n[request_slot]      = 1'b0;
                    slot_state_n[request_slot]        = SLOT_QUEUED;
                end
            end
        end

        // An offered transaction is already authorized and must not be
        // withdrawn if another event raises fault_hold while ready is low.
        if ((slot_state[execute_slot] == SLOT_OFFERED) && exec_fire)
            slot_state_n[execute_slot] = SLOT_RUNNING;

        if (result_fire) begin
            slot_state_n[execute_slot]     = SLOT_DONE;
            slot_error_n[execute_slot]     = result_error_i;
            slot_read_data_n[execute_slot] = (result_error_i ||
                                               slot_is_set[execute_slot]) ?
                                              32'd0 : result_rdata_i;
            slot_pending_n[execute_slot]   = 1'b1;
            execute_id_n                   = execute_id + 1'b1;
            if (slot_is_set[execute_slot])
                set_executed_event_o = 1'b1;
            else
                query_executed_event_o = 1'b1;
            if (result_error_i) begin
                reg_error_event_o = 1'b1;
                fault_hold_n      = 1'b1;
                block_new_offer   = 1'b1;
            end
        end

        if ((slot_state[execute_slot] == SLOT_QUEUED) &&
            !block_new_offer && !request_conflict)
            slot_state_n[execute_slot] = SLOT_OFFERED;
    end

    always @(posedge clk_i) begin
        if (!resetn_i) begin
            oldest_id    <= 64'd1;
            execute_id   <= 64'd1;
            fault_hold_o <= 1'b0;
            for (i = 0; i < 4; i = i + 1) begin
                slot_id[i]           <= 64'd0;
                slot_is_set[i]       <= 1'b0;
                slot_addr[i]         <= 16'd0;
                slot_request_data[i] <= 32'd0;
                slot_read_data[i]    <= 32'd0;
                slot_error[i]        <= 1'b0;
                slot_pending[i]      <= 1'b0;
                slot_state[i]        <= SLOT_EMPTY;
            end
        end else begin
            oldest_id    <= oldest_id_n;
            execute_id   <= execute_id_n;
            fault_hold_o <= fault_hold_n;
            for (i = 0; i < 4; i = i + 1) begin
                slot_id[i]           <= slot_id_n[i];
                slot_is_set[i]       <= slot_is_set_n[i];
                slot_addr[i]         <= slot_addr_n[i];
                slot_request_data[i] <= slot_request_data_n[i];
                slot_read_data[i]    <= slot_read_data_n[i];
                slot_error[i]        <= slot_error_n[i];
                slot_pending[i]      <= slot_pending_n[i];
                slot_state[i]        <= slot_state_n[i];
            end
        end
    end

endmodule
