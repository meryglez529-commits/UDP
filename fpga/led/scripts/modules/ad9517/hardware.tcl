# AD9517 volatile programming and bounded ILA capture stage (H).  It accepts
# only the bit/LTX pair recorded by the latest successful matching build.
set module_dir [file dirname [file normalize [info script]]]
set scripts_dir [file normalize [file join $module_dir .. ..]]

source [file join $module_dir config.tcl]
source [file join $scripts_dir common project_guard.tcl]
source [file join $scripts_dir common run_identity.tcl]
source [file join $scripts_dir common hardware_common.tcl]

cowork::validate_static_inputs false
cowork::init_run ad9517 hardware

set stable_result [file join [cowork::cfg project_dir] logs ad9517 build latest_success.properties]
set build_result [cowork::read_properties $stable_result]
if {![dict exists $build_result RESULT] || [dict get $build_result RESULT] ne "AD9517_BUILD_PASS"} {
    error "no successful AD9517 build identity is available: $stable_result"
}
set current_fingerprint [cowork::build_input_fingerprint]
if {![dict exists $build_result INPUT_FINGERPRINT] ||
    [dict get $build_result INPUT_FINGERPRINT] ne $current_fingerprint} {
    error "RTL/XDC/IP inputs changed after the accepted build; run the build stage first"
}
foreach key {BITSTREAM LTX} {
    if {![dict exists $build_result $key]} {
        error "accepted build identity is missing $key"
    }
}
set bit_path [dict get $build_result BITSTREAM]
set ltx_path [dict get $build_result LTX]
cowork::require_file bitstream $bit_path
cowork::require_file probes-file $ltx_path

cowork::open_validated_project false
if {[info exists ::env(COWORK_PREFLIGHT_ONLY)] && $::env(COWORK_PREFLIGHT_ONLY) eq "1"} {
    cowork::record PROJECT [cowork::cfg project_file]
    cowork::record HW_PART [cowork::cfg hw_part]
    cowork::record INPUT_FINGERPRINT $current_fingerprint
    cowork::record BITSTREAM [file normalize $bit_path]
    cowork::record LTX [file normalize $ltx_path]
    cowork::finish AD9517_HARDWARE_PREFLIGHT_PASS
    close_project
    exit 0
}

lassign [cowork::open_unique_hw_device [cowork::cfg hw_part]] target device
cowork::program_and_refresh $device $bit_path $ltx_path
lassign [cowork::find_unique_ila $device \
    [cowork::cfg ila_cell] [cowork::cfg ila_probe] [cowork::cfg ila_probe_width]] ila probe

set trigger_value "eq64'b10100101XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
set_property CONTROL.DATA_DEPTH 16384 $ila
set_property CONTROL.TRIGGER_POSITION 8192 $ila
set_property CONTROL.TRIGGER_CONDITION AND $ila
set_property TRIGGER_COMPARE_VALUE $trigger_value $probe

file mkdir [cowork::cfg hardware_output_dir]
set data_base [file join [cowork::cfg hardware_output_dir] "ad9517_final_status_$::cowork::run_id"]
run_hw_ila $ila
wait_on_hw_ila -timeout 3 $ila
set ila_data [upload_hw_ila_data $ila]
write_hw_ila_data -force "${data_base}.ila" $ila_data
write_hw_ila_data -force -csv_file "${data_base}.csv" $ila_data

cowork::record PROJECT [cowork::cfg project_file]
cowork::record HW_TARGET $target
cowork::record HW_DEVICE $device
cowork::record HW_PART [get_property PART $device]
cowork::record INPUT_FINGERPRINT $current_fingerprint
cowork::record BITSTREAM [file normalize $bit_path]
cowork::record LTX [file normalize $ltx_path]
cowork::record PROGRAMMED_BIT [get_property PROGRAM.FILE $device]
cowork::record PROGRAMMED_LTX [get_property PROBES.FILE $device]
cowork::record HW_ILA $ila
cowork::record HW_ILA_CELL [get_property CELL_NAME $ila]
cowork::record HW_PROBE $probe
cowork::record HW_PROBE_WIDTH [get_property WIDTH $probe]
cowork::record ILA_TRIGGER $trigger_value
cowork::record ILA_DATA "${data_base}.ila"
cowork::record ILA_CSV "${data_base}.csv"
cowork::finish AD9517_PROGRAM_AND_CAPTURE_PASS

close_hw_target $target
disconnect_hw_server
close_hw_manager
close_project
exit 0
