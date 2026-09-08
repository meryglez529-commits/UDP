// Static LED drive for the confirmed LED1 path.
// LED1 is active high through the MCON Q1 low-side switch. sys_clk_i has no
// product-function role in this demo; it supplies the RTL-instantiated ILA.
module led_static (
    input  wire sys_clk_i,
    output wire led1
);
    assign led1 = 1'b1;

    ila_led u_ila_led (
        .clk    (sys_clk_i),
        .probe0 (led1)
    );
endmodule
