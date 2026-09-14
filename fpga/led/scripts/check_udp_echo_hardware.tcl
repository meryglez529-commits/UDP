# Read-only JTAG inventory for the UDP echo test setup.
set project_path [file normalize "D:/MyFPGAProject/UDP/fpga/led/led.xpr"]
set expected_part xc7k325t

if {![file exists $project_path]} {
    error "required project is missing: $project_path"
}
if {[version -short] ne "2021.1"} {
    error "Vivado version mismatch: expected 2021.1, got [version -short]"
}

open_project $project_path
open_hw_manager
connect_hw_server

set targets [get_hw_targets *]
puts "HW_TARGET_COUNT=[llength $targets]"
foreach target $targets {
    puts "HW_TARGET=$target"
}
if {[llength $targets] != 1} {
    error "expected exactly one JTAG target, found [llength $targets]"
}

set target [lindex $targets 0]
open_hw_target $target
set devices [get_hw_devices]
puts "HW_DEVICE_COUNT=[llength $devices]"
foreach device $devices {
    puts "HW_DEVICE=$device PART=[get_property PART $device] PROGRAM_FILE=[get_property PROGRAM.FILE $device]"
}
if {[llength $devices] != 1} {
    error "expected exactly one JTAG device, found [llength $devices]"
}
set device [lindex $devices 0]
if {[get_property PART $device] ne $expected_part} {
    error "expected $expected_part, found [get_property PART $device]"
}

refresh_hw_device $device
puts "HW_PART=[get_property PART $device]"
puts "HW_PROGRAM_FILE=[get_property PROGRAM.FILE $device]"
puts "HW_ILA_COUNT=[llength [get_hw_ilas -quiet -of_objects $device]]"
puts "HW_VIO_COUNT=[llength [get_hw_vios -quiet -of_objects $device]]"
puts "RESULT=UDP_ECHO_HARDWARE_INVENTORY_PASSED"

close_hw_target $target
disconnect_hw_server
close_hw_manager
close_project
exit 0
