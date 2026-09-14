set project_path [file normalize "D:/MyFPGAProject/UDP/fpga/led/led.xpr"]
set ltx_path [file normalize "D:/MyFPGAProject/UDP/fpga/led/led.runs/impl_udp_perf_diag/udp_perf_diag_top.ltx"]
set data_dir [file normalize "D:/MyFPGAProject/UDP/fpga/led/led.hw/hw_1"]
set capture_base "udp_sequence_reorder_20260914"

open_project $project_path
open_hw_manager
connect_hw_server
set targets [get_hw_targets *]
if {[llength $targets] != 1} { error "expected exactly one JTAG target" }
set target [lindex $targets 0]
open_hw_target $target
set devices [get_hw_devices]
if {[llength $devices] != 1} { error "expected exactly one JTAG device" }
set device [lindex $devices 0]
set_property PROBES.FILE $ltx_path $device
set_property FULL_PROBES.FILE $ltx_path $device
refresh_hw_device $device
set ilas [get_hw_ilas -quiet -of_objects $device]
if {[llength $ilas] != 1} { error "expected exactly one ILA" }
set ila [lindex $ilas 0]

set capture_data [upload_hw_ila_data $ila]
set ila_path "${data_dir}/${capture_base}.ila"
set csv_path "${data_dir}/${capture_base}.csv"
write_hw_ila_data -force $ila_path $capture_data
write_hw_ila_data -force -csv_file $csv_path $capture_data
puts "CAPTURE_ILA=[file normalize $ila_path]"
puts "CAPTURE_CSV=[file normalize $csv_path]"
puts "RESULT=UDP_SEQUENCE_DIAG_UPLOADED"

close_hw_target $target
disconnect_hw_server
close_hw_manager
close_project
exit 0
