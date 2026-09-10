`timescale 1ns / 1ps

// One independently checked DUT/model pair.  Six instances run in parallel
// below, covering the complete acceptance and fault matrix.
module ad9517_scenario #(
    parameter integer SCENARIO = 0
) (
    output reg done_o,
    output reg pass_o
);
    localparam integer SC_NORMAL       = 0;
    localparam integer SC_BAD_ID       = 1;
    localparam integer SC_VERIFY_FAIL  = 2;
    localparam integer SC_CAL_TIMEOUT  = 3;
    localparam integer SC_DLD_TIMEOUT  = 4;
    localparam integer SC_RUNTIME_LOSS = 5;

    reg sys_clk_i = 1'b0;
    always #5 sys_clk_i = ~sys_clk_i;

    wire led1;
    wire pll_cs_n;
    wire pll_sclk;
    wire pll_sdio;
    wire pll_sdo;
    wire pll_ref_sel;
    wire pll_ld;
    wire pll_reset_n;
    wire out0_clk;
    wire model_protocol_error;
    wire [31:0] model_transaction_count;
    wire [31:0] model_update_count;
    reg runtime_unlock = 1'b0;
    time edge_time_1;
    time edge_time_2;

    wire bad_id      = (SCENARIO == SC_BAD_ID);
    wire verify_fail = (SCENARIO == SC_VERIFY_FAIL);
    wire cal_timeout = (SCENARIO == SC_CAL_TIMEOUT);
    wire dld_timeout = (SCENARIO == SC_DLD_TIMEOUT);

    ad9517_clock_manager #(
        .SYS_CLK_FREQ_HZ      (100000000),
        .SPI_SCLK_FREQ_HZ     (25000000),
        .POR_CYCLES           (4),
        .RESET_ASSERT_CYCLES  (4),
        .RESET_RELEASE_CYCLES (4),
        .SPI_TIMEOUT_CYCLES   (256),
        .CAL_TIMEOUT_CYCLES   (4000),
        .LOCK_TIMEOUT_CYCLES  (512),
        .LOCK_STABLE_CYCLES   (16),
        .LOSS_FILTER_CYCLES   (4),
        .ENABLE_ILA           (0)
    ) dut (
        .sys_clk_i       (sys_clk_i),
        .led1            (led1),
        .pll_cs_n_o      (pll_cs_n),
        .pll_sclk_o      (pll_sclk),
        .pll_sdio_o      (pll_sdio),
        .pll_sdo_i       (pll_sdo),
        .pll_ref_sel_o   (pll_ref_sel),
        .pll_ld_i        (pll_ld),
        .pll_reset_n_o   (pll_reset_n)
    );

    ad9517_model #(
        .CAL_DELAY_CYCLES (192)
    ) model (
        .sys_clk_i               (sys_clk_i),
        .pll_reset_n_i           (pll_reset_n),
        .pll_cs_n_i              (pll_cs_n),
        .pll_sclk_i              (pll_sclk),
        .pll_sdio_i              (pll_sdio),
        .pll_sdo_o               (pll_sdo),
        .pll_ld_o                (pll_ld),
        .out0_clk_o              (out0_clk),
        .force_bad_id_i          (bad_id),
        .force_verify_error_i    (verify_fail),
        .force_cal_timeout_i     (cal_timeout),
        .force_dld_low_i         (dld_timeout),
        .force_runtime_unlock_i  (runtime_unlock),
        .protocol_error_o        (model_protocol_error),
        .transaction_count_o     (model_transaction_count),
        .io_update_count_o       (model_update_count)
    );

    initial begin
        done_o = 1'b0;
        pass_o = 1'b0;

        case (SCENARIO)
            SC_NORMAL: begin
                wait (dut.clock_ready === 1'b1);
                if (dut.init_error !== 1'b0 || led1 !== 1'b1)
                    $fatal(1, "SC_NORMAL: ready/error/LED status is inconsistent");
                if (model_protocol_error !== 1'b0)
                    $fatal(1, "SC_NORMAL: SPI framing or four-wire ordering failed");
                if (model_update_count !== 3)
                    $fatal(1, "SC_NORMAL: expected three IO Updates, saw %0d", model_update_count);
                if (model.active_regs[13'h018] !== 8'h45 ||
                    model.active_regs[13'h0F0] !== 8'h08 ||
                    model.active_regs[13'h190] !== 8'h11 ||
                    model.active_regs[13'h197] !== 8'h80 ||
                    model.active_regs[13'h19C] !== 8'h30 ||
                    model.active_regs[13'h1A1] !== 8'h30 ||
                    model.active_regs[13'h1E0] !== 8'h01 ||
                    model.active_regs[13'h1E1] !== 8'h02)
                    $fatal(1, "SC_NORMAL: final active profile is incorrect");
                @(posedge out0_clk); edge_time_1 = $time;
                @(posedge out0_clk); edge_time_2 = $time;
                if ((edge_time_2 - edge_time_1) != 8)
                    $fatal(1, "SC_NORMAL: modeled OUT0 period is %0t, expected 8 ns", edge_time_2-edge_time_1);
            end

            SC_BAD_ID: begin
                wait (dut.init_error === 1'b1);
                if (dut.error_code !== 4'h3 || dut.clock_ready !== 1'b0)
                    $fatal(1, "SC_BAD_ID: expected error 3, saw %h", dut.error_code);
            end

            SC_VERIFY_FAIL: begin
                wait (dut.init_error === 1'b1);
                if (dut.error_code !== 4'h4 || dut.last_addr !== 13'h190)
                    $fatal(1, "SC_VERIFY_FAIL: code/address=%h/%h", dut.error_code, dut.last_addr);
            end

            SC_CAL_TIMEOUT: begin
                wait (dut.init_error === 1'b1);
                if (dut.error_code !== 4'h5 || dut.clock_ready !== 1'b0)
                    $fatal(1, "SC_CAL_TIMEOUT: expected error 5, saw %h", dut.error_code);
            end

            SC_DLD_TIMEOUT: begin
                wait (dut.init_error === 1'b1);
                if (dut.error_code !== 4'h6 || dut.clock_ready !== 1'b0)
                    $fatal(1, "SC_DLD_TIMEOUT: expected error 6, saw %h", dut.error_code);
            end

            SC_RUNTIME_LOSS: begin
                wait (dut.clock_ready === 1'b1);
                runtime_unlock = 1'b1;
                wait (dut.init_error === 1'b1);
                if (dut.error_code !== 4'h7 || dut.clock_ready !== 1'b0)
                    $fatal(1, "SC_RUNTIME_LOSS: expected error 7, saw %h", dut.error_code);
            end

            default: $fatal(1, "Unknown scenario %0d", SCENARIO);
        endcase

        if (model_protocol_error !== 1'b0)
            $fatal(1, "Scenario %0d ended with SPI protocol error", SCENARIO);
        if (pll_ref_sel !== 1'b0)
            $fatal(1, "Scenario %0d did not hold REF_SEL low", SCENARIO);

        pass_o = 1'b1;
        done_o = 1'b1;
        $display("SCENARIO_PASS: %0d transactions=%0d updates=%0d",
                 SCENARIO, model_transaction_count, model_update_count);
    end
endmodule

module ad9517_clock_manager_tb;
    wire [5:0] done;
    wire [5:0] pass;

    ad9517_scenario #(.SCENARIO(0)) s0 (.done_o(done[0]), .pass_o(pass[0]));
    ad9517_scenario #(.SCENARIO(1)) s1 (.done_o(done[1]), .pass_o(pass[1]));
    ad9517_scenario #(.SCENARIO(2)) s2 (.done_o(done[2]), .pass_o(pass[2]));
    ad9517_scenario #(.SCENARIO(3)) s3 (.done_o(done[3]), .pass_o(pass[3]));
    ad9517_scenario #(.SCENARIO(4)) s4 (.done_o(done[4]), .pass_o(pass[4]));
    ad9517_scenario #(.SCENARIO(5)) s5 (.done_o(done[5]), .pass_o(pass[5]));

    initial begin
        wait (&done);
        if (pass !== 6'b111111)
            $fatal(1, "SIM_FAIL: not all scenarios passed: %b", pass);
        $display("SIM_PASS: all six AD9517 initialization scenarios passed");
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "SIM_FAIL: global timeout, done=%b pass=%b", done, pass);
    end
endmodule
