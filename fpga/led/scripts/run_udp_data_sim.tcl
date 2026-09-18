set project_path "D:/MyFPGAProject/UDP/fpga/led/led.xpr"
set project_root "D:/MyFPGAProject/UDP/fpga/led"
set tests [list \
    [list udp_data_ring_tb RESULT=UDP_DATA_RING_PASSED] \
    [list udp_transport_dual_host_tb RESULT=UDP_TRANSPORT_DUAL_HOST_PASSED]]
open_project $project_path
source "$project_root/scripts/sources.tcl"
led_register_manifest $project_root
set prior_top [get_property top [get_filesets sim_1]]
set failed 0
foreach test $tests {
    lassign $test top marker
    set_property top $top [get_filesets sim_1]
    update_compile_order -fileset sources_1
    update_compile_order -fileset sim_1
    launch_simulation -mode behavioral -simset sim_1
    run all
    close_sim
    set sim_log "$project_root/led.sim/sim_1/behav/xsim/simulate.log"
    set fd [open $sim_log r]; set text [read $fd]; close $fd
    if {[string first $marker $text] < 0} { set failed 1; puts "FAILED_TOP=$top" }
}
set_property top $prior_top [get_filesets sim_1]
update_compile_order -fileset sim_1
close_project
if {$failed} { error "DATA simulation failed" }
puts "RESULT=UDP_DATA_SIM_PASSED"
exit 0
