# Read-only capture of an autonomous Clause 22 transaction after the approved
# B14/A14 image is loaded.  Arguments: <tag> <five-bit-register-address>.
# It does not program the FPGA or drive PHY reset/any PHY write command.
if {[llength $argv] != 2 && [llength $argv] != 3} {
    error "Usage: capture_mdio_control_ila.tcl <tag> <register-bits> ?trigger-position?"
}

set capture_tag [lindex $argv 0]
set reg_bits [lindex $argv 1]
set trigger_position 8192
if {[llength $argv] == 3} {
    set trigger_position [lindex $argv 2]
}
if {![regexp {^[01]{5}$} $reg_bits]} {
    error "register-bits must be exactly five binary characters"
}
if {![string is integer -strict $trigger_position] || $trigger_position < 0 || $trigger_position >= 16384} {
    error "trigger-position must be an integer from 0 through 16383"
}

set project_path "D:/MyFPGAProject/UDP/fpga/led/led.xpr"
set data_base "D:/MyFPGAProject/UDP/fpga/led/led.hw/hw_1/m88e1111_runtime_${capture_tag}_b14a14_20260908"
set ltx_path "D:/MyFPGAProject/UDP/fpga/led/led.runs/impl_1/led_static.ltx"

open_project $project_path
open_hw_manager
connect_hw_server
set target [lindex [get_hw_targets *] 0]
if {$target eq ""} { error "No JTAG target was found by hw_server" }
open_hw_target $target
set device [lindex [get_hw_devices xc7k325t_0] 0]
if {$device eq ""} { error "Expected xc7k325t_0 was not found" }

set_property PROBES.FILE $ltx_path $device
refresh_hw_device $device
set ila ""
foreach candidate [get_hw_ilas -of_objects $device] {
    if {[get_property CELL_NAME $candidate] eq "u_ila_mdio"} { set ila $candidate }
}
set probe ""
foreach candidate [get_hw_probes -of_objects $ila] {
    if {[get_property NAME $candidate] eq "mdio_debug"} { set probe $candidate }
}
if {$ila eq "" || $probe eq "" || [get_property WIDTH $probe] != 48} {
    error "Expected 48-bit u_ila_mdio/mdio_debug was not found"
}

set_property CONTROL.DATA_DEPTH 16384 $ila
set_property CONTROL.TRIGGER_POSITION $trigger_position $ila
set_property CONTROL.TRIGGER_CONDITION AND $ila
set trigger_value "eq48'bXXXXXXXXXXXXXXXXXXXX${reg_bits}XXXXXXXXXXXXXXXXXX1XXXX"
set_property TRIGGER_COMPARE_VALUE $trigger_value $probe
puts "HW_TARGET=$target"
puts "HW_DEVICE=$device"
puts "CAPTURE_TAG=$capture_tag REGISTER_BITS=$reg_bits TRIGGER_POSITION=$trigger_position"
puts "ILA_TRIGGER=$trigger_value"

run_hw_ila $ila
wait_on_hw_ila -timeout 3 $ila
set ila_data [upload_hw_ila_data $ila]
write_hw_ila_data -force "${data_base}.ila" $ila_data
write_hw_ila_data -force -csv_file "${data_base}.csv" $ila_data
puts "ILA_DATA=${data_base}.ila"
puts "ILA_CSV=${data_base}.csv"

close_hw_target $target
disconnect_hw_server
close_hw_manager
close_project
