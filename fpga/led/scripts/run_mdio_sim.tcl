# Run the approved self-checking MDIO behavioral simulation in led.xpr.
set project_path "D:/MyFPGAProject/UDP/fpga/led/led.xpr"
open_project $project_path
set_property top led_static_tb [get_filesets sim_1]
launch_simulation -mode behavioral -simset sim_1
run 1 ms
close_sim
close_project
