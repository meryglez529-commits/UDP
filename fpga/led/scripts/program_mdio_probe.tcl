# Volatile JTAG programming of the approved read-only MDIO probe, followed by
# an inventory of the exact debug cores/probes described by the matching LTX.
set project_path "D:/MyFPGAProject/UDP/fpga/led/led.xpr"
set bit_path "D:/MyFPGAProject/UDP/fpga/led/led.runs/impl_1/led_static.bit"
set ltx_path "D:/MyFPGAProject/UDP/fpga/led/led.runs/impl_1/led_static.ltx"

open_project $project_path
open_hw_manager
connect_hw_server
set target [lindex [get_hw_targets *] 0]
if {$target eq ""} {
    error "No JTAG target was found by hw_server"
}
open_hw_target $target
set device [lindex [get_hw_devices xc7k325t_0] 0]
if {$device eq ""} {
    error "Expected xc7k325t_0 was not found"
}

set_property PROGRAM.FILE $bit_path $device
set_property PROBES.FILE $ltx_path $device
program_hw_devices $device
refresh_hw_device $device

puts "PROGRAMMED_DEVICE=$device PART=[get_property PART $device]"
puts "PROGRAMMED_BIT=[get_property PROGRAM.FILE $device]"
puts "PROGRAMMED_LTX=[get_property PROBES.FILE $device]"
foreach ila [get_hw_ilas -of_objects $device] {
    puts "HW_ILA=$ila CELL=[get_property CELL_NAME $ila] DATA_DEPTH=[get_property CONTROL.DATA_DEPTH $ila]"
    foreach probe [get_hw_probes -of_objects $ila] {
        puts "HW_PROBE=$probe WIDTH=[get_property WIDTH $probe]"
    }
}

close_hw_target $target
disconnect_hw_server
close_hw_manager
close_project
