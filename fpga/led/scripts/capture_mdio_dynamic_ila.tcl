# Read-only ILA captures for the approved MDIO dynamic-validation work package.
# This script neither programs the FPGA nor writes PHY/Flash/reset controls.
set project_path "D:/MyFPGAProject/UDP/fpga/led/led.xpr"
set data_dir "D:/MyFPGAProject/UDP/fpga/led/led.hw/hw_1"
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
# PROBES.FILE is a per-Hardware-Manager-session host setting.  Loading the
# matching LTX and refreshing only discovers the debug cores; it does not
# reprogram the FPGA.
set_property PROBES.FILE $ltx_path $device
refresh_hw_device $device

set ila ""
foreach candidate [get_hw_ilas -of_objects $device] {
    if {[get_property CELL_NAME $candidate] eq "u_ila_mdio"} {
        set ila $candidate
    }
}
if {$ila eq ""} {
    error "The running FPGA image does not expose u_ila_mdio"
}

set probe ""
foreach candidate [get_hw_probes -of_objects $ila] {
    if {[get_property NAME $candidate] eq "mdio_debug"} {
        set probe $candidate
    }
}
if {$probe eq "" || [get_property WIDTH $probe] != 48} {
    error "Expected 48-bit mdio_debug probe was not found"
}

set_property CONTROL.DATA_DEPTH 16384 $ila
set_property CONTROL.TRIGGER_POSITION 8192 $ila
set_property CONTROL.TRIGGER_CONDITION AND $ila
puts "HW_TARGET=$target"
puts "HW_DEVICE=$device"
puts "HW_ILA=$ila CELL=[get_property CELL_NAME $ila]"

# H1: sequence_done is bit 0. It stays high throughout the 100 ms idle gap.
set_property TRIGGER_COMPARE_VALUE "eq48'bXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX1" $probe
puts "H1_TRIGGER=[get_property TRIGGER_COMPARE_VALUE $probe]"
run_hw_ila $ila
wait_on_hw_ila -timeout 3 $ila
set idle_data [upload_hw_ila_data $ila]
write_hw_ila_data -force "${data_dir}/m88e1111_dynamic_idle_b14a14_20260908.ila" $idle_data
write_hw_ila_data -force -csv_file "${data_dir}/m88e1111_dynamic_idle_b14a14_20260908.csv" $idle_data

# H2: reader_phase is bits [39:37]; preamble=3'b001. MDC is bit 4.
set_property TRIGGER_COMPARE_VALUE "eq48'bXXXXXXXX001XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX1XXXX" $probe
puts "H2_TRIGGER=[get_property TRIGGER_COMPARE_VALUE $probe]"
run_hw_ila $ila
wait_on_hw_ila -timeout 3 $ila
set preamble_data [upload_hw_ila_data $ila]
write_hw_ila_data -force "${data_dir}/m88e1111_dynamic_preamble_b14a14_20260908.ila" $preamble_data
write_hw_ila_data -force -csv_file "${data_dir}/m88e1111_dynamic_preamble_b14a14_20260908.csv" $preamble_data

puts "H1_ILA=${data_dir}/m88e1111_dynamic_idle_b14a14_20260908.ila"
puts "H1_CSV=${data_dir}/m88e1111_dynamic_idle_b14a14_20260908.csv"
puts "H2_ILA=${data_dir}/m88e1111_dynamic_preamble_b14a14_20260908.ila"
puts "H2_CSV=${data_dir}/m88e1111_dynamic_preamble_b14a14_20260908.csv"

close_hw_target $target
disconnect_hw_server
close_hw_manager
close_project
