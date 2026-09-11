# Volatile JTAG programming for the licensed UDP echo hardware image.
# This design intentionally contains no ILA/VIO debug cores, so any probes
# association left by an earlier Hardware Manager session is cleared.
set project_path [file normalize "D:/MyFPGAProject/UDP/fpga/led/led.xpr"]
set bit_path     [file normalize "D:/MyFPGAProject/UDP/fpga/led/led.runs/impl_udp_echo/udp_echo_test_top.bit"]
set expected_part xc7k325t

foreach {kind path} [list project $project_path bitstream $bit_path] {
    if {![file exists $path]} {
        error "required $kind file is missing: $path"
    }
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
set actual_part [get_property PART $device]
if {$actual_part ne $expected_part} {
    error "expected $expected_part, found $actual_part"
}

set_property PROGRAM.FILE $bit_path $device
foreach property {PROBES.FILE FULL_PROBES.FILE} {
    if {[lsearch -exact [list_property $device] $property] >= 0} {
        set_property $property {} $device
    }
}
if {[file normalize [get_property PROGRAM.FILE $device]] ne $bit_path} {
    error "PROGRAM.FILE readback does not match requested bitstream"
}

program_hw_devices $device
refresh_hw_device $device

set programmed_bit [file normalize [get_property PROGRAM.FILE $device]]
if {$programmed_bit ne $bit_path} {
    error "programmed bitstream identity mismatch: $programmed_bit"
}
set ila_count [llength [get_hw_ilas -quiet -of_objects $device]]
set vio_count [llength [get_hw_vios -quiet -of_objects $device]]

puts "PROJECT=$project_path"
puts "HW_TARGET=$target"
puts "HW_DEVICE=$device"
puts "HW_PART=$actual_part"
puts "PROGRAMMED_BIT=$programmed_bit"
puts "HW_ILA_COUNT=$ila_count"
puts "HW_VIO_COUNT=$vio_count"
puts "RESULT=UDP_ECHO_PROGRAM_PASSED"

close_hw_target $target
disconnect_hw_server
close_hw_manager
close_project
exit 0
