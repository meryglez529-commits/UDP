`timescale 1ns / 1ps

// Convert one normalized CONTROL operation into one abstract register access.
// At most one access is retained; no request ID or window state is stored here.
module db500_ctrl_reg_executor (
    input  wire        clk_i,
    input  wire        resetn_i,

    input  wire        exec_valid_i,
    output wire        exec_ready_o,
    input  wire        exec_is_set_i,
    input  wire [15:0] exec_addr_i,
    input  wire [31:0] exec_wdata_i,

    output wire        result_valid_o,
    input  wire        result_ready_i,
    output wire        result_error_o,
    output wire [31:0] result_rdata_o,

    output wire        reg_req_valid_o,
    input  wire        reg_req_ready_i,
    output wire        reg_req_write_o,
    output wire [15:0] reg_req_addr_o,
    output wire [31:0] reg_req_wdata_o,

    input  wire        reg_rsp_valid_i,
    output wire        reg_rsp_ready_o,
    input  wire        reg_rsp_error_i,
    input  wire [31:0] reg_rsp_rdata_i
);

    localparam [1:0] EXEC_IDLE          = 2'd0;
    localparam [1:0] EXEC_SEND_REQ      = 2'd1;
    localparam [1:0] EXEC_WAIT_RSP      = 2'd2;
    localparam [1:0] EXEC_RETURN_RESULT = 2'd3;

    reg [1:0]  state;
    reg        request_write;
    reg [15:0] request_addr;
    reg [31:0] request_wdata;
    reg        result_error;
    reg [31:0] result_rdata;

    assign exec_ready_o      = resetn_i && (state == EXEC_IDLE);
    assign reg_req_valid_o    = resetn_i && (state == EXEC_SEND_REQ);
    assign reg_req_write_o    = request_write;
    assign reg_req_addr_o     = request_addr;
    assign reg_req_wdata_o    = request_wdata;
    assign reg_rsp_ready_o    = resetn_i && (state == EXEC_WAIT_RSP);
    assign result_valid_o     = resetn_i && (state == EXEC_RETURN_RESULT);
    assign result_error_o     = result_error;
    assign result_rdata_o     = result_rdata;

    always @(posedge clk_i) begin
        if (!resetn_i) begin
            state         <= EXEC_IDLE;
            request_write <= 1'b0;
            request_addr  <= 16'd0;
            request_wdata <= 32'd0;
            result_error  <= 1'b0;
            result_rdata  <= 32'd0;
        end else begin
            case (state)
                EXEC_IDLE: begin
                    if (exec_valid_i && exec_ready_o) begin
                        request_write <= exec_is_set_i;
                        request_addr  <= exec_addr_i;
                        request_wdata <= exec_wdata_i;
                        state         <= EXEC_SEND_REQ;
                    end
                end

                EXEC_SEND_REQ: begin
                    if (reg_req_valid_o && reg_req_ready_i)
                        state <= EXEC_WAIT_RSP;
                end

                EXEC_WAIT_RSP: begin
                    if (reg_rsp_valid_i && reg_rsp_ready_o) begin
                        result_error <= reg_rsp_error_i;
                        result_rdata <= reg_rsp_rdata_i;
                        state        <= EXEC_RETURN_RESULT;
                    end
                end

                EXEC_RETURN_RESULT: begin
                    if (result_valid_o && result_ready_i)
                        state <= EXEC_IDLE;
                end

                default: state <= EXEC_IDLE;
            endcase
        end
    end

endmodule
