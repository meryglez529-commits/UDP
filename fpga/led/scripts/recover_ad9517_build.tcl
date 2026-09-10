# Recover only the AD9517 implementation run after an interrupted batch job.
# Use this helper only after the corresponding Vivado worker process has been
# confirmed absent at the operating-system level.
open_project "D:/MyFPGAProject/UDP/fpga/led/led.xpr"
set impl_status [get_property STATUS [get_runs impl_1]]
puts "IMPL_STATUS_BEFORE_RECOVERY=$impl_status"
reset_run impl_1
puts "IMPL_STATUS_AFTER_RECOVERY=[get_property STATUS [get_runs impl_1]]"
close_project
exit 0
