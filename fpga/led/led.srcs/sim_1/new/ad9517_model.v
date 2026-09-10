`timescale 1ns / 1ps

// Behavioral AD9517 serial-port model used only by the self-checking testbench.
// It models the features exercised by the RTL: 24-bit four-wire transactions,
// buffer/active register banks, IO Update, VCO-calibration status, DLD, and an
// OUT0 clock that appears only for the exact 50 -> 125 MHz register profile.
module ad9517_model #(
    parameter integer CAL_DELAY_CYCLES = 192
) (
    input  wire sys_clk_i,
    input  wire pll_reset_n_i,
    input  wire pll_cs_n_i,
    input  wire pll_sclk_i,
    input  wire pll_sdio_i,
    output reg  pll_sdo_o,
    output wire pll_ld_o,
    output reg  out0_clk_o,

    input  wire force_bad_id_i,
    input  wire force_verify_error_i,
    input  wire force_cal_timeout_i,
    input  wire force_dld_low_i,
    input  wire force_runtime_unlock_i,

    output reg  protocol_error_o,
    output integer transaction_count_o,
    output integer io_update_count_o
);

    reg [7:0] buffer_regs [0:8191];
    reg [7:0] active_regs [0:8191];

    reg [23:0] rx_shift;
    integer bit_count;
    reg current_rw;
    reg [12:0] current_addr;
    reg [7:0] read_byte;
    reg serial_four_wire;
    reg read_active_bank;

    reg cal_finished;
    integer cal_count;
    integer reset_index;
    integer update_index;
    reg cal_rising_edge;

    wire dld_internal = cal_finished &&
                        !force_dld_low_i &&
                        !force_runtime_unlock_i;
    assign pll_ld_o = pll_reset_n_i && dld_internal;

    wire exact_out0_profile =
        (active_regs[13'h010] == 8'h1C) &&
        (active_regs[13'h011] == 8'h02) &&
        (active_regs[13'h012] == 8'h00) &&
        (active_regs[13'h013] == 8'h04) &&
        (active_regs[13'h014] == 8'h07) &&
        (active_regs[13'h015] == 8'h00) &&
        (active_regs[13'h016] == 8'h04) &&
        (active_regs[13'h018] == 8'h45) &&
        (active_regs[13'h01C] == 8'h44) &&
        (active_regs[13'h0F0] == 8'h08) &&
        (active_regs[13'h190] == 8'h11) &&
        (active_regs[13'h191] == 8'h00) &&
        (active_regs[13'h1E0] == 8'h01) &&
        (active_regs[13'h1E1] == 8'h02);

    wire out0_active = pll_reset_n_i && dld_internal && exact_out0_profile;

    // Functional 125 MHz representation for testbench period measurement.
    // OUT0 is external to the FPGA in hardware; this signal never enters DUT.
    initial out0_clk_o = 1'b0;
    always begin
        #4;
        if (out0_active)
            out0_clk_o = ~out0_clk_o;
        else
            out0_clk_o = 1'b0;
    end

    task reset_device;
        begin
            for (reset_index = 0; reset_index < 8192; reset_index = reset_index + 1) begin
                buffer_regs[reset_index] = 8'h00;
                active_regs[reset_index] = 8'h00;
            end
            buffer_regs[13'h000] = 8'h18;
            active_regs[13'h000] = 8'h18;
            buffer_regs[13'h003] = 8'hD3;
            active_regs[13'h003] = 8'hD3;
            buffer_regs[13'h004] = 8'h00;
            active_regs[13'h004] = 8'h00;
            serial_four_wire     = 1'b0;
            read_active_bank     = 1'b0;
            cal_finished         = 1'b0;
            cal_count            = 0;
            rx_shift             = 24'h000000;
            bit_count            = 0;
            current_rw           = 1'b0;
            current_addr         = 13'h0000;
            read_byte            = 8'h00;
            pll_sdo_o            = 1'b0;
            protocol_error_o     = 1'b0;
            transaction_count_o  = 0;
            io_update_count_o    = 0;
        end
    endtask

    function [7:0] register_read_value;
        input [12:0] address;
        begin
            case (address)
                13'h003: register_read_value = force_bad_id_i ? 8'h00 : 8'hD3;
                13'h01F: register_read_value =
                    (cal_finished ? 8'h40 : 8'h00) |
                    (dld_internal ? 8'h01 : 8'h00);
                default: begin
                    if (read_active_bank)
                        register_read_value = active_regs[address];
                    else
                        register_read_value = buffer_regs[address];

                    // Corrupt one stable active-register read so the DUT's
                    // masked verification path is exercised deterministically.
                    if (force_verify_error_i && read_active_bank &&
                        (address == 13'h190))
                        register_read_value = register_read_value ^ 8'h01;
                end
            endcase
        end
    endfunction

    task accept_write;
        input [12:0] address;
        input [7:0] data;
        begin
            if (address == 13'h000) begin
                buffer_regs[address] = data;
                active_regs[address] = data;
                serial_four_wire = (data == 8'h99);
            end else if (address == 13'h004) begin
                buffer_regs[address] = data;
                active_regs[address] = data;
                read_active_bank = data[0];
            end else if (address == 13'h232) begin
                if (data[0]) begin
                    cal_rising_edge = buffer_regs[13'h018][0] &&
                                      !active_regs[13'h018][0];
                    for (update_index = 0; update_index < 8192;
                         update_index = update_index + 1)
                        active_regs[update_index] = buffer_regs[update_index];

                    active_regs[13'h232] = 8'h00;
                    buffer_regs[13'h232] = 8'h00;
                    io_update_count_o = io_update_count_o + 1;

                    if (cal_rising_edge) begin
                        cal_finished = 1'b0;
                        cal_count = 0;
                    end
                end
            end else begin
                buffer_regs[address] = data;
            end
        end
    endtask

    initial reset_device();

    always @(negedge pll_reset_n_i)
        reset_device();

    // Calibration progresses in the same convenient reference timebase as
    // the testbench.  The real device uses PFD cycles, not sys_clk_i cycles.
    always @(posedge sys_clk_i) begin
        if (pll_reset_n_i && active_regs[13'h018][0] && !cal_finished &&
            !force_cal_timeout_i) begin
            if (cal_count >= ((CAL_DELAY_CYCLES < 1) ? 0 : CAL_DELAY_CYCLES - 1))
                cal_finished <= 1'b1;
            else
                cal_count <= cal_count + 1;
        end
    end

    // A falling CS# starts one and only one 24-bit transaction.
    always @(negedge pll_cs_n_i) begin
        bit_count    = 0;
        rx_shift     = 24'h000000;
        current_rw   = 1'b0;
        current_addr = 13'h0000;
        read_byte    = 8'h00;
        pll_sdo_o    = 1'b0;
    end

    // The model samples instruction/MOSI on rising SCLK, matching the DUT's
    // CPOL=0 timing.  Blocking assignments are intentional in this model.
    always @(posedge pll_sclk_i) begin
        if (!pll_cs_n_i) begin
            rx_shift = {rx_shift[22:0], pll_sdio_i};

            if (bit_count == 15) begin
                current_rw   = rx_shift[15];
                current_addr = rx_shift[12:0];
                if (rx_shift[15]) begin
                    if (!serial_four_wire)
                        protocol_error_o = 1'b1;
                    read_byte = register_read_value(rx_shift[12:0]);
                end
            end

            if (bit_count == 23) begin
                if (!current_rw)
                    accept_write(current_addr, rx_shift[7:0]);
                transaction_count_o = transaction_count_o + 1;
            end

            bit_count = bit_count + 1;
        end
    end

    // After the 16th instruction edge, launch each SDO bit on a falling edge;
    // the master samples it on the next rising edge.
    always @(negedge pll_sclk_i) begin
        if (!pll_cs_n_i && current_rw && (bit_count >= 16) && (bit_count <= 23))
            pll_sdo_o <= read_byte[23 - bit_count];
        else if (!pll_cs_n_i)
            pll_sdo_o <= 1'b0;
    end

    always @(posedge pll_cs_n_i) begin
        if (pll_reset_n_i && (bit_count != 24))
            protocol_error_o = 1'b1;
        pll_sdo_o = 1'b0;
    end

endmodule
