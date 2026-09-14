set project_path [file normalize "D:/MyFPGAProject/UDP/fpga/led/led.xpr"]
set bit_path [file normalize "D:/MyFPGAProject/UDP/fpga/led/led.runs/impl_udp_perf_diag/udp_perf_diag_top.bit"]
set ltx_path [file normalize "D:/MyFPGAProject/UDP/fpga/led/led.runs/impl_udp_perf_diag/udp_perf_diag_top.ltx"]
set data_dir [file normalize "D:/MyFPGAProject/UDP/fpga/led/led.hw/hw_1"]
set capture_base "udp_sequence_reorder_20260914"
set expected_part xc7k325t

foreach {kind path} [list project $project_path bitstream $bit_path probes $ltx_path] {
    if {![file exists $path]} { error "required $kind file is missing: $path" }
}
if {[version -short] ne "2021.1"} {
    error "Vivado version mismatch: expected 2021.1, got [version -short]"
}

open_project $project_path
open_hw_manager
connect_hw_server
set targets [get_hw_targets *]
if {[llength $targets] != 1} {
    error "expected exactly one JTAG target, found [llength $targets]"
}
set target [lindex $targets 0]
open_hw_target $target
set devices [get_hw_devices]
if {[llength $devices] != 1} {
    error "expected exactly one JTAG device, found [llength $devices]"
}
set device [lindex $devices 0]
if {[get_property PART $device] ne $expected_part} {
    error "expected $expected_part, found [get_property PART $device]"
}

set_property PROGRAM.FILE $bit_path $device
set_property PROBES.FILE $ltx_path $device
set_property FULL_PROBES.FILE $ltx_path $device
program_hw_devices $device
refresh_hw_device $device

set ilas [get_hw_ilas -quiet -of_objects $device]
if {[llength $ilas] != 1} {
    error "expected exactly one ILA, found [llength $ilas]"
}
set ila [lindex $ilas 0]
if {[get_property CELL_NAME $ila] ne "sequence_ila_i"} {
    error "unexpected ILA cell: [get_property CELL_NAME $ila]"
}

set trigger_probe ""
foreach candidate [get_hw_probes -of_objects $ila] {
    puts "PROBE=[get_property NAME $candidate] WIDTH=[get_property WIDTH $candidate]"
    if {[get_property WIDTH $candidate] == 1 &&
        [string match "*any_reorder_pulse*" [get_property NAME $candidate]]} {
        set trigger_probe $candidate
    }
}
if {$trigger_probe eq ""} {
    error "one-bit any_reorder_pulse trigger probe was not found"
}

set_property CONTROL.DATA_DEPTH 2048 $ila
set_property CONTROL.TRIGGER_POSITION 256 $ila
set_property CONTROL.TRIGGER_CONDITION AND $ila
set_property TRIGGER_COMPARE_VALUE "eq1'b1" $trigger_probe
run_hw_ila $ila
puts "HW_TARGET=$target"
puts "HW_DEVICE=$device"
puts "PROGRAMMED_BIT=[file normalize [get_property PROGRAM.FILE $device]]"
puts "PROBES_FILE=[file normalize [get_property PROBES.FILE $device]]"
puts "HW_ILA=$ila CELL=[get_property CELL_NAME $ila]"
puts "TRIGGER_PROBE=[get_property NAME $trigger_probe]"
puts "CAPTURE_ARMED=1"
flush stdout

wait_on_hw_ila -timeout 90 $ila
set capture_data [upload_hw_ila_data $ila]
set ila_path "${data_dir}/${capture_base}.ila"
set csv_path "${data_dir}/${capture_base}.csv"
write_hw_ila_data -force $ila_path $capture_data
write_hw_ila_data -force -csv_file $csv_path $capture_data
puts "CAPTURE_ILA=[file normalize $ila_path]"
puts "CAPTURE_CSV=[file normalize $csv_path]"
puts "RESULT=UDP_SEQUENCE_DIAG_CAPTURED"

close_hw_target $target
disconnect_hw_server
close_hw_manager
close_project
exit 0
