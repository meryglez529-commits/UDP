`timescale 1ns / 1ps

module udp_data_ring_tb;
    localparam integer LEN_W = 6;
    reg clk = 1'b0;
    always #4 clk = ~clk;

    reg resetn = 1'b0;
    reg link_ready = 1'b0;
    integer errors = 0;
    integer i;
    integer timeout;

    reg rx_reserve_valid = 0;
    wire rx_reserve_ready;
    reg [LEN_W-1:0] rx_reserve_len = 0;
    reg rx_write_valid = 0;
    reg [LEN_W-1:0] rx_write_offset = 0;
    reg [7:0] rx_write_data = 0;
    reg rx_commit = 0;
    reg rx_abort = 0;
    wire rx_msg_valid;
    reg rx_msg_ready = 0;
    wire [7:0] rx_msg_data;
    wire rx_msg_last;
    wire [LEN_W-1:0] rx_msg_len;
    wire [2:0] rx_level;

    reg tx_req_valid = 0;
    wire tx_req_ready;
    reg [LEN_W-1:0] tx_req_len = 0;
    reg tx_data_valid = 0;
    wire tx_data_ready;
    reg [7:0] tx_data = 0;
    reg tx_data_last = 0;
    reg tx_cancel = 0;
    wire tx_cancel_ready;
    wire tx_status_valid;
    reg tx_status_ready = 0;
    wire [2:0] tx_status;
    wire tx_packet_valid;
    wire [LEN_W-1:0] tx_packet_len;
    wire [31:0] tx_packet_sum;
    reg tx_packet_release = 0;
    reg [LEN_W-1:0] tx_read_addr = 0;
    wire [7:0] tx_read_data;

    udp_data_rx_ring #(
        .MAX_PAYLOAD(31), .BYTE_CAPACITY(64), .DESC_COUNT(4), .LEN_W(LEN_W)
    ) rx_dut (
        .clk_i(clk), .resetn_i(resetn),
        .reserve_valid_i(rx_reserve_valid), .reserve_ready_o(rx_reserve_ready),
        .reserve_len_i(rx_reserve_len), .write_valid_i(rx_write_valid),
        .write_offset_i(rx_write_offset), .write_data_i(rx_write_data),
        .commit_i(rx_commit), .abort_i(rx_abort),
        .msg_valid_o(rx_msg_valid), .msg_ready_i(rx_msg_ready),
        .msg_data_o(rx_msg_data), .msg_last_o(rx_msg_last),
        .msg_len_o(rx_msg_len), .level_o(rx_level)
    );

    udp_data_tx_ring #(
        .MAX_PAYLOAD(31), .BYTE_CAPACITY(64), .DESC_COUNT(4), .LEN_W(LEN_W)
    ) tx_dut (
        .clk_i(clk), .resetn_i(resetn), .link_ready_i(link_ready),
        .req_valid_i(tx_req_valid), .req_ready_o(tx_req_ready),
        .req_len_i(tx_req_len), .data_valid_i(tx_data_valid),
        .data_ready_o(tx_data_ready), .data_i(tx_data),
        .data_last_i(tx_data_last), .cancel_valid_i(tx_cancel),
        .cancel_ready_o(tx_cancel_ready), .status_valid_o(tx_status_valid),
        .status_ready_i(tx_status_ready), .status_o(tx_status),
        .packet_valid_o(tx_packet_valid), .packet_len_o(tx_packet_len),
        .packet_payload_sum_o(tx_packet_sum), .packet_release_i(tx_packet_release),
        .payload_read_addr_i(tx_read_addr), .payload_read_data_o(tx_read_data),
        .busy_o()
    );

    task fail;
        input [8*100-1:0] message;
        begin
            $display("FAIL: %0s", message);
            errors = errors + 1;
        end
    endtask

    task rx_reserve;
        input integer length;
        begin
            @(negedge clk); rx_reserve_len = length; rx_reserve_valid = 1; #1;
            $display("RX reserve request len=%0d ready=%0b active=%0b used=%0d desc=%0d",
                     length, rx_reserve_ready, rx_dut.candidate_active,
                     rx_dut.used_bytes, rx_dut.desc_used);
            timeout = 0;
            while (!rx_reserve_ready && timeout < 20) begin
                @(negedge clk); timeout = timeout + 1;
            end
            if (!rx_reserve_ready) begin
                $display("RX reserve blocked len=%0d active=%0b used=%0d desc=%0d",
                         length, rx_dut.candidate_active,
                         rx_dut.used_bytes, rx_dut.desc_used);
                fail("RX reserve timeout");
            end
            @(posedge clk); @(negedge clk); rx_reserve_valid = 0;
        end
    endtask

    task rx_write_commit;
        input integer length;
        input [7:0] seed;
        input integer do_commit;
        integer j;
        begin
            rx_reserve(length);
            for (j = 0; j < length; j = j + 1) begin
                @(negedge clk); rx_write_valid = 1; rx_write_offset = j;
                rx_write_data = seed + j; @(posedge clk);
            end
            @(negedge clk); rx_write_valid = 0;
            if (do_commit) rx_commit = 1; else rx_abort = 1;
            @(posedge clk); @(negedge clk); rx_commit = 0; rx_abort = 0;
        end
    endtask

    task rx_consume;
        input integer length;
        input [7:0] seed;
        integer j;
        begin
            timeout = 0;
            while (!rx_msg_valid && timeout < 20) begin @(negedge clk); timeout=timeout+1; end
            if (!rx_msg_valid) fail("RX message timeout");
            if (rx_msg_len != length) fail("RX length mismatch");
            for (j = 0; j < length; j = j + 1) begin
                @(negedge clk);
                if (rx_msg_data !== ((seed+j)&8'hff)) fail("RX data mismatch");
                if (rx_msg_last !== (j == length-1)) fail("RX last mismatch");
                rx_msg_ready = 1; @(posedge clk);
            end
            @(negedge clk); rx_msg_ready = 0;
        end
    endtask

    task tx_request;
        input integer length;
        begin
            @(negedge clk); tx_req_len = length; tx_req_valid = 1; #1;
            timeout = 0;
            while (!tx_req_ready && timeout < 20) begin @(negedge clk); timeout=timeout+1; end
            if (!tx_req_ready) fail("TX request timeout");
            @(posedge clk); @(negedge clk); tx_req_valid = 0;
        end
    endtask

    task tx_send;
        input integer length;
        input [7:0] seed;
        integer j;
        begin
            tx_request(length);
            for (j = 0; j < length; j = j + 1) begin
                @(negedge clk); tx_data_valid=1; tx_data=seed+j;
                tx_data_last=(j==length-1);
                while (!tx_data_ready) @(negedge clk);
                @(posedge clk);
            end
            @(negedge clk); tx_data_valid=0; tx_data_last=0;
            timeout=0;
            while (!tx_status_valid && timeout<20) begin @(negedge clk); timeout=timeout+1; end
            if (!tx_status_valid || tx_status != 0) fail("TX commit status mismatch");
            tx_status_ready=1; @(posedge clk); @(negedge clk); tx_status_ready=0;
        end
    endtask

    task tx_check_packet;
        input integer length;
        input [7:0] seed;
        integer j;
        begin
            if (!tx_packet_valid || tx_packet_len != length) fail("TX descriptor mismatch");
            for (j = 0; j < length; j = j + 1) begin
                @(negedge clk); tx_read_addr=j; @(posedge clk); @(negedge clk);
                if (tx_read_data !== ((seed+j)&8'hff)) fail("TX RAM data mismatch");
            end
            tx_packet_release=1; @(posedge clk); @(negedge clk); tx_packet_release=0;
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk); resetn=1; link_ready=1;

        rx_write_commit(7, 8'h20, 1);
        rx_write_commit(5, 8'h80, 0);
        rx_write_commit(11, 8'h40, 1);
        rx_consume(7, 8'h20);
        rx_consume(11, 8'h40);
        if (rx_level != 0) fail("RX level not empty");

        tx_send(7, 8'h10);
        tx_send(11, 8'h50);
        tx_check_packet(7, 8'h10);
        tx_check_packet(11, 8'h50);

        tx_request(0);
        if (!tx_status_valid || tx_status != 1) fail("TX bad length status missing");
        tx_status_ready=1; @(posedge clk); @(negedge clk); tx_status_ready=0;

        tx_request(6);
        @(negedge clk); tx_data_valid=1; tx_data=8'hAA; tx_data_last=1;
        @(posedge clk); @(negedge clk); tx_data_valid=0; tx_data_last=0;
        if (!tx_status_valid || tx_status != 2) fail("TX bad last status missing");
        tx_status_ready=1; @(posedge clk); @(negedge clk); tx_status_ready=0;

        tx_request(8);
        @(negedge clk); tx_cancel=1; @(posedge clk); @(negedge clk); tx_cancel=0;
        if (!tx_status_valid || tx_status != 3) fail("TX cancel status missing");

        if (errors == 0) $display("RESULT=UDP_DATA_RING_PASSED");
        else $display("RESULT=UDP_DATA_RING_FAILED errors=%0d", errors);
        $finish;
    end
endmodule
