`timescale 1ns / 1ps

module udp_payload_echo_tb;

    reg clk = 1'b0;
    always #4 clk = ~clk;

    reg resetn = 1'b0;
    reg rx_valid = 1'b0;
    wire rx_ready;
    reg [7:0] rx_data = 8'd0;
    reg rx_last = 1'b0;
    reg [10:0] rx_len = 11'd0;
    wire tx_valid;
    reg tx_ready = 1'b0;
    wire [10:0] tx_len;
    wire tx_data_valid;
    reg tx_data_ready = 1'b0;
    wire [7:0] tx_data;
    wire tx_data_last;

    integer errors = 0;

    udp_payload_echo dut (
        .clk_i(clk),
        .resetn_i(resetn),
        .rx_msg_valid_i(rx_valid),
        .rx_msg_ready_o(rx_ready),
        .rx_msg_data_i(rx_data),
        .rx_msg_last_i(rx_last),
        .rx_msg_len_i(rx_len),
        .tx_msg_valid_o(tx_valid),
        .tx_msg_ready_i(tx_ready),
        .tx_msg_len_o(tx_len),
        .tx_msg_data_valid_o(tx_data_valid),
        .tx_msg_data_ready_i(tx_data_ready),
        .tx_msg_data_o(tx_data),
        .tx_msg_data_last_o(tx_data_last)
    );

    task check;
        input condition;
        input [8*100-1:0] message;
        begin
            if (!condition) begin
                $display("FAIL: %0s", message);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;

        // The first RX byte must remain held while the TX descriptor stalls.
        rx_valid = 1'b1;
        rx_data  = 8'h11;
        rx_last  = 1'b0;
        rx_len   = 11'd3;
        repeat (3) begin
            @(negedge clk);
            check(tx_valid && (tx_len == 11'd3),
                  "descriptor was not held during TX backpressure");
            check(!rx_ready && !tx_data_valid,
                  "RX payload advanced before descriptor acceptance");
        end

        tx_ready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        tx_ready = 1'b0;
        check(tx_data_valid && (tx_data == 8'h11) && !tx_data_last,
              "first payload byte was not presented after descriptor");
        check(!rx_ready, "RX ready ignored TX data backpressure");

        // Release three bytes with a deliberate stall between bytes 1 and 2.
        tx_data_ready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        rx_data = 8'h22;
        tx_data_ready = 1'b0;
        repeat (2) begin
            @(negedge clk);
            check(tx_data_valid && (tx_data == 8'h22) && !rx_ready,
                  "payload was not held during data backpressure");
        end

        tx_data_ready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        rx_data = 8'h33;
        rx_last = 1'b1;
        #1;
        check(tx_data_valid && (tx_data == 8'h33) && tx_data_last && rx_ready,
              "final payload byte mapping mismatch");
        @(posedge clk);
        @(negedge clk);
        rx_valid = 1'b0;
        rx_last = 1'b0;
        tx_data_ready = 1'b0;
        check(!tx_data_valid && !rx_ready,
              "echo adapter did not return to descriptor state");

        if (errors == 0) begin
            $display("RESULT=UDP_PAYLOAD_ECHO_PASSED");
            $finish;
        end else begin
            $display("RESULT=UDP_PAYLOAD_ECHO_FAILED errors=%0d", errors);
            $finish;
        end
    end

endmodule
