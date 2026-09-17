`timescale 1ns / 1ps

module db500_ctrl_watchdog_tb;

    reg clk = 1'b0;
    always #4 clk = ~clk;

    reg base_resetn = 1'b0;
    reg activity = 1'b0;
    wire soft_resetn;
    wire reset_event;
    wire [31:0] reset_count;
    wire [1:0] last_reason;
    wire [1:0] state;

    integer errors = 0;
    integer low_cycles;

    db500_ctrl_watchdog #(
        .WATCHDOG_TIMEOUT_CYCLES (8),
        .RESET_HOLD_CYCLES       (4)
    ) dut (
        .clk_i               (clk),
        .base_resetn_i       (base_resetn),
        .activity_event_i    (activity),
        .soft_resetn_o       (soft_resetn),
        .reset_event_o       (reset_event),
        .reset_count_o       (reset_count),
        .last_reset_reason_o (last_reason),
        .state_o             (state)
    );

    task fail;
        input [8*120-1:0] message;
        begin
            $display("FAIL: %0s", message);
            errors = errors + 1;
        end
    endtask

    task pulse_activity;
        begin
            @(negedge clk);
            activity = 1'b1;
            @(negedge clk);
            activity = 1'b0;
        end
    endtask

    task wait_for_reset;
        integer timeout;
        begin
            timeout = 0;
            while (!reset_event && (timeout < 64)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!reset_event)
                fail("watchdog reset event did not arrive");
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk);
        base_resetn = 1'b1;

        // FRESH does not free-run or repeatedly reset while no session exists.
        repeat (20) @(posedge clk);
        @(negedge clk);
        if (!soft_resetn || (reset_count != 0) || (state != 0))
            fail("FRESH state generated an unsolicited reset");

        // An activity event arms the watchdog; a second event restarts the
        // complete quiet interval.
        pulse_activity;
        repeat (5) @(posedge clk);
        pulse_activity;
        repeat (6) @(posedge clk);
        @(negedge clk);
        if (!soft_resetn || (reset_count != 0) || (state != 1))
            fail("activity did not restart the quiet interval");

        wait_for_reset;
        if (soft_resetn || (reset_count != 1) || (last_reason != 1))
            fail("quiet timeout did not enter RESET correctly");

        // The timeout edge that raises reset_event is also the first full
        // soft-reset cycle.
        low_cycles = 1;
        while (!soft_resetn) begin
            @(negedge clk);
            if (!soft_resetn)
                low_cycles = low_cycles + 1;
        end
        if (low_cycles != 4)
            fail("soft reset pulse length was not RESET_HOLD_CYCLES");

        // Returning to FRESH stops the timer until new activity.
        repeat (20) @(posedge clk);
        @(negedge clk);
        if ((reset_count != 1) || (state != 0) || !soft_resetn)
            fail("FRESH repeated a completed watchdog reset");

        pulse_activity;
        wait_for_reset;
        if (reset_count != 2)
            fail("second watchdog generation was not counted");

        @(negedge clk);
        base_resetn = 1'b0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        if ((reset_count != 0) || (last_reason != 0) || !soft_resetn ||
            (state != 0))
            fail("base reset did not clear watchdog diagnostics");

        if (errors == 0)
            $display("RESULT=DB500_CTRL_WATCHDOG_PASSED");
        else
            $display("RESULT=DB500_CTRL_WATCHDOG_FAILED errors=%0d", errors);
        $finish;
    end

endmodule
