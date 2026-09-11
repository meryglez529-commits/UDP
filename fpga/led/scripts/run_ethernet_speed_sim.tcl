set project_path "D:/MyFPGAProject/UDP/fpga/led/led.xpr"

open_project $project_path
set prior_sim_top [get_property top [get_filesets sim_1]]
set_property top ethernet_link_speed_ctrl_tb [get_filesets sim_1]
update_compile_order -fileset sim_1

launch_simulation -mode behavioral -simset sim_1
run all
close_sim

set_property top $prior_sim_top [get_filesets sim_1]
puts "RESULT=ETHERNET_SPEED_SIM_PASSED"
puts "RESTORED_SIM_TOP=[get_property top [get_filesets sim_1]]"
close_project
