`timescale 1ns / 1ps

// Synchronize and qualify the asynchronous AD9517 digital lock-detect pin.
//
// A lock is accepted only after LOCK_STABLE_CYCLES consecutive synchronized
// high samples.  Once locked, LOSS_FILTER_CYCLES consecutive low samples are
// required to report loss of lock.  With the defaults at 100 MHz these values
// are 1 ms and 8 clock cycles respectively.  The explicit cycle parameters
// can be reduced in a testbench without changing the functional algorithm.
module pll_ld_sync_and_filter #(
    parameter integer CLK_FREQ_HZ        = 100000000,
    parameter integer LOCK_STABLE_CYCLES = CLK_FREQ_HZ / 1000,
    parameter integer LOSS_FILTER_CYCLES = 8
) (
    input  wire clk_i,
    input  wire rst_i,
    input  wire pll_ld_async_i,

    output wire pll_ld_sync_o,
    output reg  pll_locked_o,
    output reg  lock_acquired_o,
    output reg  lock_lost_o
);

    // Clamp accidental zero-valued overrides to one sample so counter
    // comparisons remain well-defined in both simulation and synthesis.
    localparam integer LOCK_COUNT_TARGET =
        (LOCK_STABLE_CYCLES < 1) ? 1 : LOCK_STABLE_CYCLES;
    localparam integer LOSS_COUNT_TARGET =
        (LOSS_FILTER_CYCLES < 1) ? 1 : LOSS_FILTER_CYCLES;

    // Both stages carry ASYNC_REG so Vivado can place them together and apply
    // the intended metastability treatment.  Only ld_sync is consumed by the
    // filtering logic; the asynchronous pin never enters a state decision.
    (* ASYNC_REG = "TRUE" *) reg ld_meta;
    (* ASYNC_REG = "TRUE" *) reg ld_sync;

    integer high_count;
    integer low_count;

    assign pll_ld_sync_o = ld_sync;

    // Two-flop asynchronous-input synchronizer.
    always @(posedge clk_i) begin
        if (rst_i) begin
            ld_meta <= 1'b0;
            ld_sync <= 1'b0;
        end else begin
            ld_meta <= pll_ld_async_i;
            ld_sync <= ld_meta;
        end
    end

    // Lock qualification and loss-of-lock filtering.
    always @(posedge clk_i) begin
        if (rst_i) begin
            pll_locked_o   <= 1'b0;
            lock_acquired_o <= 1'b0;
            lock_lost_o     <= 1'b0;
            high_count      <= 0;
            low_count       <= 0;
        end else begin
            // Event outputs are one-cycle pulses.  pll_locked_o carries state.
            lock_acquired_o <= 1'b0;
            lock_lost_o     <= 1'b0;

            if (!pll_locked_o) begin
                low_count <= 0;

                if (ld_sync) begin
                    if (high_count >= (LOCK_COUNT_TARGET - 1)) begin
                        pll_locked_o    <= 1'b1;
                        lock_acquired_o <= 1'b1;
                        high_count      <= 0;
                    end else begin
                        high_count <= high_count + 1;
                    end
                end else begin
                    // Any low sample before qualification restarts the full
                    // continuous-high interval.
                    high_count <= 0;
                end
            end else begin
                high_count <= 0;

                if (!ld_sync) begin
                    if (low_count >= (LOSS_COUNT_TARGET - 1)) begin
                        pll_locked_o <= 1'b0;
                        lock_lost_o  <= 1'b1;
                        low_count    <= 0;
                    end else begin
                        low_count <= low_count + 1;
                    end
                end else begin
                    // A high sample breaks the consecutive-low loss window.
                    low_count <= 0;
                end
            end
        end
    end

endmodule
