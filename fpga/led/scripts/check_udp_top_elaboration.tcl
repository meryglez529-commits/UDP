set project_path "D:/MyFPGAProject/UDP/fpga/led/led.xpr"

open_project $project_path
set prior_sim_top [get_property top [get_filesets sim_1]]
set_property top udp_top [get_filesets sim_1]
update_compile_order -fileset sim_1

set check_status [catch {
    launch_simulation -mode behavioral -simset sim_1
    run 1 ns
    close_sim
} check_result check_options]

set_property top $prior_sim_top [get_filesets sim_1]
puts "RESTORED_SIM_TOP=[get_property top [get_filesets sim_1]]"
close_project

if {$check_status} {
    return -options $check_options $check_result
}
puts "RESULT=UDP_TOP_ELABORATION_PASSED"
