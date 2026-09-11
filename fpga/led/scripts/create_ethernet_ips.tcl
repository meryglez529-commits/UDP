set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set project_path [file join $project_dir led.xpr]

open_project $project_path

if {[llength [get_ips -quiet pcs_pma_sgmii_gtx]] == 0} {
    create_ip -name gig_ethernet_pcs_pma -vendor xilinx.com -library ip \
        -version 16.2 -module_name pcs_pma_sgmii_gtx
}

set_property -dict [list \
    CONFIG.Standard {SGMII} \
    CONFIG.Physical_Interface {Transceiver} \
    CONFIG.MaxDataRate {1G} \
    CONFIG.RefClkRate {125} \
    CONFIG.RefClkSrc {clk0} \
    CONFIG.GT_Location {X0Y0} \
    CONFIG.NumOfLanes {1} \
    CONFIG.EMAC_IF_TEMAC {TEMAC} \
    CONFIG.SGMII_PHY_Mode {false} \
    CONFIG.SGMII_Mode {10_100_1000} \
    CONFIG.Auto_Negotiation {true} \
    CONFIG.Management_Interface {false} \
    CONFIG.SupportLevel {Include_Shared_Logic_in_Core} \
] [get_ips pcs_pma_sgmii_gtx]

if {[llength [get_ips -quiet temac_sgmii_tri_speed]] == 0} {
    create_ip -name tri_mode_ethernet_mac -vendor xilinx.com -library ip \
        -version 9.0 -module_name temac_sgmii_tri_speed
}

set_property -dict [list \
    CONFIG.Physical_Interface {Internal} \
    CONFIG.Int_Mode_Type {SGMII} \
    CONFIG.MAC_Speed {Tri_speed} \
    CONFIG.Int_Clk_Src {user_clk2} \
    CONFIG.Management_Interface {false} \
    CONFIG.Enable_MDIO {false} \
    CONFIG.Frame_Filter {false} \
    CONFIG.Statistics_Counters {false} \
] [get_ips temac_sgmii_tri_speed]

if {[llength [get_ips -quiet ethernet_clk_wiz_200m]] == 0} {
    create_ip -name clk_wiz -vendor xilinx.com -library ip \
        -version 6.0 -module_name ethernet_clk_wiz_200m
}

set_property -dict [list \
    CONFIG.PRIM_SOURCE {No_buffer} \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {200.000} \
    CONFIG.CLKOUT1_DRIVES {BUFG} \
    CONFIG.USE_LOCKED {true} \
    CONFIG.USE_RESET {true} \
    CONFIG.RESET_TYPE {ACTIVE_HIGH} \
] [get_ips ethernet_clk_wiz_200m]

generate_target all [get_ips pcs_pma_sgmii_gtx]
generate_target all [get_ips temac_sgmii_tri_speed]
generate_target all [get_ips ethernet_clk_wiz_200m]
export_ip_user_files -of_objects [get_ips {pcs_pma_sgmii_gtx temac_sgmii_tri_speed ethernet_clk_wiz_200m}] \
    -no_script -sync -force -quiet

update_compile_order -fileset sources_1

puts "PCS_PMA_XCI=[get_property IP_FILE [get_ips pcs_pma_sgmii_gtx]]"
puts "TEMAC_XCI=[get_property IP_FILE [get_ips temac_sgmii_tri_speed]]"
puts "CLOCK_WIZARD_XCI=[get_property IP_FILE [get_ips ethernet_clk_wiz_200m]]"
puts "ACTIVE_TOP=[get_property top [current_fileset]]"

close_project
exit
