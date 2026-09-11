set script_dir [file dirname [file normalize [info script]]]
set example_root [file normalize [file join $script_dir ..]]
set seed_dir [file join $example_root work pcs_pma_sgmii_seed]
set generated_dir [file join $example_root generated pcs_pma_sgmii]

file mkdir $seed_dir
file mkdir $generated_dir
create_project -force pcs_pma_sgmii_seed $seed_dir -part xc7k325tffg676-2

create_ip -name gig_ethernet_pcs_pma -vendor xilinx.com -library ip \
    -version 16.2 -module_name pcs_pma_sgmii_gtx

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
    CONFIG.SupportLevel {Include_Shared_Logic_in_Example_Design} \
] [get_ips pcs_pma_sgmii_gtx]

puts "===== PCS_PMA_SELECTED_CONFIG ====="
foreach property_name {
    CONFIG.Standard
    CONFIG.Physical_Interface
    CONFIG.MaxDataRate
    CONFIG.RefClkRate
    CONFIG.RefClkSrc
    CONFIG.GT_Location
    CONFIG.NumOfLanes
    CONFIG.EMAC_IF_TEMAC
    CONFIG.SGMII_PHY_Mode
    CONFIG.SGMII_Mode
    CONFIG.Auto_Negotiation
    CONFIG.SupportLevel
} {
    puts "$property_name=[get_property $property_name [get_ips pcs_pma_sgmii_gtx]]"
}

generate_target all [get_ips pcs_pma_sgmii_gtx]
open_example_project -force -dir $generated_dir [get_ips pcs_pma_sgmii_gtx]
puts "PCS_PMA_EXAMPLE_PROJECT=[file join $generated_dir pcs_pma_sgmii_gtx_ex pcs_pma_sgmii_gtx_ex.xpr]"
puts "PCS_PMA_EXAMPLE_DIRECTORY=$generated_dir"
close_project
exit
