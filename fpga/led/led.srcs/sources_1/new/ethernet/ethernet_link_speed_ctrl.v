`timescale 1ns / 1ps

// Closes the SGMII auto-negotiation loop between the PCS/PMA and TEMAC.
// The PCS/PMA reports the copper-side result in status_vector.  The TEMAC
// configuration-vector controller must then reset both MAC directions while
// applying that speed.  link_ready_o is asserted only after that reset pulse
// has actually been observed and released.
module ethernet_link_speed_ctrl (
    input  wire        clk_i,
    input  wire        resetn_i,
    input  wire        core_ready_i,
    input  wire [15:0] pcs_status_i,
    input  wire        mac_rx_reset_i,
    input  wire        mac_tx_reset_i,

    output reg  [1:0]  mac_speed_o,
    output reg         update_speed_o,
    output reg         link_ready_o
);

    localparam [2:0] ST_WAIT_LINK          = 3'd0;
    localparam [2:0] ST_WAIT_RESET_ASSERT  = 3'd1;
    localparam [2:0] ST_WAIT_RESET_RELEASE = 3'd2;
    localparam [2:0] ST_READY              = 3'd3;

    reg [2:0] state;

    wire [1:0] negotiated_speed = pcs_status_i[11:10];
    wire       negotiated_valid = core_ready_i &&
                                  pcs_status_i[0] &&
                                  pcs_status_i[7] &&
                                  pcs_status_i[12] &&
                                  (negotiated_speed != 2'b11);
    wire       mac_reset_active = mac_rx_reset_i || mac_tx_reset_i;

    always @(posedge clk_i) begin
        if (!resetn_i) begin
            state          <= ST_WAIT_LINK;
            mac_speed_o    <= 2'b10; // TEMAC encoding: 1 Gb/s
            update_speed_o <= 1'b0;
            link_ready_o   <= 1'b0;
        end else begin
            update_speed_o <= 1'b0;

            case (state)
                ST_WAIT_LINK: begin
                    link_ready_o <= 1'b0;
                    if (negotiated_valid) begin
                        mac_speed_o    <= negotiated_speed;
                        update_speed_o <= 1'b1;
                        state          <= ST_WAIT_RESET_ASSERT;
                    end
                end

                ST_WAIT_RESET_ASSERT: begin
                    link_ready_o <= 1'b0;
                    if (!negotiated_valid ||
                        (negotiated_speed != mac_speed_o)) begin
                        state <= ST_WAIT_LINK;
                    end else if (mac_reset_active) begin
                        state <= ST_WAIT_RESET_RELEASE;
                    end
                end

                ST_WAIT_RESET_RELEASE: begin
                    link_ready_o <= 1'b0;
                    if (!negotiated_valid ||
                        (negotiated_speed != mac_speed_o)) begin
                        state <= ST_WAIT_LINK;
                    end else if (!mac_reset_active) begin
                        link_ready_o <= 1'b1;
                        state        <= ST_READY;
                    end
                end

                ST_READY: begin
                    if (!negotiated_valid ||
                        (negotiated_speed != mac_speed_o)) begin
                        link_ready_o <= 1'b0;
                        state        <= ST_WAIT_LINK;
                    end
                end

                default: begin
                    state          <= ST_WAIT_LINK;
                    mac_speed_o    <= 2'b10;
                    update_speed_o <= 1'b0;
                    link_ready_o   <= 1'b0;
                end
            endcase
        end
    end

endmodule
