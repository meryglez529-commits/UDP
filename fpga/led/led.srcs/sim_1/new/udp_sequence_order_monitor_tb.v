`timescale 1ns / 1ps

module udp_sequence_order_monitor_tb;
    reg clk = 1'b0;
    reg resetn = 1'b0;
    reg [7:0] data = 8'd0;
    reg valid = 1'b0;
    reg ready = 1'b1;
    reg last = 1'b0;
    wire reorder_pulse;
    wire [31:0] reorder_count;
    wire [31:0] packet_count;
    wire [31:0] current_sequence;
    wire [31:0] previous_highest;
    wire [31:0] current_run_id;
    integer pulse_count = 0;

    always #4 clk = ~clk;

    udp_sequence_order_monitor #(.PAYLOAD_BASE(0)) dut (
        .clk_i(clk), .resetn_i(resetn),
        .stream_data_i(data), .stream_valid_i(valid),
        .stream_ready_i(ready), .stream_last_i(last),
        .reorder_pulse_o(reorder_pulse),
        .reorder_count_o(reorder_count), .packet_count_o(packet_count),
        .current_sequence_o(current_sequence),
        .previous_highest_o(previous_highest),
        .current_run_id_o(current_run_id)
    );

    always @(posedge clk) begin
        if (reorder_pulse)
            pulse_count <= pulse_count + 1;
    end

    task send_byte;
        input [7:0] value;
        input       is_last;
        begin
            @(negedge clk);
            data  = value;
            valid = 1'b1;
            last  = is_last;
            @(negedge clk);
            valid = 1'b0;
            last  = 1'b0;
        end
    endtask

    task send_packet;
        input [31:0] run_id;
        input [31:0] sequence;
        input        good_magic;
        begin
            send_byte(good_magic ? 8'h55 : 8'h00, 1'b0);
            send_byte(8'h50, 1'b0);
            send_byte(8'h46, 1'b0);
            send_byte(8'h31, 1'b0);
            send_byte(run_id[31:24], 1'b0);
            send_byte(run_id[23:16], 1'b0);
            send_byte(run_id[15:8],  1'b0);
            send_byte(run_id[7:0],   1'b0);
            send_byte(sequence[31:24], 1'b0);
            send_byte(sequence[23:16], 1'b0);
            send_byte(sequence[15:8],  1'b0);
            send_byte(sequence[7:0],   1'b0);
            send_byte(8'hA5, 1'b1);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        resetn = 1'b1;

        send_packet(32'h1122_3344, 32'd10, 1'b1);
        send_packet(32'h1122_3344, 32'd12, 1'b1);
        send_packet(32'h1122_3344, 32'd11, 1'b1);
        repeat (2) @(posedge clk);
        if (packet_count !== 32'd3 || reorder_count !== 32'd1 ||
            pulse_count !== 1 || current_sequence !== 32'd11 ||
            previous_highest !== 32'd12 || current_run_id !== 32'h1122_3344)
            $fatal(1, "same-run reorder detection failed");

        // A new run establishes an independent sequence baseline.
        send_packet(32'h5566_7788, 32'd1, 1'b1);
        // Non-UPF1 traffic must be ignored.
        send_packet(32'h5566_7788, 32'd0, 1'b0);
        repeat (2) @(posedge clk);
        if (packet_count !== 32'd4 || reorder_count !== 32'd1 ||
            current_sequence !== 32'd1 || current_run_id !== 32'h5566_7788)
            $fatal(1, "run reset or magic filtering failed");

        $display("RESULT=UDP_SEQUENCE_ORDER_MONITOR_PASSED");
        $finish;
    end
endmodule
