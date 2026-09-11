set script_dir [file dirname [file normalize [info script]]]
set example_root [file normalize [file join $script_dir ..]]
set seed_dir [file join $example_root work temac_sgmii_seed]
set generated_dir [file join $example_root generated temac_sgmii]

file mkdir $seed_dir
file mkdir $generated_dir
create_project -force temac_sgmii_seed $seed_dir -part xc7k325tffg676-2

create_ip -name tri_mode_ethernet_mac -vendor xilinx.com -library ip \
    -version 9.0 -module_name temac_sgmii_tri_speed

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

puts "===== TEMAC_SELECTED_CONFIG ====="
foreach property_name {
    CONFIG.Physical_Interface
    CONFIG.Int_Mode_Type
    CONFIG.MAC_Speed
    CONFIG.Int_Clk_Src
    CONFIG.Management_Interface
    CONFIG.Enable_MDIO
    CONFIG.Frame_Filter
    CONFIG.Statistics_Counters
} {
    puts "$property_name=[get_property $property_name [get_ips temac_sgmii_tri_speed]]"
}

generate_target all [get_ips temac_sgmii_tri_speed]
open_example_project -force -dir $generated_dir [get_ips temac_sgmii_tri_speed]
puts "TEMAC_EXAMPLE_PROJECT=[file join $generated_dir temac_sgmii_tri_speed_ex temac_sgmii_tri_speed_ex.xpr]"
puts "TEMAC_EXAMPLE_DIRECTORY=$generated_dir"
close_project
exit
