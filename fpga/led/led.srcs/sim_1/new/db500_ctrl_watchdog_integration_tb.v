`timescale 1ns / 1ps

module db500_ctrl_watchdog_integration_tb;

    reg clk = 1'b0;
    always #4 clk = ~clk;

    reg base_resetn = 1'b0;
    wire soft_resetn;
    wire comm_resetn = base_resetn && soft_resetn;
    wire watchdog_activity;
    wire [31:0] watchdog_reset_count;
    wire [1:0] watchdog_last_reason;

    reg rx_msg_valid = 1'b0;
    wire rx_msg_ready;
    reg [7:0] rx_msg_data = 8'd0;
    reg rx_msg_last = 1'b0;
    reg [10:0] rx_msg_len = 11'd0;

    wire tx_msg_valid;
    wire [10:0] tx_msg_len;
    wire tx_msg_data_valid;
    wire [7:0] tx_msg_data;
    wire tx_msg_data_last;

    wire reg_req_valid;
    wire reg_req_ready;
    wire reg_req_write;
    wire [15:0] reg_req_addr;
    wire [31:0] reg_req_wdata;
    wire reg_rsp_valid;
    wire reg_rsp_ready;
    wire reg_rsp_error;
    wire [31:0] reg_rsp_rdata;
    wire fault_hold;
    wire [31:0] scratch0;
    wire [31:0] scratch1;
    wire [31:0] write_count;

    integer errors = 0;
    integer rsp_count = 0;
    integer capture_index = 0;
    integer timeout;
    reg [127:0] capture_shift = 128'd0;
    reg [127:0] responses [0:15];

    db500_ctrl_watchdog #(
        .WATCHDOG_TIMEOUT_CYCLES (64),
        .RESET_HOLD_CYCLES       (4)
    ) watchdog (
        .clk_i               (clk),
        .base_resetn_i       (base_resetn),
        .activity_event_i    (watchdog_activity),
        .soft_resetn_o       (soft_resetn),
        .reset_event_o       (),
        .reset_count_o       (watchdog_reset_count),
        .last_reset_reason_o (watchdog_last_reason),
        .state_o             ()
    );

    db500_udp_control control (
        .clk_i                 (clk),
        .resetn_i              (comm_resetn),
        .rx_msg_valid_i        (rx_msg_valid),
        .rx_msg_ready_o        (rx_msg_ready),
        .rx_msg_data_i         (rx_msg_data),
        .rx_msg_last_i         (rx_msg_last),
        .rx_msg_len_i          (rx_msg_len),
        .tx_msg_valid_o        (tx_msg_valid),
        .tx_msg_ready_i        (1'b1),
        .tx_msg_len_o          (tx_msg_len),
        .tx_msg_data_valid_o   (tx_msg_data_valid),
        .tx_msg_data_ready_i   (1'b1),
        .tx_msg_data_o         (tx_msg_data),
        .tx_msg_data_last_o    (tx_msg_data_last),
        .tx_msg_error_i        (1'b0),
        .reg_req_valid_o       (reg_req_valid),
        .reg_req_ready_i       (reg_req_ready),
        .reg_req_write_o       (reg_req_write),
        .reg_req_addr_o        (reg_req_addr),
        .reg_req_wdata_o       (reg_req_wdata),
        .reg_rsp_valid_i       (reg_rsp_valid),
        .reg_rsp_ready_o       (reg_rsp_ready),
        .reg_rsp_error_i       (reg_rsp_error),
        .reg_rsp_rdata_i       (reg_rsp_rdata),
        .watchdog_activity_o   (watchdog_activity),
        .fault_hold_o          (fault_hold),
        .oldest_id_o           (),
        .execute_id_o          (),
        .rx_seen_o             (),
        .rx_format_drop_o      (),
        .rx_window_drop_o      (),
        .rx_duplicate_o        (),
        .rx_id_conflict_o      (),
        .query_executed_o      (),
        .set_executed_o        (),
        .reg_error_o           (),
        .rsp_loaded_o          (),
        .tx_input_error_o      (),
        .last_fault_kind_o     ()
    );

    db500_ctrl_test_reg_bank bank (
        .clk_i            (clk),
        .resetn_i         (base_resetn),
        .txn_resetn_i     (comm_resetn),
        .watchdog_reset_count_i (watchdog_reset_count),
        .watchdog_last_reason_i (watchdog_last_reason),
        .reg_req_valid_i  (reg_req_valid),
        .reg_req_ready_o  (reg_req_ready),
        .reg_req_write_i  (reg_req_write),
        .reg_req_addr_i   (reg_req_addr),
        .reg_req_wdata_i  (reg_req_wdata),
        .reg_rsp_valid_o  (reg_rsp_valid),
        .reg_rsp_ready_i  (reg_rsp_ready),
        .reg_rsp_error_o  (reg_rsp_error),
        .reg_rsp_rdata_o  (reg_rsp_rdata),
        .scratch0_o       (scratch0),
        .scratch1_o       (scratch1),
        .write_count_o    (write_count)
    );

    function [127:0] make_record;
        input [7:0] type_value;
        input [7:0] status_value;
        input [63:0] id_value;
        input [15:0] addr_value;
        input [31:0] data_value;
        begin
            make_record = {type_value, status_value, id_value,
                           addr_value, data_value};
        end
    endfunction

    task fail;
        input [8*160-1:0] message;
        begin
            $display("FAIL: %0s", message);
            errors = errors + 1;
        end
    endtask

    task send_record;
        input [127:0] record_value;
        integer byte_number;
        begin
            for (byte_number = 0; byte_number < 16;
                 byte_number = byte_number + 1) begin
                timeout = 0;
                while (!rx_msg_ready && (timeout < 200)) begin
                    @(negedge clk);
                    timeout = timeout + 1;
                end
                if (!rx_msg_ready)
                    fail("RX was not ready during watchdog integration test");
                rx_msg_len   = 11'd16;
                rx_msg_data  = record_value[127-(byte_number*8) -: 8];
                rx_msg_last  = (byte_number == 15);
                rx_msg_valid = 1'b1;
                @(posedge clk);
                @(negedge clk);
            end
            rx_msg_valid = 1'b0;
            rx_msg_last  = 1'b0;
            rx_msg_len   = 11'd0;
        end
    endtask

    task wait_responses;
        input integer expected_count;
        begin
            timeout = 0;
            while ((rsp_count < expected_count) && (timeout < 1000)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (rsp_count < expected_count)
                fail("timed out waiting for response");
            @(negedge clk);
        end
    endtask

    task wait_watchdog_count;
        input integer expected_count;
        begin
            timeout = 0;
            while (((watchdog_reset_count < expected_count) || !soft_resetn) &&
                   (timeout < 1000)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if ((watchdog_reset_count != expected_count) || !soft_resetn)
                fail("watchdog did not complete the expected reset");
            @(negedge clk);
        end
    endtask

    always @(posedge clk) begin
        if (!base_resetn) begin
            rsp_count     <= 0;
            capture_index <= 0;
            capture_shift <= 128'd0;
        end else if (!comm_resetn) begin
            capture_index <= 0;
            capture_shift <= 128'd0;
        end else if (tx_msg_data_valid) begin
            if ((capture_index == 15) != tx_msg_data_last)
                fail("response last marker mismatch");
            if (capture_index == 15) begin
                responses[rsp_count] <= {capture_shift[119:0], tx_msg_data};
                rsp_count <= rsp_count + 1;
                capture_index <= 0;
            end else begin
                capture_shift <= {capture_shift[119:0], tx_msg_data};
                capture_index <= capture_index + 1;
            end
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk);
        base_resetn = 1'b1;
        repeat (2) @(posedge clk);

        // Generation 1 writes scratch0.
        send_record(make_record(8'h02, 8'h00, 64'd1,
                                16'h0000, 32'h1357_2468));
        wait_responses(1);
        if (responses[0] !== make_record(8'h82, 8'h00, 64'd1,
                                         16'h0000, 32'h1357_2468))
            fail("generation 1 SET response mismatch");

        wait_watchdog_count(1);
        if ((scratch0 != 32'h1357_2468) || (write_count != 1))
            fail("soft communication reset cleared register storage");

        // FRESH must not repeatedly reset while the host remains quiet.
        repeat (150) @(posedge clk);
        if (watchdog_reset_count != 1)
            fail("FRESH generated repeated resets");

        // Generation 2 restarts at ID 1 and reads the preserved value.
        send_record(make_record(8'h01, 8'h00, 64'd1,
                                16'h0000, 32'd0));
        wait_responses(2);
        if (responses[1] !== make_record(8'h81, 8'h00, 64'd1,
                                         16'h0000, 32'h1357_2468))
            fail("new generation did not read preserved scratch value");

        // An adapter error enters fail-stop.  Host silence then clears the
        // communication fault without clearing the register bank.
        send_record(make_record(8'h01, 8'h00, 64'd2,
                                16'hFFFF, 32'd0));
        wait_responses(3);
        if (!fault_hold ||
            (responses[2] !== make_record(8'h81, 8'h01, 64'd2,
                                           16'hFFFF, 32'd0)))
            fail("adapter ERROR did not enter fail-stop");

        wait_watchdog_count(2);
        if (fault_hold)
            fail("watchdog reset did not clear fail-stop");

        send_record(make_record(8'h01, 8'h00, 64'd1,
                                16'h0011, 32'd0));
        wait_responses(4);
        if (responses[3] !== make_record(8'h81, 8'h00, 64'd1,
                                         16'h0011, 32'd1))
            fail("post-fault generation did not preserve write count");

        if (errors == 0)
            $display("RESULT=DB500_CTRL_WATCHDOG_INTEGRATION_PASSED");
        else
            $display("RESULT=DB500_CTRL_WATCHDOG_INTEGRATION_FAILED errors=%0d", errors);
        $finish;
    end

endmodule
