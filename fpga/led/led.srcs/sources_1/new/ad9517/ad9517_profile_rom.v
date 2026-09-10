`timescale 1ns / 1ps

// =============================================================================
// AD9517 SGMII_125M_V1 base-profile ROM
// =============================================================================
// This combinational ROM contains only the buffered configuration registers
// from the "base profile" table in AI-work/modules/ad9517/MODULE.md.  The
// profile programs the PLL and divider chain while keeping every board-level
// clock output powered down.  OUT0 is enabled later by the initialization
// controller, after VCO calibration and lock checks have completed.
//
// Deliberately excluded from this ROM:
//   * 0x000 and 0x004: serial-port setup, handled before the base profile.
//   * 0x003 and 0x01F: read-only identification/status registers.
//   * 0x232: self-clearing IO Update command, issued by the controller.
//   * 0x018=0x45 and 0x0F0=0x08: later calibration/output-enable actions.
//
// There are 35 valid entries, addressed by index_i values 0 through 34.
// entry_valid_o is low outside that range.  Since every stored register is a
// genuine, stable configuration register, all eight bits are verified after
// IO Update and verify_mask_o is therefore 8'hFF for every valid entry.
//
// The ROM is intentionally written as a Verilog-2001 combinational case.  It
// creates no clock domain and has no state; the initialization controller owns
// index advancement and transaction timing.
// =============================================================================

module ad9517_profile_rom (
    input  wire [5:0]  index_i,

    output reg  [12:0] addr_o,
    output reg  [7:0]  data_o,
    output reg  [7:0]  verify_mask_o,
    output reg         entry_valid_o,
    output reg         last_o
);

    always @* begin
        // Safe values for an out-of-range index.  Consumers must qualify all
        // outputs with entry_valid_o; zeros also make accidental observation
        // deterministic in simulation and hardware.
        addr_o        = 13'h0000;
        data_o        = 8'h00;
        verify_mask_o = 8'h00;
        entry_valid_o = 1'b0;
        last_o        = 1'b0;

        case (index_i)
            // PLL core, reference selection, calibration parameters and DLD.
            6'd0:  begin addr_o = 13'h010; data_o = 8'h1C; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd1:  begin addr_o = 13'h011; data_o = 8'h02; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd2:  begin addr_o = 13'h012; data_o = 8'h00; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd3:  begin addr_o = 13'h013; data_o = 8'h04; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd4:  begin addr_o = 13'h014; data_o = 8'h07; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd5:  begin addr_o = 13'h015; data_o = 8'h00; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd6:  begin addr_o = 13'h016; data_o = 8'h04; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd7:  begin addr_o = 13'h017; data_o = 8'h00; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd8:  begin addr_o = 13'h018; data_o = 8'h44; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd9:  begin addr_o = 13'h019; data_o = 8'h00; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd10: begin addr_o = 13'h01A; data_o = 8'h00; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd11: begin addr_o = 13'h01B; data_o = 8'h00; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd12: begin addr_o = 13'h01C; data_o = 8'h44; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd13: begin addr_o = 13'h01D; data_o = 8'h00; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end

            // LVPECL outputs 0..3: safe power-down during configuration.
            6'd14: begin addr_o = 13'h0F0; data_o = 8'h0A; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd15: begin addr_o = 13'h0F1; data_o = 8'h0A; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd16: begin addr_o = 13'h0F4; data_o = 8'h0A; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd17: begin addr_o = 13'h0F5; data_o = 8'h0A; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end

            // LVDS/CMOS outputs 4..7: unused and powered down.
            6'd18: begin addr_o = 13'h140; data_o = 8'h43; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd19: begin addr_o = 13'h141; data_o = 8'h43; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd20: begin addr_o = 13'h142; data_o = 8'h43; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd21: begin addr_o = 13'h143; data_o = 8'h43; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end

            // Channel divider 0 produces /4 for OUT0; divider 1 is disabled.
            6'd22: begin addr_o = 13'h190; data_o = 8'h11; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd23: begin addr_o = 13'h191; data_o = 8'h00; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd24: begin addr_o = 13'h192; data_o = 8'h00; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd25: begin addr_o = 13'h196; data_o = 8'h00; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd26: begin addr_o = 13'h197; data_o = 8'h80; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd27: begin addr_o = 13'h198; data_o = 8'h00; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end

            // Unused channel dividers 2 and 3 are bypassed and shut down.
            6'd28: begin addr_o = 13'h19C; data_o = 8'h30; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd29: begin addr_o = 13'h19D; data_o = 8'h00; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd30: begin addr_o = 13'h1A1; data_o = 8'h30; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd31: begin addr_o = 13'h1A2; data_o = 8'h00; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end

            // Internal VCO, VCO divider /3, and normal distribution sync.
            6'd32: begin addr_o = 13'h1E0; data_o = 8'h01; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd33: begin addr_o = 13'h1E1; data_o = 8'h02; verify_mask_o = 8'hFF; entry_valid_o = 1'b1; end
            6'd34: begin
                addr_o        = 13'h230;
                data_o        = 8'h00;
                verify_mask_o = 8'hFF;
                entry_valid_o = 1'b1;
                last_o        = 1'b1;
            end

            default: begin
                // Defaults assigned above intentionally retained.
            end
        endcase
    end

endmodule
