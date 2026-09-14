set project_path "D:/MyFPGAProject/UDP/fpga/led/led.xpr"
set project_root "D:/MyFPGAProject/UDP/fpga/led"

open_project $project_path
source "$project_root/scripts/sources.tcl"
led_register_manifest $project_root
set prior_sim_top [get_property top [get_filesets sim_1]]

set tests [list \
    udp_rx_payload_ring_tb RESULT=UDP_RX_PAYLOAD_RING_PASSED \
    udp_tx_payload_ring_tb RESULT=UDP_TX_PAYLOAD_RING_PASSED]

set sim_status [catch {
    foreach {test_top pass_marker} $tests {
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
        if {[string first $pass_marker $sim_text] < 0} {
            error "$test_top did not report PASS; inspect $sim_log"
        }
        puts "TEST_PASSED=$test_top"
    }
} sim_result sim_options]

set_property top $prior_sim_top [get_filesets sim_1]
puts "RESTORED_SIM_TOP=[get_property top [get_filesets sim_1]]"
close_project

if {$sim_status} {
    return -options $sim_options $sim_result
}
puts "RESULT=UDP_PAYLOAD_RING_SIM_PASSED"
