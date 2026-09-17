`timescale 1ns / 1ps

// Deterministic register bank for CONTROL verification only.
// 0000/0001 are writable scratch registers; 0010 is a read-only signature;
// 0011 reports the number of successful scratch writes since reset.
module db500_ctrl_test_reg_bank (
    input  wire        clk_i,
    input  wire        resetn_i,
    input  wire        txn_resetn_i,
    input  wire [31:0] watchdog_reset_count_i,
    input  wire [1:0]  watchdog_last_reason_i,

    input  wire        reg_req_valid_i,
    output wire        reg_req_ready_o,
    input  wire        reg_req_write_i,
    input  wire [15:0] reg_req_addr_i,
    input  wire [31:0] reg_req_wdata_i,

    output reg         reg_rsp_valid_o,
    input  wire        reg_rsp_ready_i,
    output reg         reg_rsp_error_o,
    output reg  [31:0] reg_rsp_rdata_o,

    output reg  [31:0] scratch0_o,
    output reg  [31:0] scratch1_o,
    output reg  [31:0] write_count_o
);

    assign reg_req_ready_o = resetn_i && txn_resetn_i && !reg_rsp_valid_o;

    always @(posedge clk_i) begin
        if (!resetn_i) begin
            reg_rsp_valid_o <= 1'b0;
            reg_rsp_error_o <= 1'b0;
            reg_rsp_rdata_o <= 32'd0;
            scratch0_o      <= 32'hC0DE_C0DE;
            scratch1_o      <= 32'h0000_0000;
            write_count_o   <= 32'd0;
        end else if (!txn_resetn_i) begin
            // A communication-generation reset cancels only an unfinished
            // adapter transaction.  Register storage models product
            // configuration and deliberately survives this reset.
            reg_rsp_valid_o <= 1'b0;
            reg_rsp_error_o <= 1'b0;
            reg_rsp_rdata_o <= 32'd0;
        end else begin
            if (reg_rsp_valid_o && reg_rsp_ready_i)
                reg_rsp_valid_o <= 1'b0;

            if (reg_req_valid_i && reg_req_ready_o) begin
                reg_rsp_valid_o <= 1'b1;
                reg_rsp_error_o <= 1'b0;
                reg_rsp_rdata_o <= 32'd0;
                case (reg_req_addr_i)
                    16'h0000: begin
                        if (reg_req_write_i) begin
                            scratch0_o    <= reg_req_wdata_i;
                            write_count_o <= write_count_o + 1'b1;
                        end else begin
                            reg_rsp_rdata_o <= scratch0_o;
                        end
                    end

                    16'h0001: begin
                        if (reg_req_write_i) begin
                            scratch1_o    <= reg_req_wdata_i;
                            write_count_o <= write_count_o + 1'b1;
                        end else begin
                            reg_rsp_rdata_o <= scratch1_o;
                        end
                    end

                    16'h0010: begin
                        if (reg_req_write_i)
                            reg_rsp_error_o <= 1'b1;
                        else
                            reg_rsp_rdata_o <= 32'hDB50_0001;
                    end

                    16'h0011: begin
                        if (reg_req_write_i)
                            reg_rsp_error_o <= 1'b1;
                        else
                            reg_rsp_rdata_o <= write_count_o;
                    end

                    16'h0012: begin
                        if (reg_req_write_i)
                            reg_rsp_error_o <= 1'b1;
                        else
                            reg_rsp_rdata_o <= watchdog_reset_count_i;
                    end

                    16'h0013: begin
                        if (reg_req_write_i)
                            reg_rsp_error_o <= 1'b1;
                        else
                            reg_rsp_rdata_o <= {30'd0, watchdog_last_reason_i};
                    end

                    default: reg_rsp_error_o <= 1'b1;
                endcase
            end
        end
    end

endmodule
