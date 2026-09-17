`timescale 1ns / 1ps

module db500_udp_control_tb;

    reg clk = 1'b0;
    always #4 clk = ~clk;

    reg resetn = 1'b0;
    reg rx_msg_valid = 1'b0;
    wire rx_msg_ready;
    reg [7:0] rx_msg_data = 8'd0;
    reg rx_msg_last = 1'b0;
    reg [10:0] rx_msg_len = 11'd0;

    wire tx_msg_valid;
    reg  tx_msg_ready = 1'b1;
    wire [10:0] tx_msg_len;
    wire tx_msg_data_valid;
    reg  tx_msg_data_ready = 1'b1;
    wire [7:0] tx_msg_data;
    wire tx_msg_data_last;
    reg  tx_msg_error = 1'b0;

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
    wire [63:0] oldest_id;
    wire [63:0] execute_id;
    wire [31:0] rx_seen;
    wire [31:0] rx_format_drop;
    wire [31:0] rx_window_drop;
    wire [31:0] rx_duplicate;
    wire [31:0] rx_id_conflict;
    wire [31:0] query_executed;
    wire [31:0] set_executed;
    wire [31:0] reg_error;
    wire [31:0] rsp_loaded;
    wire [31:0] tx_input_error;
    wire [1:0] last_fault_kind;
    wire watchdog_activity;
    wire [31:0] scratch0;
    wire [31:0] scratch1;
    wire [31:0] write_count;

    integer errors = 0;
    integer rsp_count = 0;
    integer capture_index = 0;
    integer timeout;
    reg [127:0] capture_shift = 128'd0;
    reg [127:0] rsp_records [0:63];

    db500_udp_control dut (
        .clk_i                 (clk),
        .resetn_i              (resetn),
        .rx_msg_valid_i        (rx_msg_valid),
        .rx_msg_ready_o        (rx_msg_ready),
        .rx_msg_data_i         (rx_msg_data),
        .rx_msg_last_i         (rx_msg_last),
        .rx_msg_len_i          (rx_msg_len),
        .tx_msg_valid_o        (tx_msg_valid),
        .tx_msg_ready_i        (tx_msg_ready),
        .tx_msg_len_o          (tx_msg_len),
        .tx_msg_data_valid_o   (tx_msg_data_valid),
        .tx_msg_data_ready_i   (tx_msg_data_ready),
        .tx_msg_data_o         (tx_msg_data),
        .tx_msg_data_last_o    (tx_msg_data_last),
        .tx_msg_error_i        (tx_msg_error),
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
        .oldest_id_o           (oldest_id),
        .execute_id_o          (execute_id),
        .rx_seen_o             (rx_seen),
        .rx_format_drop_o      (rx_format_drop),
        .rx_window_drop_o      (rx_window_drop),
        .rx_duplicate_o        (rx_duplicate),
        .rx_id_conflict_o      (rx_id_conflict),
        .query_executed_o      (query_executed),
        .set_executed_o        (set_executed),
        .reg_error_o           (reg_error),
        .rsp_loaded_o          (rsp_loaded),
        .tx_input_error_o      (tx_input_error),
        .last_fault_kind_o     (last_fault_kind)
    );

    db500_ctrl_test_reg_bank bank (
        .clk_i            (clk),
        .resetn_i         (resetn),
        .txn_resetn_i     (resetn),
        .watchdog_reset_count_i (32'd0),
        .watchdog_last_reason_i (2'd0),
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

    task reset_control;
        begin
            @(negedge clk);
            resetn           = 1'b0;
            rx_msg_valid      = 1'b0;
            rx_msg_last       = 1'b0;
            tx_msg_ready      = 1'b1;
            tx_msg_data_ready = 1'b1;
            tx_msg_error      = 1'b0;
            repeat (4) @(posedge clk);
            @(negedge clk);
            resetn = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task send_bytes;
        input [127:0] record_value;
        input integer declared_length;
        input integer byte_count;
        integer byte_number;
        begin
            for (byte_number = 0; byte_number < byte_count;
                 byte_number = byte_number + 1) begin
                timeout = 0;
                while (!rx_msg_ready && (timeout < 200)) begin
                    @(negedge clk);
                    timeout = timeout + 1;
                end
                if (!rx_msg_ready)
                    fail("RX decoder did not become ready");
                rx_msg_len   = declared_length;
                rx_msg_data  = record_value[127-(byte_number*8) -: 8];
                rx_msg_last  = (byte_number == (byte_count - 1));
                rx_msg_valid = 1'b1;
                @(posedge clk);
                @(negedge clk);
            end
            rx_msg_valid = 1'b0;
            rx_msg_last  = 1'b0;
            rx_msg_data  = 8'd0;
            rx_msg_len   = 11'd0;
        end
    endtask

    task send_record;
        input [127:0] record_value;
        begin
            send_bytes(record_value, 16, 16);
        end
    endtask

    task wait_responses;
        input integer expected_count;
        begin
            timeout = 0;
            while ((rsp_count < expected_count) && (timeout < 3000)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (rsp_count < expected_count)
                fail("timed out waiting for CONTROL response");
            @(negedge clk);
        end
    endtask

    task expect_response;
        input integer record_number;
        input [127:0] expected_record;
        begin
            if (rsp_records[record_number] !== expected_record) begin
                $display("expected=%032h actual=%032h",
                         expected_record, rsp_records[record_number]);
                fail("CONTROL response record mismatch");
            end
        end
    endtask

    always @(posedge clk) begin
        if (!resetn) begin
            rsp_count     <= 0;
            capture_index <= 0;
            capture_shift <= 128'd0;
        end else begin
            if (tx_msg_valid && tx_msg_ready) begin
                if (tx_msg_len != 11'd16)
                    fail("TX descriptor length was not 16");
                capture_index <= 0;
                capture_shift <= 128'd0;
            end

            if (tx_msg_data_valid && tx_msg_data_ready) begin
                if ((capture_index == 15) != tx_msg_data_last)
                    fail("TX last did not match byte 15");
                if (capture_index == 15) begin
                    rsp_records[rsp_count] <= {capture_shift[119:0], tx_msg_data};
                    rsp_count <= rsp_count + 1;
                    capture_index <= 0;
                end else begin
                    capture_shift <= {capture_shift[119:0], tx_msg_data};
                    capture_index <= capture_index + 1;
                end
            end
        end
    end

    initial begin
        reset_control;

        // Basic SET and QUERY, followed by a malformed message which must be
        // drained without consuming request ID 3.
        send_record(make_record(8'h02, 8'h00, 64'd1,
                                16'h0000, 32'h1122_3344));
        wait_responses(1);
        expect_response(0, make_record(8'h82, 8'h00, 64'd1,
                                       16'h0000, 32'h1122_3344));
        send_record(make_record(8'h01, 8'h00, 64'd2,
                                16'h0000, 32'd0));
        wait_responses(2);
        expect_response(1, make_record(8'h81, 8'h00, 64'd2,
                                       16'h0000, 32'h1122_3344));
        send_bytes(make_record(8'h01, 8'h00, 64'd3,
                               16'h0010, 32'd0), 15, 15);
        repeat (8) @(posedge clk);
        if ((rsp_count != 2) || (rx_format_drop != 1))
            fail("malformed payload was not dropped exactly once");
        send_record(make_record(8'h01, 8'h00, 64'd3,
                                16'h0010, 32'd0));
        wait_responses(3);
        expect_response(2, make_record(8'h81, 8'h00, 64'd3,
                                       16'h0010, 32'hDB50_0001));
        if ((scratch0 != 32'h1122_3344) || (write_count != 1))
            fail("basic register side effects were incorrect");

        // Requests arrive 3,1,2 but execute and respond 1,2,3.
        reset_control;
        send_record(make_record(8'h01, 8'h00, 64'd3,
                                16'h0010, 32'd0));
        send_record(make_record(8'h02, 8'h00, 64'd1,
                                16'h0000, 32'hAAAA_0001));
        send_record(make_record(8'h02, 8'h00, 64'd2,
                                16'h0001, 32'hBBBB_0002));
        wait_responses(3);
        expect_response(0, make_record(8'h82, 8'h00, 64'd1,
                                       16'h0000, 32'hAAAA_0001));
        expect_response(1, make_record(8'h82, 8'h00, 64'd2,
                                       16'h0001, 32'hBBBB_0002));
        expect_response(2, make_record(8'h81, 8'h00, 64'd3,
                                       16'h0010, 32'hDB50_0001));
        if ((scratch0 != 32'hAAAA_0001) ||
            (scratch1 != 32'hBBBB_0002) || (write_count != 2))
            fail("out-of-order arrival changed execution semantics");

        // A duplicate before execution merges; a duplicate after completion
        // replays the saved result without a second register write.
        reset_control;
        send_record(make_record(8'h02, 8'h00, 64'd2,
                                16'h0001, 32'h2222_2222));
        send_record(make_record(8'h02, 8'h00, 64'd2,
                                16'h0001, 32'h2222_2222));
        send_record(make_record(8'h02, 8'h00, 64'd1,
                                16'h0000, 32'h1111_1111));
        wait_responses(2);
        send_record(make_record(8'h02, 8'h00, 64'd2,
                                16'h0001, 32'h2222_2222));
        wait_responses(3);
        expect_response(2, make_record(8'h82, 8'h00, 64'd2,
                                       16'h0001, 32'h2222_2222));
        if ((write_count != 2) || (rx_duplicate != 2))
            fail("duplicate request executed twice or was not counted");

        // TX backpressure does not block register execution or corrupt the
        // saved response.
        reset_control;
        tx_msg_ready = 1'b0;
        send_record(make_record(8'h02, 8'h00, 64'd1,
                                16'h0000, 32'hCAFE_BABE));
        repeat (40) @(posedge clk);
        if ((write_count != 1) || (rsp_count != 0) || (execute_id != 2))
            fail("TX backpressure leaked into ordered register execution");
        tx_msg_ready = 1'b1;
        wait_responses(1);
        expect_response(0, make_record(8'h82, 8'h00, 64'd1,
                                       16'h0000, 32'hCAFE_BABE));

        // Adapter ERROR is reported once, advances E to 2, and prevents the
        // already queued request 2 from starting.
        reset_control;
        send_record(make_record(8'h01, 8'h00, 64'd2,
                                16'h0010, 32'd0));
        send_record(make_record(8'h01, 8'h00, 64'd1,
                                16'hFFFF, 32'd0));
        wait_responses(1);
        expect_response(0, make_record(8'h81, 8'h01, 64'd1,
                                       16'hFFFF, 32'd0));
        repeat (100) @(posedge clk);
        if (!fault_hold || (execute_id != 2) || (rsp_count != 1) ||
            (reg_error != 1) || (query_executed != 1))
            fail("register ERROR did not enter fail-stop correctly");

        // Same request ID with different content preserves the original slot
        // and enters fail-stop before either queued request can execute.
        reset_control;
        send_record(make_record(8'h02, 8'h00, 64'd2,
                                16'h0001, 32'hAAAA_AAAA));
        send_record(make_record(8'h02, 8'h00, 64'd2,
                                16'h0001, 32'hBBBB_BBBB));
        repeat (80) @(posedge clk);
        if (!fault_hold || (last_fault_kind != 2) ||
            (rx_id_conflict != 1) || (write_count != 0) || (rsp_count != 0))
            fail("same-ID content conflict did not preserve fail-stop");

        // A local TX contract error produces one event and terminal encoder
        // state until reset.
        reset_control;
        send_record(make_record(8'h01, 8'h00, 64'd1,
                                16'h0010, 32'd0));
        wait (tx_msg_data_valid);
        @(negedge clk);
        tx_msg_error = 1'b1;
        @(posedge clk);
        @(negedge clk);
        tx_msg_error = 1'b0;
        repeat (20) @(posedge clk);
        if (!fault_hold || (last_fault_kind != 3) ||
            (tx_input_error != 1) || tx_msg_valid || tx_msg_data_valid)
            fail("TX contract error did not enter terminal fault state");

        if (errors == 0) begin
            $display("RESULT=DB500_UDP_CONTROL_PASSED");
            $finish;
        end else begin
            $display("RESULT=DB500_UDP_CONTROL_FAILED errors=%0d", errors);
            $finish;
        end
    end

endmodule
