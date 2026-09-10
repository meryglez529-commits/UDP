// Static LED drive for the confirmed LED1 path.
// LED1 is active high through the MCON Q1 low-side switch. sys_clk_i has no
// product-function role in this demo; it supplies the RTL-instantiated ILA.
module led_static (
    input  wire sys_clk_i,
    output wire led1,
    output wire mdc,
    inout  wire mdio
);
    assign led1 = 1'b1;

    wire       mdio_in;
    wire       mdio_drive_low;
    wire [47:0] mdio_debug;
    wire [15:0] phy_id1_unused;
    wire [15:0] phy_id2_unused;
    wire [15:0] mode_reg27_unused;
    wire [15:0] bmcr_unused;
    wire [15:0] anar_unused;
    wire [15:0] gctrl_unused;
    wire [15:0] bmsr_first_unused;
    wire [15:0] bmsr_second_unused;

    // MDIO uses the board pull-up and is driven only low or released.
    IOBUF u_mdio_iobuf (
        .I  (1'b0),
        .T  (~mdio_drive_low),
        .O  (mdio_in),
        .IO (mdio)
    );

    m88e1111_runtime_probe u_m88e1111_runtime_probe (
        .clk             (sys_clk_i),
        .mdio_in         (mdio_in),
        .mdc             (mdc),
        .mdio_drive_low  (mdio_drive_low),
        .debug_bus       (mdio_debug),
        .phy_id1         (phy_id1_unused),
        .phy_id2         (phy_id2_unused),
        .mode_reg27      (mode_reg27_unused),
        .bmcr            (bmcr_unused),
        .anar            (anar_unused),
        .gctrl           (gctrl_unused),
        .bmsr_first      (bmsr_first_unused),
        .bmsr_second     (bmsr_second_unused)
    );

    ila_led u_ila_led (
        .clk    (sys_clk_i),
        .probe0 (led1)
    );

    ila_mdio u_ila_mdio (
        .clk    (sys_clk_i),
        .probe0 (mdio_debug)
    );
endmodule
