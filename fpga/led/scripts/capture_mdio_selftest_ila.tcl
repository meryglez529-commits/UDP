# Read-only ILA captures for the MDC-low MDIO open-drain self-test and the
# first Clause 22 frame that follows it.  The FPGA is not programmed here.
set project_path "D:/MyFPGAProject/UDP/fpga/led/led.xpr"
set data_dir "D:/MyFPGAProject/UDP/fpga/led/led.hw/hw_1"
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
set_property CONTROL.TRIGGER_CONDITION AND $ila
puts "HW_TARGET=$target"
puts "HW_DEVICE=$device"
puts "HW_ILA=$ila CELL=[get_property CELL_NAME $ila]"

# H3: probe_state is bits [42:40]; PROBE_SELFTEST=3'b101.  Trigger early so
# post-trigger data contains the whole 20.4 us release-low-release sequence.
set_property CONTROL.TRIGGER_POSITION 1024 $ila
set_property TRIGGER_COMPARE_VALUE "eq48'bXXXXX101XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" $probe
puts "H3_TRIGGER=[get_property TRIGGER_COMPARE_VALUE $probe]"
run_hw_ila $ila
wait_on_hw_ila -timeout 3 $ila
set selftest_data [upload_hw_ila_data $ila]
write_hw_ila_data -force "${data_dir}/m88e1111_selftest_b14a14_20260908.ila" $selftest_data
write_hw_ila_data -force -csv_file "${data_dir}/m88e1111_selftest_b14a14_20260908.csv" $selftest_data

# H4: transaction_index=0, preamble phase=001, and MDC high.  The 50% trigger
# position retains the preceding idle interval and the ensuing complete frame.
set_property CONTROL.TRIGGER_POSITION 8192 $ila
set_property TRIGGER_COMPARE_VALUE "eq48'bXXXXXXXX001XXXXXX000XXXXXXXXXXXXXXXXXXXXXXX1XXXX" $probe
puts "H4_TRIGGER=[get_property TRIGGER_COMPARE_VALUE $probe]"
run_hw_ila $ila
wait_on_hw_ila -timeout 3 $ila
set frame_data [upload_hw_ila_data $ila]
write_hw_ila_data -force "${data_dir}/m88e1111_selftest_frame_b14a14_20260908.ila" $frame_data
write_hw_ila_data -force -csv_file "${data_dir}/m88e1111_selftest_frame_b14a14_20260908.csv" $frame_data

puts "H3_ILA=${data_dir}/m88e1111_selftest_b14a14_20260908.ila"
puts "H3_CSV=${data_dir}/m88e1111_selftest_b14a14_20260908.csv"
puts "H4_ILA=${data_dir}/m88e1111_selftest_frame_b14a14_20260908.ila"
puts "H4_CSV=${data_dir}/m88e1111_selftest_frame_b14a14_20260908.csv"

close_hw_target $target
disconnect_hw_server
close_hw_manager
close_project
