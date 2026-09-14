`timescale 1ns / 1ps

module udp_tx_payload_ring_tb;

    localparam integer MAX_PAYLOAD = 1472;

    reg clk = 1'b0;
    always #4 clk = ~clk;

    reg resetn = 1'b0;
    reg link_ready = 1'b0;
    reg msg_valid = 1'b0;
    wire msg_ready;
    reg [10:0] msg_len = 11'd0;
    reg msg_data_valid = 1'b0;
    wire msg_data_ready;
    reg [7:0] msg_data = 8'd0;
    reg msg_data_last = 1'b0;
    wire msg_error;
    wire packet_valid;
    wire [10:0] packet_len;
    wire [31:0] packet_sum;
    reg packet_release = 1'b0;
    reg [10:0] read_addr = 11'd0;
    wire [7:0] read_data;
    wire busy;
    wire accept_event;
    wire error_event;

    integer errors = 0;
    integer error_events = 0;
    integer i;
    integer timeout;

    udp_tx_payload_ring #(
        .MAX_UDP_PAYLOAD (MAX_PAYLOAD),
        .SLOT_COUNT      (2)
    ) dut (
        .clk_i                  (clk),
        .resetn_i               (resetn),
        .link_ready_i           (link_ready),
        .msg_valid_i            (msg_valid),
        .msg_ready_o            (msg_ready),
        .msg_len_i              (msg_len),
        .msg_data_valid_i       (msg_data_valid),
        .msg_data_ready_o       (msg_data_ready),
        .msg_data_i             (msg_data),
        .msg_data_last_i        (msg_data_last),
        .msg_error_o            (msg_error),
        .packet_valid_o         (packet_valid),
        .packet_len_o           (packet_len),
        .packet_payload_sum_o   (packet_sum),
        .packet_release_i       (packet_release),
        .payload_read_addr_i    (read_addr),
        .payload_read_data_o    (read_data),
        .busy_o                 (busy),
        .accept_event_o         (accept_event),
        .error_event_o          (error_event)
    );

    always @(posedge clk) begin
        if (error_event)
            error_events <= error_events + 1;
    end

    function [31:0] expected_sum;
        input integer length;
        input [7:0] seed;
        integer j;
        reg [31:0] sum;
        reg [7:0] hi;
        begin
            sum = 0;
            hi = 0;
            for (j = 0; j < length; j = j + 1) begin
                if (!j[0])
                    hi = seed + j;
                else
                    sum = sum + (hi << 8) + ((seed + j) & 8'hFF);
            end
            if (length[0])
                sum = sum + {hi, 8'h00};
            expected_sum = sum;
        end
    endfunction

    task fail;
        input [8*120-1:0] message;
        begin
            $display("FAIL: %0s", message);
            errors = errors + 1;
        end
    endtask

    task send_packet;
        input integer length;
        input [7:0] seed;
        integer j;
        begin
            timeout = 0;
            while (!msg_ready && (timeout < 100)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!msg_ready)
                fail("TX descriptor did not become ready");

            @(negedge clk);
            msg_len   = length;
            msg_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            msg_valid = 1'b0;

            for (j = 0; j < length; j = j + 1) begin
                msg_data       = seed + j;
                msg_data_valid = 1'b1;
                msg_data_last  = (j == (length - 1));
                @(posedge clk);
                if (!msg_data_ready)
                    fail("TX payload unexpectedly backpressured");
                @(negedge clk);
            end
            msg_data_valid = 1'b0;
            msg_data_last  = 1'b0;
        end
    endtask

    task wait_for_packet;
        input integer length;
        input [7:0] seed;
        begin
            timeout = 0;
            while (!packet_valid && (timeout < 100)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!packet_valid) begin
                fail("committed TX packet did not become valid");
            end else begin
                if (packet_len != length)
                    fail("TX packet length metadata mismatch");
                if (packet_sum != expected_sum(length, seed))
                    fail("TX payload sum mismatch");
            end
        end
    endtask

    task read_and_release_packet;
        input integer length;
        input [7:0] seed;
        integer j;
        begin
            wait_for_packet(length, seed);
            for (j = 0; j < length; j = j + 1) begin
                @(negedge clk);
                read_addr = j;
                @(posedge clk);
                @(negedge clk);
                if (read_data !== ((seed + j) & 8'hFF))
                    fail("TX payload RAM read mismatch");
            end
            packet_release = 1'b1;
            @(posedge clk);
            @(negedge clk);
            packet_release = 1'b0;
            read_addr = 0;
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        resetn = 1'b1;
        link_ready = 1'b1;
        repeat (2) @(posedge clk);

        // The second slot can be written while the first is read.
        send_packet(7, 8'h10);
        fork
            send_packet(8, 8'h40);
            read_and_release_packet(7, 8'h10);
        join
        read_and_release_packet(8, 8'h40);

        // Two committed slots assert descriptor backpressure until release.
        send_packet(2, 8'h60);
        send_packet(3, 8'h70);
        if (msg_ready)
            fail("full TX ring accepted another descriptor");
        read_and_release_packet(2, 8'h60);
        if (!msg_ready)
            fail("TX ring did not recover ready after release");
        read_and_release_packet(3, 8'h70);

        // Early last aborts the candidate and never publishes a packet.
        @(negedge clk);
        msg_len = 2;
        msg_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        msg_valid = 1'b0;
        msg_data = 8'hEE;
        msg_data_valid = 1'b1;
        msg_data_last = 1'b1;
        @(posedge clk);
        @(negedge clk);
        msg_data_valid = 1'b0;
        msg_data_last = 1'b0;
        repeat (3) @(posedge clk);
        if (packet_valid || (error_events != 1))
            fail("malformed TX message was not aborted exactly once");

        // Exercise the standard-MTU UDP payload boundary in the ring itself.
        send_packet(MAX_PAYLOAD, 8'h20);
        read_and_release_packet(MAX_PAYLOAD, 8'h20);

        // Repeated commits and releases exercise both pointer wraps.
        for (i = 0; i < 8; i = i + 1) begin
            send_packet((i % 8) + 1, 8'h80 + i);
            read_and_release_packet((i % 8) + 1, 8'h80 + i);
        end

        if (busy || packet_valid)
            fail("TX ring did not return to idle");

        if (errors == 0) begin
            $display("RESULT=UDP_TX_PAYLOAD_RING_PASSED");
            $finish;
        end else begin
            $display("RESULT=UDP_TX_PAYLOAD_RING_FAILED errors=%0d", errors);
            $finish;
        end
    end

endmodule
