`timescale 1ns / 1ps

// Reusable DB500 Ethernet link layer.
//
// This module owns the PCS/PMA + TEMAC clock/reset boundary and exposes a
// fixed 125 MHz AXI4-Stream frame interface.  It intentionally stops at
// Ethernet frames; ARP, IPv4, UDP and application protocol logic live above
// this boundary.
module ethernet_link_top (
    input  wire        reset_i,
    input  wire        clock_ready_i,
    input  wire        system_clock_100m_i,

    input  wire        gtrefclk_p_i,
    input  wire        gtrefclk_n_i,
    output wire        sgmii_txp_o,
    output wire        sgmii_txn_o,
    input  wire        sgmii_rxp_i,
    input  wire        sgmii_rxn_i,

    output wire        user_clk_o,
    output wire        user_resetn_o,
    output wire        clock_200m_locked_o,
    output wire        link_ready_o,
    output wire [1:0]  link_speed_o,
    output wire [15:0] pcs_status_o,

    output wire [7:0]  rx_axis_tdata_o,
    output wire        rx_axis_tvalid_o,
    input  wire        rx_axis_tready_i,
    output wire        rx_axis_tlast_o,

    input  wire [7:0]  tx_axis_tdata_i,
    input  wire        tx_axis_tvalid_i,
    output wire        tx_axis_tready_o,
    input  wire        tx_axis_tlast_i
);

    wire independent_clock_bufg;
    wire independent_clock_locked;

    // This Clocking Wizard owns both the MMCM and output BUFG.  Its 200 MHz
    // output is deliberately independent of the 125 MHz MGT reference clock.
    ethernet_clk_wiz_200m independent_clock_i (
        .clk_out1 (independent_clock_bufg),
        .reset    (reset_i),
        .locked   (independent_clock_locked),
        .clk_in1  (system_clock_100m_i)
    );

    // Assert immediately if either clock prerequisite disappears; release in
    // the free-running 200 MHz domain so PCS/PMA reset deassertion is clean.
    wire pcs_reset_async = reset_i ||
                           !clock_ready_i ||
                           !independent_clock_locked;
    // Reset synchronizer: asynchronous assertion, synchronous release.
    // Keep the stages colocated and prevent SRL extraction, matching the
    // reset structures used by the AMD PCS/PMA and TEMAC example designs.
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [3:0] pcs_reset_pipe;

    always @(posedge independent_clock_bufg or posedge pcs_reset_async) begin
        if (pcs_reset_async)
            pcs_reset_pipe <= 4'b1111;
        else
            pcs_reset_pipe <= {pcs_reset_pipe[2:0], 1'b0};
    end

    wire pcs_reset = pcs_reset_pipe[3];

    wire        userclk;
    wire        userclk2;
    wire        rxuserclk;
    wire        rxuserclk2;
    wire        pcs_resetdone;
    wire        pcs_pma_reset;
    wire        pcs_mmcm_locked;
    wire        gtrefclk_out;
    wire        gtrefclk_bufg_out;
    wire        sgmii_clk_r;
    wire        sgmii_clk_f;
    wire        sgmii_clk_en;
    wire        gmii_isolate;
    wire        an_interrupt;
    wire [15:0] pcs_status;
    wire        gt0_qplloutclk;
    wire        gt0_qplloutrefclk;

    wire [7:0] gmii_txd;
    wire       gmii_tx_en;
    wire       gmii_tx_er;
    wire [7:0] gmii_rxd;
    wire       gmii_rx_dv;
    wire       gmii_rx_er;
    wire       speed_is_10_100;
    wire       speed_is_100;

    // Management is intentionally disabled in this PCS/PMA instance.  The
    // board-level M88E1111 MDIO pins remain owned by the existing PHY manager.
    // 5'b10000 enables SGMII auto-negotiation through Configuration Vector.
    pcs_pma_sgmii_gtx pcs_pma_i (
        .gtrefclk_p              (gtrefclk_p_i),
        .gtrefclk_n              (gtrefclk_n_i),
        .gtrefclk_out            (gtrefclk_out),
        .gtrefclk_bufg_out       (gtrefclk_bufg_out),
        .txn                     (sgmii_txn_o),
        .txp                     (sgmii_txp_o),
        .rxn                     (sgmii_rxn_i),
        .rxp                     (sgmii_rxp_i),
        .independent_clock_bufg  (independent_clock_bufg),
        .userclk_out             (userclk),
        .userclk2_out            (userclk2),
        .rxuserclk_out           (rxuserclk),
        .rxuserclk2_out          (rxuserclk2),
        .resetdone               (pcs_resetdone),
        .pma_reset_out           (pcs_pma_reset),
        .mmcm_locked_out         (pcs_mmcm_locked),
        .sgmii_clk_r             (sgmii_clk_r),
        .sgmii_clk_f             (sgmii_clk_f),
        .sgmii_clk_en            (sgmii_clk_en),
        .gmii_txd                (gmii_txd),
        .gmii_tx_en              (gmii_tx_en),
        .gmii_tx_er              (gmii_tx_er),
        .gmii_rxd                (gmii_rxd),
        .gmii_rx_dv              (gmii_rx_dv),
        .gmii_rx_er              (gmii_rx_er),
        .gmii_isolate            (gmii_isolate),
        .configuration_vector    (5'b10000),
        .an_interrupt            (an_interrupt),
        .an_adv_config_vector    (16'b0),
        .an_restart_config       (1'b0),
        .speed_is_10_100         (speed_is_10_100),
        .speed_is_100            (speed_is_100),
        .status_vector           (pcs_status),
        .reset                   (pcs_reset),
        .signal_detect           (1'b1),
        .gt0_qplloutclk_out      (gt0_qplloutclk),
        .gt0_qplloutrefclk_out   (gt0_qplloutrefclk)
    );

    // Asynchronously assert when any PCS clock prerequisite disappears, then
    // release synchronously in the 125 MHz userclk2 domain.
    wire mac_reset_async = pcs_reset || !pcs_resetdone || !pcs_mmcm_locked;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [3:0] mac_reset_pipe;

    always @(posedge userclk2 or posedge mac_reset_async) begin
        if (mac_reset_async)
            mac_reset_pipe <= 4'b1111;
        else
            mac_reset_pipe <= {mac_reset_pipe[2:0], 1'b0};
    end

    wire mac_resetn = !mac_reset_pipe[3];

    wire [1:0] mac_speed;
    wire       update_speed;
    wire       link_ready;
    wire       mac_rx_reset;
    wire       mac_tx_reset;

    ethernet_link_speed_ctrl speed_ctrl_i (
        .clk_i           (userclk2),
        .resetn_i        (mac_resetn),
        .core_ready_i    (independent_clock_locked &&
                          pcs_resetdone && pcs_mmcm_locked),
        .pcs_status_i    (pcs_status),
        .mac_rx_reset_i  (mac_rx_reset),
        .mac_tx_reset_i  (mac_tx_reset),
        .mac_speed_o     (mac_speed),
        .update_speed_o  (update_speed),
        .link_ready_o    (link_ready)
    );

    wire [79:0] rx_configuration_vector;
    wire [79:0] tx_configuration_vector;

    temac_sgmii_tri_speed_config_vector_sm config_vector_i (
        .gtx_clk                 (userclk2),
        .gtx_resetn              (mac_resetn),
        .mac_speed               (mac_speed),
        .update_speed            (update_speed),
        .rx_configuration_vector (rx_configuration_vector),
        .tx_configuration_vector (tx_configuration_vector)
    );

    wire [7:0] rx_axis_fifo_tdata;
    wire       rx_axis_fifo_tvalid;
    wire       rx_axis_fifo_tready;
    wire       rx_axis_fifo_tlast;
    wire [7:0] tx_axis_fifo_tdata;
    wire       tx_axis_fifo_tvalid;
    wire       tx_axis_fifo_tready;
    wire       tx_axis_fifo_tlast;
    wire       fifo_resetn = mac_resetn && link_ready;

    wire [27:0] rx_statistics_vector;
    wire        rx_statistics_valid;
    wire [31:0] tx_statistics_vector;
    wire        tx_statistics_valid;
    wire        rx_mac_aclk;
    wire        tx_mac_aclk;

    temac_sgmii_tri_speed_fifo_block mac_fifo_i (
        .gtx_clk                 (userclk2),
        .glbl_rstn               (mac_resetn),
        .rx_axi_rstn             (1'b1),
        .tx_axi_rstn             (1'b1),
        .rx_mac_aclk             (rx_mac_aclk),
        .rx_reset                (mac_rx_reset),
        .rx_statistics_vector    (rx_statistics_vector),
        .rx_statistics_valid     (rx_statistics_valid),
        .rx_fifo_clock           (userclk2),
        .rx_fifo_resetn          (fifo_resetn),
        .rx_axis_fifo_tdata      (rx_axis_fifo_tdata),
        .rx_axis_fifo_tvalid     (rx_axis_fifo_tvalid),
        .rx_axis_fifo_tready     (rx_axis_fifo_tready),
        .rx_axis_fifo_tlast      (rx_axis_fifo_tlast),
        .tx_mac_aclk             (tx_mac_aclk),
        .tx_reset                (mac_tx_reset),
        .tx_ifg_delay            (8'd0),
        .tx_statistics_vector    (tx_statistics_vector),
        .tx_statistics_valid     (tx_statistics_valid),
        .tx_fifo_clock           (userclk2),
        .tx_fifo_resetn          (fifo_resetn),
        .tx_axis_fifo_tdata      (tx_axis_fifo_tdata),
        .tx_axis_fifo_tvalid     (tx_axis_fifo_tvalid),
        .tx_axis_fifo_tready     (tx_axis_fifo_tready),
        .tx_axis_fifo_tlast      (tx_axis_fifo_tlast),
        .pause_req               (1'b0),
        .pause_val               (16'd0),
        .gmii_txd                (gmii_txd),
        .gmii_tx_en              (gmii_tx_en),
        .gmii_tx_er              (gmii_tx_er),
        .gmii_rxd                (gmii_rxd),
        .gmii_rx_dv              (gmii_rx_dv),
        .gmii_rx_er              (gmii_rx_er),
        .clk_enable              (sgmii_clk_en),
        .speedis100              (speed_is_100),
        .speedis10100            (speed_is_10_100),
        .rx_configuration_vector (rx_configuration_vector),
        .tx_configuration_vector (tx_configuration_vector)
    );

    assign rx_axis_fifo_tready = rx_axis_tready_i && link_ready;
    assign tx_axis_fifo_tdata  = tx_axis_tdata_i;
    assign tx_axis_fifo_tvalid = tx_axis_tvalid_i && link_ready;
    assign tx_axis_fifo_tlast  = tx_axis_tlast_i;

    assign user_clk_o        = userclk2;
    assign user_resetn_o     = mac_resetn;
    assign clock_200m_locked_o = independent_clock_locked;
    assign link_ready_o      = link_ready;
    assign link_speed_o      = mac_speed;
    assign pcs_status_o      = pcs_status;
    assign rx_axis_tdata_o   = rx_axis_fifo_tdata;
    assign rx_axis_tvalid_o  = rx_axis_fifo_tvalid && link_ready;
    assign rx_axis_tlast_o   = rx_axis_fifo_tlast;
    assign tx_axis_tready_o  = tx_axis_fifo_tready && link_ready;

endmodule
