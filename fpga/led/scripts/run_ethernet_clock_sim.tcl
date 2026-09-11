set project_path "D:/MyFPGAProject/UDP/fpga/led/led.xpr"

open_project $project_path
set prior_sim_top [get_property top [get_filesets sim_1]]
set_property top ethernet_clk_wiz_200m_tb [get_filesets sim_1]
update_compile_order -fileset sim_1

set sim_status [catch {
    launch_simulation -mode behavioral -simset sim_1
    run all
    close_sim
} sim_result sim_options]

set_property top $prior_sim_top [get_filesets sim_1]
puts "RESTORED_SIM_TOP=[get_property top [get_filesets sim_1]]"
close_project

if {$sim_status} {
    return -options $sim_options $sim_result
}
puts "RESULT=ETHERNET_CLOCK_SIM_PASSED"
