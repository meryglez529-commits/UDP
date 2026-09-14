`timescale 1ns / 1ps

// Cycle-efficiency test for the complete UDP transport plus payload echo path.
// RX frames arrive at the cadence of a 1 Gb/s Ethernet wire.  The TX ready
// model inserts the 24 byte-times that are not visible on the MAC-client AXIS
// (preamble/SFD, FCS and IFG), so both directions are paced at physical line
// rate while the payload pipeline remains fully active.
module udp_echo_pipeline_perf_tb;

    localparam [47:0] LOCAL_MAC = 48'h02_DB_50_00_00_01;
    localparam [31:0] LOCAL_IP  = 32'hC0A8_0114;
    localparam [47:0] HOST_MAC  = 48'h9C69_D31A_4C6D;
    localparam [31:0] HOST_IP   = 32'hC0A8_010A;
    localparam [15:0] UDP_PORT  = 16'd32000;
    localparam integer HIDDEN_WIRE_CYCLES = 24;

    reg clk = 1'b0;
    always #4 clk = ~clk;

    reg resetn = 1'b0;
    reg link_ready = 1'b0;

    reg [7:0] rx_tdata = 8'd0;
    reg       rx_tvalid = 1'b0;
    wire      rx_tready;
    reg       rx_tlast = 1'b0;

    wire [7:0] tx_tdata;
    wire       tx_tvalid;
    wire       tx_tready;
    wire       tx_tlast;

    wire       rx_msg_valid;
    wire       rx_msg_ready;
    wire [7:0] rx_msg_data;
    wire       rx_msg_last;
    wire [10:0] rx_msg_len;
    wire       tx_msg_valid;
    wire       tx_msg_ready;
    wire [10:0] tx_msg_len;
    wire       tx_msg_data_valid;
    wire       tx_msg_data_ready;
    wire [7:0] tx_msg_data;
    wire       tx_msg_data_last;

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
    ) transport_i (
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

    udp_payload_echo echo_i (
        .clk_i(clk),
        .resetn_i(resetn),
        .rx_msg_valid_i(rx_msg_valid),
        .rx_msg_ready_o(rx_msg_ready),
        .rx_msg_data_i(rx_msg_data),
        .rx_msg_last_i(rx_msg_last),
        .rx_msg_len_i(rx_msg_len),
        .tx_msg_valid_o(tx_msg_valid),
        .tx_msg_ready_i(tx_msg_ready),
        .tx_msg_len_o(tx_msg_len),
        .tx_msg_data_valid_o(tx_msg_data_valid),
        .tx_msg_data_ready_i(tx_msg_data_ready),
        .tx_msg_data_o(tx_msg_data),
        .tx_msg_data_last_o(tx_msg_data_last)
    );

    reg [7:0] frame [0:1599];
    integer cycle_count = 0;
    integer errors = 0;
    integer rx_stall_cycles = 0;
    integer max_rx_level = 0;
    integer tx_gap_count = 0;
    integer tx_output_index = 0;
    integer tx_frame_count = 0;
    integer expected_sequence = 0;
    integer expected_payload_length = 64;
    integer phase_tx_start_count = 0;
    integer phase_first_rx_cycle = 0;
    integer phase_last_rx_cycle = 0;
    integer phase_first_tx_cycle = 0;
    integer phase_last_tx_cycle = 0;
    integer timeout;
    integer i;

    assign tx_tready = (tx_gap_count == 0);

    task fail;
        input [8*160-1:0] message;
        begin
            $display("FAIL: %0s", message);
            errors = errors + 1;
        end
    endtask

    task set16;
        input integer index;
        input [15:0] value;
        begin
            frame[index] = value[15:8];
            frame[index+1] = value[7:0];
        end
    endtask

    task set32;
        input integer index;
        input [31:0] value;
        begin
            frame[index] = value[31:24];
            frame[index+1] = value[23:16];
            frame[index+2] = value[15:8];
            frame[index+3] = value[7:0];
        end
    endtask

    task set48;
        input integer index;
        input [47:0] value;
        begin
            frame[index] = value[47:40];
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
                  LOCAL_IP[31:16] + LOCAL_IP[15:0] +
                  16'h0011 + udp_length;
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
        input integer sequence;
        integer j;
        begin
            set48(0, LOCAL_MAC);
            set48(6, HOST_MAC);
            set16(12, 16'h0800);
            frame[14] = 8'h45;
            frame[15] = 8'h00;
            set16(16, payload_length + 28);
            set16(18, sequence[15:0]);
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
            for (j = 0; j < payload_length; j = j + 1) begin
                case (j)
                    0: frame[42+j] = sequence[31:24];
                    1: frame[42+j] = sequence[23:16];
                    2: frame[42+j] = sequence[15:8];
                    3: frame[42+j] = sequence[7:0];
                    default: frame[42+j] = (sequence + (j * 37)) & 8'hFF;
                endcase
            end
            recompute_ipv4_checksum;
            recompute_udp_checksum(payload_length);
        end
    endtask

    task send_frame_at_wire_rate;
        input integer frame_length;
        integer j;
        begin
            for (j = 0; j < frame_length; j = j + 1) begin
                @(negedge clk);
                rx_tdata = frame[j];
                rx_tvalid = 1'b1;
                rx_tlast = (j == (frame_length - 1));
                @(posedge clk);
                while (!rx_tready) begin
                    rx_stall_cycles = rx_stall_cycles + 1;
                    @(posedge clk);
                end
                if ((j == 0) && (phase_first_rx_cycle == 0))
                    phase_first_rx_cycle = cycle_count;
                if (j == (frame_length - 1))
                    phase_last_rx_cycle = cycle_count;
            end
            @(negedge clk);
            rx_tvalid = 1'b0;
            rx_tlast = 1'b0;
            rx_tdata = 8'd0;
            repeat (HIDDEN_WIRE_CYCLES) @(posedge clk);
        end
    endtask

    task wait_for_tx_count;
        input integer target_count;
        begin
            timeout = 0;
            while ((tx_frame_count < target_count) && (timeout < 100000)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (tx_frame_count < target_count)
                fail("timed out waiting for echoed TX frames");
        end
    endtask

    task run_phase;
        input integer payload_length;
        input integer packet_count;
        integer sequence;
        integer rx_span;
        integer tx_span;
        real rx_goodput_mbps;
        real tx_goodput_mbps;
        begin
            expected_payload_length = payload_length;
            expected_sequence = 0;
            phase_tx_start_count = tx_frame_count;
            phase_first_rx_cycle = 0;
            phase_last_rx_cycle = 0;
            phase_first_tx_cycle = 0;
            phase_last_tx_cycle = 0;
            rx_stall_cycles = 0;
            max_rx_level = 0;

            for (sequence = 0; sequence < packet_count; sequence = sequence + 1) begin
                build_udp_frame(payload_length, sequence);
                send_frame_at_wire_rate(payload_length + 42);
            end
            wait_for_tx_count(phase_tx_start_count + packet_count);
            repeat (HIDDEN_WIRE_CYCLES + 4) @(posedge clk);

            rx_span = phase_last_rx_cycle - phase_first_rx_cycle + 1;
            tx_span = phase_last_tx_cycle - phase_first_tx_cycle + 1;
            rx_goodput_mbps = (payload_length * packet_count * 1000.0) /
                              rx_span;
            tx_goodput_mbps = (payload_length * packet_count * 1000.0) /
                              tx_span;
            $display("PERF payload=%0d packets=%0d rx_span_cycles=%0d tx_span_cycles=%0d rx_goodput_mbps=%0.3f tx_goodput_mbps=%0.3f rx_stalls=%0d max_rx_level=%0d",
                     payload_length, packet_count, rx_span, tx_span,
                     rx_goodput_mbps, tx_goodput_mbps,
                     rx_stall_cycles, max_rx_level);

            if (rx_stall_cycles != 0)
                fail("line-rate RX encountered internal backpressure");
            if (rx_goodput_mbps < 0.99 *
                ((payload_length == 64) ? 492.307 : 957.087))
                fail("RX measured goodput was below the modeled line-rate target");
            if (tx_goodput_mbps < 0.99 *
                ((payload_length == 64) ? 492.307 : 957.087))
                fail("TX measured goodput was below the modeled line-rate target");
        end
    endtask

    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        if (!resetn) begin
            tx_gap_count <= 0;
            tx_output_index <= 0;
            tx_frame_count <= 0;
        end else begin
            if (tx_gap_count > 0)
                tx_gap_count <= tx_gap_count - 1;
            if (tx_tvalid && tx_tready) begin
                if ((tx_output_index == 0) && (phase_first_tx_cycle == 0))
                    phase_first_tx_cycle <= cycle_count;

                if (tx_output_index >= 42) begin
                    case (tx_output_index - 42)
                        0: if (tx_tdata !== expected_sequence[31:24])
                               fail("TX sequence byte 0 mismatch");
                        1: if (tx_tdata !== expected_sequence[23:16])
                               fail("TX sequence byte 1 mismatch");
                        2: if (tx_tdata !== expected_sequence[15:8])
                               fail("TX sequence byte 2 mismatch");
                        3: if (tx_tdata !== expected_sequence[7:0])
                               fail("TX sequence byte 3 mismatch");
                        default:
                            if (tx_tdata !== ((expected_sequence +
                                              ((tx_output_index - 42) * 37)) & 8'hFF))
                                fail("TX deterministic payload mismatch");
                    endcase
                end

                if (tx_tlast) begin
                    if (tx_output_index != (expected_payload_length + 41))
                        fail("TX frame length mismatch");
                    phase_last_tx_cycle <= cycle_count;
                    tx_frame_count <= tx_frame_count + 1;
                    expected_sequence <= expected_sequence + 1;
                    tx_output_index <= 0;
                    tx_gap_count <= HIDDEN_WIRE_CYCLES;
                end else begin
                    tx_output_index <= tx_output_index + 1;
                end
            end

            if (rx_fifo_level > max_rx_level)
                max_rx_level <= rx_fifo_level;
        end
    end

    initial begin
        repeat (8) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;
        link_ready = 1'b1;
        repeat (4) @(posedge clk);

        run_phase(64, 1000);
        run_phase(1472, 1000);

        if (rx_udp_accepted != 2000)
            fail("RX accepted counter mismatch after performance phases");
        if (tx_accepted != 2000 || tx_sent != 2000)
            fail("TX counters mismatch after performance phases");
        if (rx_drop_endpoint != 0 || rx_drop_ipv4 != 0 ||
            rx_drop_udp != 0 || rx_drop_checksum != 0 ||
            rx_drop_oversize != 0 || rx_drop_fifo_full != 0)
            fail("unexpected RX drop during line-rate performance phases");
        if (tx_msg_error || tx_input_error != 0)
            fail("unexpected TX input error during line-rate performance phases");

        if (errors == 0) begin
            $display("RESULT=UDP_ECHO_PIPELINE_PERF_PASSED");
            $finish;
        end else begin
            $display("RESULT=UDP_ECHO_PIPELINE_PERF_FAILED errors=%0d", errors);
            $finish;
        end
    end

endmodule
