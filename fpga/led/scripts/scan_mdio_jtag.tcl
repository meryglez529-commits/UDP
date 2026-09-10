# Read-only JTAG inventory for the approved M88E1111 runtime validation.
open_hw_manager
connect_hw_server
set targets [get_hw_targets *]
if {[llength $targets] == 0} {
    error "No JTAG target was found by hw_server"
}
foreach target $targets {
    puts "HW_TARGET=$target"
    open_hw_target $target
    foreach device [get_hw_devices] {
        refresh_hw_device $device
        puts "HW_DEVICE=$device PART=[get_property PART $device] PROGRAMMED=[get_property PROGRAM.FILE $device]"
    }
    close_hw_target $target
}
disconnect_hw_server
close_hw_manager
