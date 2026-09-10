# Volatile-program the approved bitstream and capture the register-27 MDIO
# transaction. The trigger masks all debug bits except scheduled_reg==27 and
# MDC==1; the 50% trigger position preserves the full Clause 22 read frame.
set project_path "D:/MyFPGAProject/UDP/fpga/led/led.xpr"
set bit_path "D:/MyFPGAProject/UDP/fpga/led/led.runs/impl_1/led_static.bit"
set ltx_path "D:/MyFPGAProject/UDP/fpga/led/led.runs/impl_1/led_static.ltx"
set data_base "D:/MyFPGAProject/UDP/fpga/led/led.hw/hw_1/m88e1111_runtime_reg27_b14a14_20260908"

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
if {$ila eq "" || $probe eq ""} {
    error "The programmed MDIO ILA or its debug probe was not found"
}

set_property CONTROL.DATA_DEPTH 16384 $ila
set_property CONTROL.TRIGGER_POSITION 8192 $ila
set_property CONTROL.TRIGGER_CONDITION AND $ila
# bit[27:23]=11011 is register 27; bit[4]=1 is MDC high.  Other bits are X.
set_property TRIGGER_COMPARE_VALUE "eq48'bXXXXXXXXXXXXXXXXXXXX11011XXXXXXXXXXXXXXXXXX1XXXX" $probe
puts "ILA_TRIGGER=[get_property TRIGGER_COMPARE_VALUE $probe]"
puts "ILA_TRIGGER_POSITION=[get_property CONTROL.TRIGGER_POSITION $ila]"

run_hw_ila $ila
wait_on_hw_ila -timeout 1 $ila
set ila_data [upload_hw_ila_data $ila]
write_hw_ila_data -force "${data_base}.ila" $ila_data
write_hw_ila_data -force -csv_file "${data_base}.csv" $ila_data
puts "ILA_DATA=${data_base}.ila"
puts "ILA_CSV=${data_base}.csv"

close_hw_target $target
disconnect_hw_server
close_hw_manager
close_project
