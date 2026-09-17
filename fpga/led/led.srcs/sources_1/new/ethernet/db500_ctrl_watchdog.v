`timescale 1ns / 1ps

// CONTROL communication-generation watchdog.
//
// This block is intentionally reset only by the base link reset.  It must
// remain alive while soft_resetn_o clears the UDP transport, CONTROL core,
// and register-adapter transaction state.  The Ethernet link and its client
// FIFOs remain outside this application-generation reset boundary.
module db500_ctrl_watchdog #(
    parameter integer WATCHDOG_TIMEOUT_CYCLES = 62500000,
    parameter integer RESET_HOLD_CYCLES       = 32
) (
    input  wire        clk_i,
    input  wire        base_resetn_i,
    input  wire        activity_event_i,

    output reg         soft_resetn_o,
    output reg         reset_event_o,
    output reg  [31:0] reset_count_o,
    output reg  [1:0]  last_reset_reason_o,
    output wire [1:0]  state_o
);

    localparam [1:0] WD_FRESH  = 2'd0;
    localparam [1:0] WD_ACTIVE = 2'd1;
    localparam [1:0] WD_RESET  = 2'd2;

    localparam integer TIMEOUT_WIDTH =
        (WATCHDOG_TIMEOUT_CYCLES <= 1) ? 1 : $clog2(WATCHDOG_TIMEOUT_CYCLES);
    localparam integer HOLD_WIDTH =
        (RESET_HOLD_CYCLES <= 1) ? 1 : $clog2(RESET_HOLD_CYCLES);

    reg [1:0] state;
    reg [TIMEOUT_WIDTH-1:0] quiet_count;
    reg [HOLD_WIDTH-1:0] reset_hold_count;

    assign state_o = state;

    always @(posedge clk_i) begin
        if (!base_resetn_i) begin
            state               <= WD_FRESH;
            quiet_count         <= {TIMEOUT_WIDTH{1'b0}};
            reset_hold_count    <= {HOLD_WIDTH{1'b0}};
            soft_resetn_o       <= 1'b1;
            reset_event_o       <= 1'b0;
            reset_count_o       <= 32'd0;
            last_reset_reason_o <= 2'd0;
        end else begin
            reset_event_o <= 1'b0;

            case (state)
                WD_FRESH: begin
                    soft_resetn_o    <= 1'b1;
                    quiet_count      <= {TIMEOUT_WIDTH{1'b0}};
                    reset_hold_count <= {HOLD_WIDTH{1'b0}};
                    if (activity_event_i)
                        state <= WD_ACTIVE;
                end

                WD_ACTIVE: begin
                    soft_resetn_o <= 1'b1;
                    if (activity_event_i) begin
                        quiet_count <= {TIMEOUT_WIDTH{1'b0}};
                    end else if ((WATCHDOG_TIMEOUT_CYCLES <= 1) ||
                                 (quiet_count >= WATCHDOG_TIMEOUT_CYCLES - 1)) begin
                        state               <= WD_RESET;
                        quiet_count         <= {TIMEOUT_WIDTH{1'b0}};
                        reset_hold_count    <= {HOLD_WIDTH{1'b0}};
                        soft_resetn_o       <= 1'b0;
                        reset_event_o       <= 1'b1;
                        last_reset_reason_o <= 2'd1;
                        if (reset_count_o != 32'hFFFF_FFFF)
                            reset_count_o <= reset_count_o + 1'b1;
                    end else begin
                        quiet_count <= quiet_count + 1'b1;
                    end
                end

                WD_RESET: begin
                    soft_resetn_o <= 1'b0;
                    if ((RESET_HOLD_CYCLES <= 1) ||
                        (reset_hold_count >= RESET_HOLD_CYCLES - 1)) begin
                        state            <= WD_FRESH;
                        reset_hold_count <= {HOLD_WIDTH{1'b0}};
                        soft_resetn_o    <= 1'b1;
                    end else begin
                        reset_hold_count <= reset_hold_count + 1'b1;
                    end
                end

                default: begin
                    state         <= WD_FRESH;
                    soft_resetn_o <= 1'b1;
                end
            endcase
        end
    end

endmodule
