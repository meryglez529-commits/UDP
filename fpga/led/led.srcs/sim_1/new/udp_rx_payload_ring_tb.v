`timescale 1ns / 1ps

module udp_rx_payload_ring_tb;

    localparam integer MAX_PAYLOAD = 1472;

    reg clk = 1'b0;
    always #4 clk = ~clk;

    reg resetn = 1'b0;
    wire slot_available;
    reg write_valid = 1'b0;
    reg [10:0] write_offset = 11'd0;
    reg [7:0] write_data = 8'd0;
    reg commit = 1'b0;
    reg [10:0] commit_length = 11'd0;
    wire msg_valid;
    reg msg_ready = 1'b0;
    wire [7:0] msg_data;
    wire msg_last;
    wire [10:0] msg_len;
    wire [2:0] level;

    integer errors = 0;
    integer i;
    integer timeout;

    udp_rx_payload_ring #(
        .MAX_UDP_PAYLOAD (MAX_PAYLOAD),
        .SLOT_COUNT      (4)
    ) dut (
        .clk_i                  (clk),
        .resetn_i               (resetn),
        .slot_available_o       (slot_available),
        .payload_write_valid_i  (write_valid),
        .payload_write_offset_i (write_offset),
        .payload_write_data_i   (write_data),
        .commit_i               (commit),
        .commit_length_i        (commit_length),
        .msg_valid_o            (msg_valid),
        .msg_ready_i            (msg_ready),
        .msg_data_o             (msg_data),
        .msg_last_o             (msg_last),
        .msg_len_o              (msg_len),
        .level_o                (level)
    );

    task fail;
        input [8*120-1:0] message;
        begin
            $display("FAIL: %0s", message);
            errors = errors + 1;
        end
    endtask

    task write_candidate;
        input integer length;
        input [7:0] seed;
        input integer do_commit;
        integer j;
        begin
            for (j = 0; j < length; j = j + 1) begin
                @(negedge clk);
                write_valid  = 1'b1;
                write_offset = j;
                write_data   = seed + j;
                @(posedge clk);
            end
            @(negedge clk);
            write_valid = 1'b0;
            if (do_commit != 0) begin
                commit        = 1'b1;
                commit_length = length;
                @(posedge clk);
                @(negedge clk);
                commit = 1'b0;
            end
        end
    endtask

    task wait_for_message;
        begin
            timeout = 0;
            while (!msg_valid && (timeout < 40)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!msg_valid)
                fail("message did not become valid");
        end
    endtask

    task consume_message;
        input integer length;
        input [7:0] seed;
        integer j;
        begin
            wait_for_message;
            if (msg_len != length)
                fail("message length mismatch");

            @(negedge clk);
            msg_ready = 1'b1;
            for (j = 0; j < length; j = j + 1) begin
                if (!msg_valid)
                    fail("message valid ended early");
                if (msg_data !== ((seed + j) & 8'hFF))
                    fail("message payload mismatch");
                if (msg_last !== (j == (length - 1)))
                    fail("message last mismatch");
                @(posedge clk);
                @(negedge clk);
            end
            msg_ready = 1'b0;
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        resetn = 1'b1;
        repeat (2) @(posedge clk);

        // A rejected candidate never becomes visible and is overwritten by
        // the next committed packet in the same write slot.
        write_candidate(3, 8'h10, 0);
        if (msg_valid || (level != 0))
            fail("aborted candidate became visible");
        write_candidate(3, 8'h20, 1);

        // Hold the first byte under backpressure and verify that the BRAM
        // prefetch register is stable.
        wait_for_message;
        if ((msg_data !== 8'h20) || (msg_len != 3))
            fail("first committed packet mismatch");
        repeat (3) begin
            @(posedge clk);
            @(negedge clk);
            if ((msg_data !== 8'h20) || msg_last)
                fail("RX output changed while stalled");
        end
        consume_message(3, 8'h20);

        // Commit a new packet on the same edge that the prior one is released.
        write_candidate(1, 8'h30, 1);
        write_candidate(1, 8'h40, 0);
        wait_for_message;
        @(negedge clk);
        msg_ready     = 1'b1;
        commit        = 1'b1;
        commit_length = 1;
        @(posedge clk);
        @(negedge clk);
        msg_ready = 1'b0;
        commit    = 1'b0;
        if ((level != 1) || !msg_valid || (msg_data !== 8'h40))
            fail("simultaneous commit and release failed");
        consume_message(1, 8'h40);

        // Fill all four slots, reject further reservation, then drain in order.
        for (i = 0; i < 4; i = i + 1)
            write_candidate(1, 8'h50 + i, 1);
        if ((level != 4) || slot_available)
            fail("four-slot full indication mismatch");
        for (i = 0; i < 4; i = i + 1)
            consume_message(1, 8'h50 + i);

        // Exercise the standard-MTU UDP payload boundary in the ring itself.
        write_candidate(MAX_PAYLOAD, 8'h60, 1);
        consume_message(MAX_PAYLOAD, 8'h60);

        // Exercise multiple complete pointer wraps with mixed packet lengths.
        for (i = 0; i < 10; i = i + 1) begin
            write_candidate((i % 8) + 1, 8'h80 + i, 1);
            consume_message((i % 8) + 1, 8'h80 + i);
        end

        if (level != 0)
            fail("RX ring did not return to empty");

        if (errors == 0) begin
            $display("RESULT=UDP_RX_PAYLOAD_RING_PASSED");
            $finish;
        end else begin
            $display("RESULT=UDP_RX_PAYLOAD_RING_FAILED errors=%0d", errors);
            $finish;
        end
    end

endmodule
