set project_path "D:/MyFPGAProject/UDP/fpga/led/led.xpr"
set project_root "D:/MyFPGAProject/UDP/fpga/led"

open_project $project_path
source "$project_root/scripts/sources.tcl"
led_register_manifest $project_root
set prior_sim_top [get_property top [get_filesets sim_1]]
set_property top udp_transport_fixed_host_tb [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

set sim_status [catch {
    launch_simulation -mode behavioral -simset sim_1
    run all
    close_sim

    set sim_log "$project_root/led.sim/sim_1/behav/xsim/simulate.log"
    set sim_fd [open $sim_log r]
    set sim_text [read $sim_fd]
    close $sim_fd
    if {[string first "RESULT=UDP_TRANSPORT_FIXED_HOST_PASSED" $sim_text] < 0} {
        error "UDP transport testbench did not report PASS; inspect $sim_log"
    }
} sim_result sim_options]

set_property top $prior_sim_top [get_filesets sim_1]
puts "RESTORED_SIM_TOP=[get_property top [get_filesets sim_1]]"
close_project

if {$sim_status} {
    return -options $sim_options $sim_result
}
puts "RESULT=UDP_TRANSPORT_SIM_PASSED"
