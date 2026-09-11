`timescale 1ns / 1ps

module udp_transport_fixed_host_tb;

    localparam [47:0] LOCAL_MAC  = 48'h02_DB_50_00_00_01;
    localparam [31:0] LOCAL_IP   = 32'hC0A8_0114;
    localparam [47:0] HOST_MAC   = 48'h9C69_D31A_4C6D;
    localparam [31:0] HOST_IP    = 32'hC0A8_010A;
    localparam [15:0] UDP_PORT   = 16'd32000;

    reg clk = 1'b0;
    always #4 clk = ~clk;

    reg resetn = 1'b0;
    reg link_ready = 1'b0;

    reg  [7:0] rx_tdata = 8'd0;
    reg        rx_tvalid = 1'b0;
    wire       rx_tready;
    reg        rx_tlast = 1'b0;

    wire [7:0] tx_tdata;
    wire       tx_tvalid;
    reg        tx_tready = 1'b1;
    wire       tx_tlast;

    wire       rx_msg_valid;
    reg        rx_msg_ready = 1'b0;
    wire [7:0] rx_msg_data;
    wire       rx_msg_last;
    wire [10:0] rx_msg_len;

    reg        tx_msg_valid = 1'b0;
    wire       tx_msg_ready;
    reg [10:0] tx_msg_len = 11'd0;
    reg        tx_msg_data_valid = 1'b0;
    wire       tx_msg_data_ready;
    reg [7:0]  tx_msg_data = 8'd0;
    reg        tx_msg_data_last = 1'b0;
    wire       tx_msg_error;

    wire [2:0] rx_fifo_level;
    wire       tx_busy;
    wire [3:0] last_drop_reason;
    wire [31:0] rx_frames_seen;
    wire [31:0] rx_udp_accepted;
    wire [31:0] rx_drop_endpoint;
    wire [31:0] rx_drop_ipv4;
    wire [31:0] rx_drop_udp;
    wire [31:0] rx_drop_checksum;
    wire [31:0] rx_drop_oversize;
    wire [31:0] rx_drop_fifo_full;
    wire [31:0] tx_accepted;
    wire [31:0] tx_sent;
    wire [31:0] tx_input_error;

    udp_transport_fixed_host #(
        .LOCAL_MAC(LOCAL_MAC),
        .LOCAL_IPV4(LOCAL_IP),
        .HOST_MAC(HOST_MAC),
        .HOST_IPV4(HOST_IP),
        .LOCAL_UDP_PORT(UDP_PORT),
        .HOST_UDP_PORT(UDP_PORT),
        .MAX_UDP_PAYLOAD(1472)
    ) dut (
        .clk_i(clk),
        .resetn_i(resetn),
        .link_ready_i(link_ready),
        .rx_axis_tdata_i(rx_tdata),
        .rx_axis_tvalid_i(rx_tvalid),
        .rx_axis_tready_o(rx_tready),
        .rx_axis_tlast_i(rx_tlast),
        .tx_axis_tdata_o(tx_tdata),
        .tx_axis_tvalid_o(tx_tvalid),
        .tx_axis_tready_i(tx_tready),
        .tx_axis_tlast_o(tx_tlast),
        .rx_msg_valid_o(rx_msg_valid),
        .rx_msg_ready_i(rx_msg_ready),
        .rx_msg_data_o(rx_msg_data),
        .rx_msg_last_o(rx_msg_last),
        .rx_msg_len_o(rx_msg_len),
        .tx_msg_valid_i(tx_msg_valid),
        .tx_msg_ready_o(tx_msg_ready),
        .tx_msg_len_i(tx_msg_len),
        .tx_msg_data_valid_i(tx_msg_data_valid),
        .tx_msg_data_ready_o(tx_msg_data_ready),
        .tx_msg_data_i(tx_msg_data),
        .tx_msg_data_last_i(tx_msg_data_last),
        .tx_msg_error_o(tx_msg_error),
        .rx_fifo_level_o(rx_fifo_level),
        .tx_busy_o(tx_busy),
        .last_drop_reason_o(last_drop_reason),
        .rx_frames_seen_o(rx_frames_seen),
        .rx_udp_accepted_o(rx_udp_accepted),
        .rx_drop_endpoint_o(rx_drop_endpoint),
        .rx_drop_ipv4_o(rx_drop_ipv4),
        .rx_drop_udp_o(rx_drop_udp),
        .rx_drop_checksum_o(rx_drop_checksum),
        .rx_drop_oversize_o(rx_drop_oversize),
        .rx_drop_fifo_full_o(rx_drop_fifo_full),
        .tx_accepted_o(tx_accepted),
        .tx_sent_o(tx_sent),
        .tx_input_error_o(tx_input_error)
    );

    reg [7:0] frame [0:1599];
    reg [7:0] tx_capture [0:1599];
    integer tx_capture_index = 0;
    integer tx_frame_count = 0;
    integer tx_last_length = 0;
    integer i;
    integer timeout;
    integer errors = 0;
    reg tx_was_stalled = 1'b0;
    reg [7:0] tx_stalled_data = 8'd0;
    reg tx_stalled_last = 1'b0;

    always @(posedge clk) begin
        if (tx_tvalid && tx_tready) begin
            tx_capture[tx_capture_index] <= tx_tdata;
            if (tx_tlast) begin
                tx_last_length <= tx_capture_index + 1;
                tx_capture_index <= 0;
                tx_frame_count <= tx_frame_count + 1;
            end else begin
                tx_capture_index <= tx_capture_index + 1;
            end
        end

        if (tx_tvalid && !tx_tready) begin
            if (tx_was_stalled &&
                ((tx_tdata !== tx_stalled_data) || (tx_tlast !== tx_stalled_last))) begin
                $display("FAIL: TX AXI output changed while stalled");
                errors = errors + 1;
            end
            tx_was_stalled <= 1'b1;
            tx_stalled_data <= tx_tdata;
            tx_stalled_last <= tx_tlast;
        end else begin
            tx_was_stalled <= 1'b0;
        end
    end

    task fail;
        input [8*120-1:0] message;
        begin
            $display("FAIL: %0s", message);
            errors = errors + 1;
        end
    endtask

    task set16;
        input integer index;
        input [15:0] value;
        begin
            frame[index]   = value[15:8];
            frame[index+1] = value[7:0];
        end
    endtask

    task set32;
        input integer index;
        input [31:0] value;
        begin
            frame[index]   = value[31:24];
            frame[index+1] = value[23:16];
            frame[index+2] = value[15:8];
            frame[index+3] = value[7:0];
        end
    endtask

    task set48;
        input integer index;
        input [47:0] value;
        begin
            frame[index]   = value[47:40];
            frame[index+1] = value[39:32];
            frame[index+2] = value[31:24];
            frame[index+3] = value[23:16];
            frame[index+4] = value[15:8];
            frame[index+5] = value[7:0];
        end
    endtask

    task recompute_ipv4_checksum;
        integer j;
        integer sum;
        integer word_value;
        reg [15:0] checksum;
        begin
            frame[24] = 8'h00;
            frame[25] = 8'h00;
            sum = 0;
            for (j = 14; j < 34; j = j + 2) begin
                word_value = (frame[j] << 8) | frame[j+1];
                sum = sum + word_value;
            end
            while (sum > 16'hFFFF)
                sum = (sum & 16'hFFFF) + (sum >> 16);
            checksum = ~sum;
            set16(24, checksum);
        end
    endtask

    task recompute_udp_checksum;
        input integer payload_length;
        integer j;
        integer sum;
        integer word_value;
        integer udp_length;
        reg [15:0] checksum;
        begin
            udp_length = payload_length + 8;
            frame[40] = 8'h00;
            frame[41] = 8'h00;
            sum = HOST_IP[31:16] + HOST_IP[15:0] +
                  LOCAL_IP[31:16] + LOCAL_IP[15:0] + 16'h0011 + udp_length;
            for (j = 34; j < (34 + udp_length); j = j + 2) begin
                word_value = frame[j] << 8;
                if ((j + 1) < (34 + udp_length))
                    word_value = word_value | frame[j+1];
                sum = sum + word_value;
            end
            while (sum > 16'hFFFF)
                sum = (sum & 16'hFFFF) + (sum >> 16);
            checksum = ~sum;
            if (checksum == 16'h0000)
                checksum = 16'hFFFF;
            set16(40, checksum);
        end
    endtask

    task build_udp_frame;
        input integer payload_length;
        input [7:0] seed;
        integer j;
        begin
            set48(0, LOCAL_MAC);
            set48(6, HOST_MAC);
            set16(12, 16'h0800);
            frame[14] = 8'h45;
            frame[15] = 8'h00;
            set16(16, payload_length + 28);
            set16(18, 16'h1234);
            set16(20, 16'h4000);
            frame[22] = 8'd64;
            frame[23] = 8'h11;
            set16(24, 16'h0000);
            set32(26, HOST_IP);
            set32(30, LOCAL_IP);
            set16(34, UDP_PORT);
            set16(36, UDP_PORT);
            set16(38, payload_length + 8);
            set16(40, 16'h0000);
            for (j = 0; j < payload_length; j = j + 1)
                frame[42+j] = seed + j;
            recompute_ipv4_checksum;
            recompute_udp_checksum(payload_length);
        end
    endtask

    task build_arp_request;
        begin
            set48(0, 48'hFFFF_FFFF_FFFF);
            set48(6, HOST_MAC);
            set16(12, 16'h0806);
            set16(14, 16'h0001);
            set16(16, 16'h0800);
            frame[18] = 8'd6;
            frame[19] = 8'd4;
            set16(20, 16'h0001);
            set48(22, HOST_MAC);
            set32(28, HOST_IP);
            set48(32, 48'h0000_0000_0000);
            set32(38, LOCAL_IP);
        end
    endtask

    task send_frame;
        input integer frame_length;
        integer j;
        begin
            for (j = 0; j < frame_length; j = j + 1) begin
                @(negedge clk);
                rx_tdata  = frame[j];
                rx_tvalid = 1'b1;
                rx_tlast  = (j == (frame_length - 1));
                @(posedge clk);
                while (!rx_tready)
                    @(posedge clk);
            end
            @(negedge clk);
            rx_tvalid = 1'b0;
            rx_tlast  = 1'b0;
            rx_tdata  = 8'd0;
            repeat (3) @(posedge clk);
        end
    endtask

    task expect_rx_message;
        input integer payload_length;
        input [7:0] seed;
        integer j;
        reg [7:0] expected_byte;
        begin
            timeout = 0;
            while (!rx_msg_valid && (timeout < 100)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (!rx_msg_valid) begin
                fail("RX message did not become valid");
            end else begin
                if (rx_msg_len != payload_length)
                    fail("RX message length mismatch");
                @(negedge clk);
                rx_msg_ready = 1'b1;
                for (j = 0; j < payload_length; j = j + 1) begin
                    expected_byte = seed + j;
                    if (!rx_msg_valid)
                        fail("RX message ended early");
                    if (rx_msg_data !== expected_byte)
                        fail("RX payload byte mismatch");
                    if (rx_msg_last !== (j == (payload_length - 1)))
                        fail("RX last mismatch");
                    @(posedge clk);
                    @(negedge clk);
                end
                rx_msg_ready = 1'b0;
            end
        end
    endtask

    task wait_for_tx_frame;
        input integer expected_count;
        begin
            timeout = 0;
            while ((tx_frame_count < expected_count) && (timeout < 5000)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (tx_frame_count < expected_count)
                fail("TX frame timeout");
            repeat (2) @(posedge clk);
        end
    endtask

    task send_tx_message_three_bytes;
        begin
            @(negedge clk);
            tx_msg_len   = 11'd3;
            tx_msg_valid = 1'b1;
            @(posedge clk);
            while (!tx_msg_ready)
                @(posedge clk);
            @(negedge clk);
            tx_msg_valid = 1'b0;

            for (i = 0; i < 3; i = i + 1) begin
                tx_msg_data       = 8'hA0 + i;
                tx_msg_data_valid = 1'b1;
                tx_msg_data_last  = (i == 2);
                @(posedge clk);
                while (!tx_msg_data_ready)
                    @(posedge clk);
                @(negedge clk);
            end
            tx_msg_data_valid = 1'b0;
            tx_msg_data_last  = 1'b0;
        end
    endtask

    task verify_captured_udp;
        integer j;
        integer sum;
        integer word_value;
        integer udp_length;
        begin
            if (tx_last_length != 45)
                fail("TX UDP frame length mismatch");
            if ({tx_capture[0],tx_capture[1],tx_capture[2],tx_capture[3],
                 tx_capture[4],tx_capture[5]} != HOST_MAC)
                fail("TX destination MAC mismatch");
            if ({tx_capture[6],tx_capture[7],tx_capture[8],tx_capture[9],
                 tx_capture[10],tx_capture[11]} != LOCAL_MAC)
                fail("TX source MAC mismatch");
            if ({tx_capture[34],tx_capture[35]} != UDP_PORT ||
                {tx_capture[36],tx_capture[37]} != UDP_PORT)
                fail("TX UDP port mismatch");
            if ((tx_capture[42] != 8'hA0) || (tx_capture[43] != 8'hA1) ||
                (tx_capture[44] != 8'hA2))
                fail("TX UDP payload mismatch");

            sum = 0;
            for (j = 14; j < 34; j = j + 2)
                sum = sum + ((tx_capture[j] << 8) | tx_capture[j+1]);
            while (sum > 16'hFFFF)
                sum = (sum & 16'hFFFF) + (sum >> 16);
            if (sum != 16'hFFFF)
                fail("TX IPv4 checksum mismatch");

            udp_length = (tx_capture[38] << 8) | tx_capture[39];
            sum = LOCAL_IP[31:16] + LOCAL_IP[15:0] +
                  HOST_IP[31:16] + HOST_IP[15:0] + 16'h0011 + udp_length;
            for (j = 34; j < (34 + udp_length); j = j + 2) begin
                word_value = tx_capture[j] << 8;
                if ((j + 1) < (34 + udp_length))
                    word_value = word_value | tx_capture[j+1];
                sum = sum + word_value;
            end
            while (sum > 16'hFFFF)
                sum = (sum & 16'hFFFF) + (sum >> 16);
            if (sum != 16'hFFFF)
                fail("TX UDP checksum mismatch");
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        resetn = 1'b1;
        link_ready = 1'b1;
        repeat (3) @(posedge clk);

        // Valid odd-length UDP payload: exercises checksum zero-padding.
        build_udp_frame(5, 8'h10);
        send_frame(47);
        expect_rx_message(5, 8'h10);

        // The standard-MTU boundary is a 1472-byte UDP payload.
        build_udp_frame(1472, 8'h80);
        send_frame(1514);
        expect_rx_message(1472, 8'h80);

        // A payload corruption must be retained only as an uncommitted write.
        build_udp_frame(4, 8'h20);
        frame[43] = frame[43] ^ 8'h01;
        send_frame(46);
        if (rx_msg_valid || (rx_drop_checksum != 1))
            fail("Bad UDP checksum was not dropped");

        // Correct packet from a different UDP source port is an endpoint drop.
        build_udp_frame(2, 8'h30);
        set16(34, 16'd32001);
        recompute_udp_checksum(2);
        send_frame(44);
        if (rx_msg_valid || (rx_drop_endpoint != 1))
            fail("Wrong endpoint was not dropped");

        // IPv4 permits checksum zero, but this project deliberately rejects it.
        build_udp_frame(2, 8'h40);
        set16(40, 16'h0000);
        send_frame(44);
        if (rx_msg_valid || (rx_drop_checksum != 2))
            fail("Zero UDP checksum was not dropped");

        // MF or a non-zero fragment offset is outside the first-version scope.
        build_udp_frame(1, 8'h44);
        set16(20, 16'h2000);
        recompute_ipv4_checksum;
        send_frame(43);
        if (rx_msg_valid || (rx_drop_ipv4 != 1))
            fail("Fragmented IPv4 packet was not dropped");

        // UDP length must exactly agree with IPv4 total length and frame data.
        build_udp_frame(1, 8'h45);
        set16(38, 16'd10);
        send_frame(43);
        if (rx_msg_valid || (rx_drop_udp != 1))
            fail("Inconsistent UDP length was not dropped");

        // One byte beyond the standard-MTU UDP limit is an oversize drop.
        build_udp_frame(1473, 8'h46);
        send_frame(1515);
        if (rx_msg_valid || (rx_drop_oversize != 1))
            fail("Oversize UDP payload was not dropped");

        // Four committed slots must not be overwritten by a fifth datagram.
        for (i = 0; i < 5; i = i + 1) begin
            build_udp_frame(1, 8'h50 + i);
            send_frame(43);
        end
        if ((rx_fifo_level != 4) || (rx_drop_fifo_full != 1))
            fail("RX four-slot full behavior mismatch");
        for (i = 0; i < 4; i = i + 1)
            expect_rx_message(1, 8'h50 + i);

        // ARP request from the fixed host produces a standard ARP reply.
        build_arp_request;
        send_frame(42);
        wait_for_tx_frame(1);
        if (tx_last_length != 42)
            fail("ARP reply length mismatch");
        if ({tx_capture[20],tx_capture[21]} != 16'h0002)
            fail("ARP operation is not reply");
        if ({tx_capture[22],tx_capture[23],tx_capture[24],tx_capture[25],
             tx_capture[26],tx_capture[27]} != LOCAL_MAC)
            fail("ARP sender MAC mismatch");
        if ({tx_capture[28],tx_capture[29],tx_capture[30],tx_capture[31]} != LOCAL_IP)
            fail("ARP sender IP mismatch");

        // Application TX produces a complete checksummed UDP frame.
        send_tx_message_three_bytes;
        tx_tready = 1'b0;
        repeat (5) @(posedge clk);
        @(negedge clk);
        tx_tready = 1'b1;
        wait_for_tx_frame(2);
        verify_captured_udp;
        if ((tx_accepted != 1) || (tx_sent != 1))
            fail("TX counters mismatch");

        // Early TLAST is rejected without producing another Ethernet frame.
        @(negedge clk);
        tx_msg_len = 11'd2;
        tx_msg_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        tx_msg_valid = 1'b0;
        tx_msg_data = 8'hEE;
        tx_msg_data_valid = 1'b1;
        tx_msg_data_last = 1'b1;
        @(posedge clk);
        @(negedge clk);
        tx_msg_data_valid = 1'b0;
        tx_msg_data_last = 1'b0;
        repeat (5) @(posedge clk);
        if ((tx_input_error != 1) || (tx_frame_count != 2))
            fail("Malformed TX message handling mismatch");

        if (rx_udp_accepted != 6)
            fail("RX accepted counter mismatch");

        if (errors == 0) begin
            $display("RESULT=UDP_TRANSPORT_FIXED_HOST_PASSED");
            $finish;
        end else begin
            $display("RESULT=UDP_TRANSPORT_FIXED_HOST_FAILED errors=%0d", errors);
            $finish;
        end
    end

endmodule
