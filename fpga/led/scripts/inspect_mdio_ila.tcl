# Inspect ILA/probe control properties before arming a capture.
open_hw_manager
connect_hw_server
set target [lindex [get_hw_targets *] 0]
open_hw_target $target
set device [lindex [get_hw_devices xc7k325t_0] 0]
set_property PROGRAM.FILE "D:/MyFPGAProject/UDP/fpga/led/led.runs/impl_1/led_static.bit" $device
set_property PROBES.FILE "D:/MyFPGAProject/UDP/fpga/led/led.runs/impl_1/led_static.ltx" $device
program_hw_devices $device
refresh_hw_device $device
set ila ""
foreach candidate [get_hw_ilas -of_objects $device] {
    if {[get_property CELL_NAME $candidate] eq "u_ila_mdio"} {
        set ila $candidate
    }
}
set probe ""
foreach candidate [get_hw_probes -of_objects $ila] {
    if {[get_property NAME $candidate] eq "mdio_debug"} {
        set probe $candidate
    }
}
puts "ILA_PROPERTY_BEGIN"
report_property -all $ila
puts "PROBE_PROPERTY_BEGIN"
report_property -all $probe
close_hw_target $target
disconnect_hw_server
close_hw_manager
