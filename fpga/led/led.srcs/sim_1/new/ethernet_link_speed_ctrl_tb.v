`timescale 1ns / 1ps

module ethernet_link_speed_ctrl_tb;

    reg         clk = 1'b0;
    reg         resetn = 1'b0;
    reg         core_ready = 1'b0;
    reg  [15:0] pcs_status = 16'b0;
    reg         mac_rx_reset = 1'b0;
    reg         mac_tx_reset = 1'b0;
    wire [1:0]  mac_speed;
    wire        update_speed;
    wire        link_ready;
    integer     update_count = 0;

    always #4 clk = ~clk;

    always @(posedge clk) begin
        if (update_speed)
            update_count = update_count + 1;
    end

    ethernet_link_speed_ctrl dut (
        .clk_i          (clk),
        .resetn_i       (resetn),
        .core_ready_i   (core_ready),
        .pcs_status_i   (pcs_status),
        .mac_rx_reset_i (mac_rx_reset),
        .mac_tx_reset_i (mac_tx_reset),
        .mac_speed_o    (mac_speed),
        .update_speed_o (update_speed),
        .link_ready_o   (link_ready)
    );

    task emulate_mac_speed_reset;
        begin
            repeat (2) @(posedge clk);
            mac_rx_reset = 1'b1;
            mac_tx_reset = 1'b1;
            repeat (3) @(posedge clk);
            mac_rx_reset = 1'b0;
            mac_tx_reset = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    task pcs_speed_assign;
        input [1:0] speed;
        begin
            pcs_status[11:10] = speed;
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        resetn = 1'b1;
        core_ready = 1'b1;
        repeat (2) @(posedge clk);
        #1;
        if (mac_speed !== 2'b10 || link_ready !== 1'b0)
            $fatal(1, "reset defaults are incorrect");

        // Initial 1 Gb/s link: even though 1G is the reset default, the
        // controller still requests and observes a complete MAC reset cycle.
        pcs_status = 16'b0;
        pcs_status[0] = 1'b1;
        pcs_status[7] = 1'b1;
        pcs_status[12] = 1'b1;
        pcs_speed_assign(2'b10);
        wait (update_count == 1);
        emulate_mac_speed_reset();
        #1;
        if (link_ready !== 1'b1 || mac_speed !== 2'b10)
            $fatal(1, "1000 Mb/s negotiation failed");

        pcs_status[7] = 1'b0;
        @(posedge clk);
        #1;
        if (link_ready !== 1'b0)
            $fatal(1, "link loss did not clear link_ready");

        pcs_status[7] = 1'b1;
        pcs_speed_assign(2'b01);
        wait (update_count == 2);
        #1;
        if (mac_speed !== 2'b01 || link_ready !== 1'b0)
            $fatal(1, "100 Mb/s negotiation was not latched");
        emulate_mac_speed_reset();
        #1;
        if (link_ready !== 1'b1)
            $fatal(1, "link_ready did not follow the observed MAC reset cycle");

        pcs_status[7] = 1'b0;
        @(posedge clk);
        #1;
        if (link_ready !== 1'b0)
            $fatal(1, "link loss did not clear link_ready");

        pcs_status[7] = 1'b1;
        pcs_speed_assign(2'b00);
        wait (update_count == 3);
        emulate_mac_speed_reset();
        #1;
        if (link_ready !== 1'b1 || mac_speed !== 2'b00)
            $fatal(1, "10 Mb/s renegotiation failed");

        pcs_status[12] = 1'b0;
        @(posedge clk);
        #1;
        if (link_ready !== 1'b0)
            $fatal(1, "half-duplex result was incorrectly accepted");

        pcs_status[12] = 1'b1;
        pcs_speed_assign(2'b11);
        repeat (4) @(posedge clk);
        #1;
        if (update_count != 3 || link_ready !== 1'b0)
            $fatal(1, "reserved SGMII speed was incorrectly accepted");

        $display("PASS: ethernet_link_speed_ctrl tri-speed sequencing");
        $finish;
    end

endmodule
