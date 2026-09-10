# Rebuild the existing implementation runs after the approved MDIO/ILA change.
set project_path "D:/MyFPGAProject/UDP/fpga/led/led.xpr"
set project_root "D:/MyFPGAProject/UDP/fpga/led"
open_project $project_path

reset_run synth_1
launch_runs synth_1 -jobs 2
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "synth_1 did not complete: [get_property STATUS [get_runs synth_1]]"
}

launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    error "impl_1 did not complete: [get_property STATUS [get_runs impl_1]]"
}

open_run impl_1
report_timing_summary -file "$project_root/led.runs/impl_1/mdio_timing_summary.rpt"
report_drc -file "$project_root/led.runs/impl_1/mdio_drc.rpt"
close_project
