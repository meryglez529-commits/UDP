# Register the AD9517-only RTL and simulation inputs in the existing led.xpr.
# This script never creates a second project and never creates Ethernet/GT IP.
set expected_vivado_version "2021.1"
set project_path "D:/MyFPGAProject/UDP/fpga/led/led.xpr"
set project_root "D:/MyFPGAProject/UDP/fpga/led"

if {[version -short] ne $expected_vivado_version} {
    error "Vivado version mismatch: expected $expected_vivado_version, got [version -short]"
}

open_project $project_path
source "$project_root/scripts/sources.tcl"
led_register_manifest $project_root

# Preserve the former LED/MDIO constraint file in the project, but disable it
# for this new board-level top.  The AD9517-specific file is the active XDC.
set old_xdc "$project_root/led.srcs/constrs_1/new/led_static.xdc"
set new_xdc "$project_root/led.srcs/constrs_1/new/ad9517_clock_manager.xdc"
set_property IS_ENABLED false [get_files $old_xdc]
set_property IS_ENABLED true  [get_files $new_xdc]

set_property top ad9517_clock_manager [get_filesets sources_1]
set_property top ad9517_clock_manager_tb [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Vivado persists add_files and fileset properties in the already-open project;
# close_project completes the in-place update.  save_project_as must not target
# the same .xpr because Vivado 2021.1 rejects that as "already open".
puts "PROJECT=$project_path"
puts "DESIGN_TOP=[get_property top [get_filesets sources_1]]"
puts "SIM_TOP=[get_property top [get_filesets sim_1]]"
puts "RESULT=AD9517_SOURCES_REGISTERED"
close_project
