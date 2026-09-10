`timescale 1ns / 1ps

// Minimal behavioral Clause 22 slave used only by sim_1. It checks the master
// frame fields, provides Z0 turnaround, and returns the values expected from
// the M88E1111 strap/configuration validation scenario.
module mdio_clause22_model (
    input  wire       mdc,
    inout  wire       mdio,
    output reg        protocol_error,
    output reg [7:0]  transaction_count,
    output reg [4:0]  last_phy_addr,
    output reg [4:0]  last_reg_addr
);
    reg        drive_low;
    reg [6:0]  receive_count;
    reg [4:0]  phy_shift;
    reg [4:0]  reg_shift;
    reg [15:0] response_word;
    reg [1:0]  bmsr_read_count;

    assign mdio = drive_low ? 1'b0 : 1'bz;

    function [15:0] read_value;
        input [4:0] addr;
        input [1:0] bmsr_count;
        begin
            case (addr)
                5'd0:  read_value = 16'h1140; // BMCR: AN enable + full duplex
                5'd1:  read_value = bmsr_count == 0 ? 16'h7828 : 16'h782c;
                5'd2:  read_value = 16'h0141; // M88E1111 PHYID1
                5'd3:  read_value = 16'h0cc2; // M88E1111 PHYID2/model revision
                5'd4:  read_value = 16'h01e1; // ANAR
                5'd9:  read_value = 16'h0300; // 1000BASE-T control
                5'd27: read_value = 16'h0004; // HWCFG_MODE[3:0]
                default: read_value = 16'h0000;
            endcase
        end
    endfunction

    initial begin
        drive_low         = 1'b0;
        receive_count     = 6'd0;
        phy_shift         = 5'd0;
        reg_shift         = 5'd0;
        response_word     = 16'd0;
        bmsr_read_count   = 2'd0;
        protocol_error    = 1'b0;
        transaction_count = 8'd0;
        last_phy_addr     = 5'd0;
        last_reg_addr     = 5'd0;
    end

    // The station samples data on MDC rising edges. Verify the 32-bit
    // preamble and the 01/10 read header while collecting PHY and register IDs.
    always @(posedge mdc) begin
        if (receive_count < 6'd32) begin
            if (mdio !== 1'b1)
                protocol_error <= 1'b1;
        end else begin
            case (receive_count)
                6'd32: if (mdio !== 1'b0) protocol_error <= 1'b1; // ST[1]
                6'd33: if (mdio !== 1'b1) protocol_error <= 1'b1; // ST[0]
                6'd34: if (mdio !== 1'b1) protocol_error <= 1'b1; // OP[1]
                6'd35: if (mdio !== 1'b0) protocol_error <= 1'b1; // OP[0]
                6'd46: if (mdio !== 1'b1) protocol_error <= 1'b1; // TA=Z
                6'd47: if (mdio !== 1'b0) protocol_error <= 1'b1; // TA=0 PHY
                default: begin end
            endcase

            if ((receive_count >= 6'd36) && (receive_count <= 6'd40))
                phy_shift <= {phy_shift[3:0], mdio};

            if ((receive_count >= 6'd41) && (receive_count <= 6'd45)) begin
                reg_shift <= {reg_shift[3:0], mdio};
                if (receive_count == 6'd45) begin
                    last_phy_addr <= phy_shift;
                    last_reg_addr <= {reg_shift[3:0], mdio};
                    response_word <= read_value({reg_shift[3:0], mdio}, bmsr_read_count);
                    if ({reg_shift[3:0], mdio} == 5'd1)
                        bmsr_read_count <= bmsr_read_count + 1'b1;
                end
            end

            if (receive_count == 6'd63)
                transaction_count <= transaction_count + 1'b1;
        end

        receive_count <= receive_count + 1'b1;
    end

    // Change PHY-driven turnaround/data only on MDC falling edges.
    always @(negedge mdc) begin
        if (receive_count == 6'd47) begin
            drive_low <= 1'b1; // second turnaround bit: PHY drives zero
        end else if ((receive_count >= 6'd48) && (receive_count <= 6'd63)) begin
            drive_low <= !response_word[15 - (receive_count - 6'd48)];
        end else begin
            drive_low <= 1'b0;
        end

        if (receive_count == 7'd64) begin
            receive_count <= 6'd0;
            phy_shift     <= 5'd0;
            reg_shift     <= 5'd0;
            drive_low     <= 1'b0;
        end
    end
endmodule
