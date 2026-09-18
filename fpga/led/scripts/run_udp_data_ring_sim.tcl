set project_path "D:/MyFPGAProject/UDP/fpga/led/led.xpr"
set project_root "D:/MyFPGAProject/UDP/fpga/led"
open_project $project_path
source "$project_root/scripts/sources.tcl"
led_register_manifest $project_root
set prior_top [get_property top [get_filesets sim_1]]
set_property top udp_data_ring_tb [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation -mode behavioral -simset sim_1
run all
close_sim
set sim_log "$project_root/led.sim/sim_1/behav/xsim/simulate.log"
set fd [open $sim_log r]
set log_text [read $fd]
close $fd
set_property top $prior_top [get_filesets sim_1]
update_compile_order -fileset sim_1
close_project
if {[string first "RESULT=UDP_DATA_RING_PASSED" $log_text] < 0} {
    error "DATA ring simulation failed; inspect $sim_log"
}
puts "RESULT=UDP_DATA_RING_SIM_PASSED"
exit 0
