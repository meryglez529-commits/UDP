`timescale 1ns / 1ps

// Self-checking MDIO read-only probe simulation. It models the electrically
// released-high MDIO line and an M88E1111 at the strapped Clause 22 address 7.
module led_static_tb;
    reg  sys_clk_i = 1'b0;
    tri  mdio;
    wire mdc;
    wire mdio_drive_low;
    wire mdio_in;
    wire [47:0] debug_bus;
    wire [15:0] phy_id1;
    wire [15:0] phy_id2;
    wire [15:0] mode_reg27;
    wire [15:0] bmcr;
    wire [15:0] anar;
    wire [15:0] gctrl;
    wire [15:0] bmsr_first;
    wire [15:0] bmsr_second;
    reg selftest_seen = 1'b0;
    reg selftest_mdc_error = 1'b0;

    pullup (mdio);
    assign mdio    = mdio_drive_low ? 1'b0 : 1'bz;
    assign mdio_in = mdio;

    always #5 sys_clk_i = ~sys_clk_i;

    // The self-test is not a management frame: it must keep MDC low while it
    // exercises MDIO release-low-release before the reader begins.
    always @(posedge sys_clk_i) begin
        if (dut.probe_state == 3'd5) begin
            selftest_seen <= 1'b1;
            if (mdc !== 1'b0)
                selftest_mdc_error <= 1'b1;
        end
    end

    // Shorten only the initial/repeat idle delays; the reader itself remains
    // at the production 1 MHz MDC rate for frame-timing verification.
    m88e1111_runtime_probe #(
        .STARTUP_CYCLES     (17'd10),
        .REPEAT_IDLE_CYCLES (24'd1000)
    ) dut (
        .clk             (sys_clk_i),
        .mdio_in         (mdio_in),
        .mdc             (mdc),
        .mdio_drive_low  (mdio_drive_low),
        .debug_bus       (debug_bus),
        .phy_id1         (phy_id1),
        .phy_id2         (phy_id2),
        .mode_reg27      (mode_reg27),
        .bmcr            (bmcr),
        .anar            (anar),
        .gctrl           (gctrl),
        .bmsr_first      (bmsr_first),
        .bmsr_second     (bmsr_second)
    );

    mdio_clause22_model phy_model (
        .mdc               (mdc),
        .mdio              (mdio),
        .protocol_error    (),
        .transaction_count (),
        .last_phy_addr     (),
        .last_reg_addr     ()
    );

    initial begin
        @(posedge dut.sequence_done);
        #100;

        if (phy_model.protocol_error !== 1'b0)
            $fatal(1, "SIM_FAIL: Clause 22 frame fields or turnaround were invalid");
        if (phy_model.transaction_count !== 8)
            $fatal(1, "SIM_FAIL: expected 8 reads, saw %0d", phy_model.transaction_count);
        if (phy_model.last_phy_addr !== 5'h07)
            $fatal(1, "SIM_FAIL: expected PHY address 7, saw %0d", phy_model.last_phy_addr);
        if (phy_model.last_reg_addr !== 5'd1)
            $fatal(1, "SIM_FAIL: expected final BMSR read, saw reg %0d", phy_model.last_reg_addr);
        if (selftest_seen !== 1'b1 || selftest_mdc_error !== 1'b0)
            $fatal(1, "SIM_FAIL: MDIO self-test did not keep MDC low");
        if ({dut.selftest_idle_high, dut.selftest_low_is_low,
             dut.selftest_release_100ns_high, dut.selftest_release_250ns_high,
             dut.selftest_release_400ns_high} !== 5'b11111)
            $fatal(1, "SIM_FAIL: MDIO open-drain self-test flags=%b%b%b%b%b",
                   dut.selftest_idle_high, dut.selftest_low_is_low,
                   dut.selftest_release_100ns_high, dut.selftest_release_250ns_high,
                   dut.selftest_release_400ns_high);
        if (phy_id1 !== 16'h0141 || phy_id2 !== 16'h0cc2)
            $fatal(1, "SIM_FAIL: PHY ID readback %h:%h", phy_id1, phy_id2);
        if (mode_reg27 !== 16'h0004)
            $fatal(1, "SIM_FAIL: register 27 expected 0004, saw %h", mode_reg27);
        if (bmcr[12] !== 1'b1)
            $fatal(1, "SIM_FAIL: BMCR auto-negotiation enable was not set: %h", bmcr);
        if (anar !== 16'h01e1 || gctrl !== 16'h0300)
            $fatal(1, "SIM_FAIL: advertised capability readback ANAR=%h GCTRL=%h", anar, gctrl);
        if (bmsr_first[2] !== 1'b0 || bmsr_second[2] !== 1'b1 || bmsr_second[5] !== 1'b1)
            $fatal(1, "SIM_FAIL: BMSR latch-low test failed: first=%h second=%h", bmsr_first, bmsr_second);

        $display("SIM_PASS: MDIO self-test and read frame/TA verified; ID=0141:0cc2, mode27=0004, BMCR=%h, BMSR=%h/%h", bmcr, bmsr_first, bmsr_second);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "SIM_FAIL: timeout waiting for MDIO read sequence");
    end
endmodule
