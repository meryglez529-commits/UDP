set expected_vivado_version "2021.1"
set project_path "D:/MyFPGAProject/UDP/fpga/led/led.xpr"
set project_root "D:/MyFPGAProject/UDP/fpga/led"

if {[version -short] ne $expected_vivado_version} {
    error "Vivado version mismatch: expected $expected_vivado_version, got [version -short]"
}

open_project $project_path

set prior_design_top [get_property top [get_filesets sources_1]]
set prior_sim_top [get_property top [get_filesets sim_1]]
set udp_xdc "$project_root/led.srcs/constrs_1/new/udp_top.xdc"
set prior_udp_xdc_enabled [get_property IS_ENABLED [get_files $udp_xdc]]

source "$project_root/scripts/sources.tcl"
led_register_manifest $project_root

# Source registration must not change the user's active design/simulation top
# or the current board-level constraint selection.
set_property IS_ENABLED $prior_udp_xdc_enabled [get_files $udp_xdc]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
set_property top $prior_design_top [get_filesets sources_1]
set_property top $prior_sim_top [get_filesets sim_1]

puts "PROJECT=$project_path"
puts "DESIGN_TOP=[get_property top [get_filesets sources_1]]"
puts "SIM_TOP=[get_property top [get_filesets sim_1]]"
puts "RESULT=ETHERNET_LINK_SOURCES_REGISTERED"
close_project
