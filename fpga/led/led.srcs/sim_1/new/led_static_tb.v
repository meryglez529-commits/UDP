`timescale 1ns / 1ps

// Self-checking simulation for the final LED + ILA RTL.
module led_static_tb;
    reg  sys_clk_i = 1'b0;
    wire led1;
    integer rising_edges = 0;

    always #5 sys_clk_i = ~sys_clk_i;
    always @(posedge sys_clk_i) rising_edges = rising_edges + 1;

    led_static dut (
        .sys_clk_i (sys_clk_i),
        .led1      (led1)
    );

    initial begin
        #1;
        if (led1 !== 1'b1) begin
            $fatal(1, "SIM_FAIL: LED output must be high, got %b", led1);
        end

        #35;
        if (rising_edges != 4) begin
            $fatal(1, "SIM_FAIL: expected four 100 MHz rising edges, got %0d", rising_edges);
        end
        $display("SIM_PASS: LED is high and sys_clk_i completed four rising edges");
    end
endmodule
