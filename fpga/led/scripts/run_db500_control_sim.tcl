set project_path "D:/MyFPGAProject/UDP/fpga/led/led.xpr"
set project_root "D:/MyFPGAProject/UDP/fpga/led"
set test_cases [list \
    [list db500_udp_control_tb RESULT=DB500_UDP_CONTROL_PASSED] \
    [list db500_ctrl_watchdog_tb RESULT=DB500_CTRL_WATCHDOG_PASSED] \
    [list db500_ctrl_watchdog_integration_tb RESULT=DB500_CTRL_WATCHDOG_INTEGRATION_PASSED]]

open_project $project_path
source "$project_root/scripts/sources.tcl"
led_register_manifest $project_root
set prior_sim_top [get_property top [get_filesets sim_1]]

set sim_status [catch {
    foreach test_case $test_cases {
        lassign $test_case test_top expected_marker
        set_property top $test_top [get_filesets sim_1]
        update_compile_order -fileset sources_1
        update_compile_order -fileset sim_1
        launch_simulation -mode behavioral -simset sim_1
        run all
        close_sim

        set sim_log "$project_root/led.sim/sim_1/behav/xsim/simulate.log"
        set sim_fd [open $sim_log r]
        set sim_text [read $sim_fd]
        close $sim_fd
        if {[string first $expected_marker $sim_text] < 0} {
            error "$test_top did not report PASS; inspect $sim_log"
        }
        puts "TEST_TOP=$test_top"
        puts "$expected_marker"
    }
} sim_result sim_options]

set_property top $prior_sim_top [get_filesets sim_1]
update_compile_order -fileset sim_1
puts "RESTORED_SIM_TOP=[get_property top [get_filesets sim_1]]"
close_project

if {$sim_status} {
    return -options $sim_options $sim_result
}
puts "RESULT=DB500_CONTROL_SIM_PASSED"
exit 0
