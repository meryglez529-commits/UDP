`timescale 1ns / 1ps

module ethernet_clk_wiz_200m_tb;

    reg  clk_in1 = 1'b0;
    reg  reset = 1'b1;
    wire clk_out1;
    wire locked;
    realtime first_edge;
    realtime last_edge;
    realtime measured_period;

    always #5 clk_in1 = ~clk_in1;

    ethernet_clk_wiz_200m dut (
        .clk_out1 (clk_out1),
        .reset    (reset),
        .locked   (locked),
        .clk_in1  (clk_in1)
    );

    initial begin
        #100;
        reset = 1'b0;
        wait (locked === 1'b1);
        @(posedge clk_out1);
        first_edge = $realtime;
        repeat (20) @(posedge clk_out1);
        last_edge = $realtime;
        measured_period = (last_edge - first_edge) / 20.0;

        if ((measured_period < 4.99) || (measured_period > 5.01))
            $fatal(1, "unexpected clk_out1 period: %0.3f ns", measured_period);

        $display("PASS: ethernet clock wizard locked, clk_out1 period=%0.3f ns", measured_period);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "timeout waiting for ethernet clock wizard lock");
    end

endmodule
