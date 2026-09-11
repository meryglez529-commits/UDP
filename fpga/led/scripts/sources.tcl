# Explicit source manifest for the user-created Vivado project.
# Keep every project input in these lists. Do not discover inputs through
# directory globs, so the manifest remains auditable against led.xpr.

proc led_require_file {kind path} {
    if {![file exists $path]} {
        error "required $kind file is missing: $path"
    }
}

proc led_register_file {fileset path} {
    set matches [get_files -quiet $path]
    if {[llength $matches] == 0} {
        add_files -norecurse -fileset $fileset $path
    } elseif {[llength $matches] != 1} {
        error "source is ambiguous in project: $path"
    }
}

proc led_validate_manifest {project_dir} {
    set rtl_files [list \
        [file join $project_dir led.srcs sources_1 new led_static.v] \
        [file join $project_dir led.srcs sources_1 new mdio_clause22_reader.v] \
        [file join $project_dir led.srcs sources_1 new m88e1111_runtime_probe.v] \
        [file join $project_dir led.srcs sources_1 new ad9517_clock_manager.v] \
        [file join $project_dir led.srcs sources_1 new ad9517 ad9517_init_ctrl.v] \
        [file join $project_dir led.srcs sources_1 new ad9517 ad9517_profile_rom.v] \
        [file join $project_dir led.srcs sources_1 new ad9517 ad9517_spi_master.v] \
        [file join $project_dir led.srcs sources_1 new ad9517 pll_ld_sync_and_filter.v] \
        [file join $project_dir led.srcs sources_1 new ethernet ethernet_link_speed_ctrl.v] \
        [file join $project_dir led.srcs sources_1 new ethernet ethernet_link_top.v] \
        [file join $project_dir led.srcs sources_1 new ethernet fixed_host_rx_parser.v] \
        [file join $project_dir led.srcs sources_1 new ethernet udp_rx_message_fifo.v] \
        [file join $project_dir led.srcs sources_1 new ethernet udp_tx_message_buffer.v] \
        [file join $project_dir led.srcs sources_1 new ethernet fixed_host_tx_engine.v] \
        [file join $project_dir led.srcs sources_1 new ethernet udp_transport_stats.v] \
        [file join $project_dir led.srcs sources_1 new ethernet udp_transport_fixed_host.v] \
        [file join $project_dir led.srcs sources_1 new ethernet udp_payload_echo.v] \
        [file join $project_dir led.srcs sources_1 new ethernet temac_sgmii_tri_speed_bram_tdp.v] \
        [file join $project_dir led.srcs sources_1 new ethernet temac_sgmii_tri_speed_config_vector_sm.v] \
        [file join $project_dir led.srcs sources_1 new ethernet temac_sgmii_tri_speed_fifo_block.v] \
        [file join $project_dir led.srcs sources_1 new ethernet temac_sgmii_tri_speed_reset_sync.v] \
        [file join $project_dir led.srcs sources_1 new ethernet temac_sgmii_tri_speed_rx_client_fifo.v] \
        [file join $project_dir led.srcs sources_1 new ethernet temac_sgmii_tri_speed_support.v] \
        [file join $project_dir led.srcs sources_1 new ethernet temac_sgmii_tri_speed_sync_block.v] \
        [file join $project_dir led.srcs sources_1 new ethernet temac_sgmii_tri_speed_ten_100_1g_eth_fifo.v] \
        [file join $project_dir led.srcs sources_1 new ethernet temac_sgmii_tri_speed_tx_client_fifo.v] \
        [file join $project_dir led.srcs sources_1 new udp_top.v] \
        [file join $project_dir led.srcs sources_1 new udp_echo_test_top.v]]
    set ip_files [list \
        [file join $project_dir led.srcs sources_1 ip ila_led ila_led.xci] \
        [file join $project_dir led.srcs sources_1 ip ila_mdio ila_mdio.xci] \
        [file join $project_dir led.srcs sources_1 ip ila_ad9517 ila_ad9517.xci] \
        [file join $project_dir led.srcs sources_1 ip ethernet_clk_wiz_200m ethernet_clk_wiz_200m.xci] \
        [file join $project_dir led.srcs sources_1 ip pcs_pma_sgmii_gtx pcs_pma_sgmii_gtx.xci] \
        [file join $project_dir led.srcs sources_1 ip temac_sgmii_tri_speed temac_sgmii_tri_speed.xci]]
    set xdc_files [list \
        [file join $project_dir led.srcs constrs_1 new led_static.xdc] \
        [file join $project_dir led.srcs constrs_1 new ad9517_clock_manager.xdc] \
        [file join $project_dir led.srcs constrs_1 new udp_top.xdc]]
    set sim_files [list \
        [file join $project_dir led.srcs sim_1 new led_static_tb.v] \
        [file join $project_dir led.srcs sim_1 new mdio_clause22_model.v] \
        [file join $project_dir led.srcs sim_1 new ad9517_model.v] \
        [file join $project_dir led.srcs sim_1 new ad9517_clock_manager_tb.v] \
        [file join $project_dir led.srcs sim_1 new ethernet_clk_wiz_200m_tb.v] \
        [file join $project_dir led.srcs sim_1 new ethernet_link_speed_ctrl_tb.v] \
        [file join $project_dir led.srcs sim_1 new udp_transport_fixed_host_tb.v] \
        [file join $project_dir led.srcs sim_1 new udp_payload_echo_tb.v]]

    foreach path $rtl_files { led_require_file RTL $path }
    foreach path $ip_files { led_require_file IP $path }
    foreach path $xdc_files { led_require_file XDC $path }
    foreach path $sim_files { led_require_file simulation $path }
    return [list $rtl_files $ip_files $xdc_files $sim_files]
}

proc led_register_manifest {project_dir} {
    lassign [led_validate_manifest $project_dir] rtl_files ip_files xdc_files sim_files
    foreach path $rtl_files { led_register_file sources_1 $path }
    foreach path $ip_files { led_register_file sources_1 $path }
    foreach path $xdc_files { led_register_file constrs_1 $path }
    foreach path $sim_files { led_register_file sim_1 $path }
}
