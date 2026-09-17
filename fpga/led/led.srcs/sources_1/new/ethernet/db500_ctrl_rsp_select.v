`timescale 1ns / 1ps

// Stateless payload selection plus one round-robin pointer.  A selected
// result is copied by the encoder in the same cycle that take is generated.
module db500_ctrl_rsp_select (
    input  wire         clk_i,
    input  wire         resetn_i,

    input  wire [3:0]   slot_pending_i,
    input  wire [3:0]   slot_is_set_i,
    input  wire [3:0]   slot_error_i,
    input  wire [255:0] slot_id_i,
    input  wire [63:0]  slot_addr_i,
    input  wire [127:0] slot_data_i,

    input  wire         load_ready_i,
    output wire         load_fire_o,
    output reg          load_is_set_o,
    output reg          load_error_o,
    output reg  [63:0]  load_id_o,
    output reg  [15:0]  load_addr_o,
    output reg  [31:0]  load_data_o,

    output wire         take_valid_o,
    output reg  [1:0]   take_slot_o,
    output wire [63:0]  take_request_id_o
);

    reg [1:0] rr_start;
    reg [1:0] selected_slot;
    reg       selected_valid;
    integer offset;
    reg [2:0] candidate;

    always @* begin
        selected_slot  = 2'd0;
        selected_valid = 1'b0;
        candidate      = 3'd0;
        for (offset = 0; offset < 4; offset = offset + 1) begin
            candidate = {1'b0, rr_start} + offset;
            if (!selected_valid && slot_pending_i[candidate[1:0]]) begin
                selected_valid = 1'b1;
                selected_slot  = candidate[1:0];
            end
        end

        take_slot_o   = selected_slot;
        load_is_set_o = slot_is_set_i[selected_slot];
        load_error_o  = slot_error_i[selected_slot];
        case (selected_slot)
            2'd0: begin
                load_id_o   = slot_id_i[63:0];
                load_addr_o = slot_addr_i[15:0];
                load_data_o = slot_data_i[31:0];
            end
            2'd1: begin
                load_id_o   = slot_id_i[127:64];
                load_addr_o = slot_addr_i[31:16];
                load_data_o = slot_data_i[63:32];
            end
            2'd2: begin
                load_id_o   = slot_id_i[191:128];
                load_addr_o = slot_addr_i[47:32];
                load_data_o = slot_data_i[95:64];
            end
            default: begin
                load_id_o   = slot_id_i[255:192];
                load_addr_o = slot_addr_i[63:48];
                load_data_o = slot_data_i[127:96];
            end
        endcase
    end

    assign load_fire_o       = resetn_i && load_ready_i && selected_valid;
    assign take_valid_o      = load_fire_o;
    assign take_request_id_o = load_id_o;

    always @(posedge clk_i) begin
        if (!resetn_i)
            rr_start <= 2'd0;
        else if (load_fire_o)
            rr_start <= selected_slot + 1'b1;
    end

endmodule
