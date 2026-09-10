# AD9517 synthesis/implementation/signoff stage (B).  A matching completed
# implementation is reused; changed inputs or COWORK_FORCE_REBUILD=1 rebuild it.
set module_dir [file dirname [file normalize [info script]]]
set scripts_dir [file normalize [file join $module_dir .. ..]]

source [file join $module_dir config.tcl]
source [file join $scripts_dir common project_guard.tcl]
source [file join $scripts_dir common run_identity.tcl]
source [file join $scripts_dir common timing_guard.tcl]

cowork::validate_static_inputs false
cowork::init_run ad9517 build
cowork::open_validated_project false
cowork::validate_registered_manifest
cowork::assert_xdc_selection
cowork::assert_ila_ip
update_compile_order -fileset [cowork::cfg design_fileset]
cowork::assert_runs_idle

set input_fingerprint [cowork::build_input_fingerprint]
set stable_result [file join [cowork::cfg project_dir] logs ad9517 build latest_success.properties]
set previous [cowork::read_properties $stable_result]
set force_rebuild false
if {[info exists ::env(COWORK_FORCE_REBUILD)] && $::env(COWORK_FORCE_REBUILD) eq "1"} {
    set force_rebuild true
}

set synth_run [get_runs [cowork::cfg synth_run]]
set impl_run [get_runs [cowork::cfg impl_run]]
set bit_path [cowork::cfg bitstream]
set ltx_path [cowork::cfg probes_file]
set can_reuse [expr {
    !$force_rebuild &&
    [dict exists $previous INPUT_FINGERPRINT] &&
    [dict get $previous INPUT_FINGERPRINT] eq $input_fingerprint &&
    [string match "*Complete*" [get_property STATUS $synth_run]] &&
    [string match "*Complete*" [get_property STATUS $impl_run]] &&
    [file exists $bit_path] &&
    [file exists $ltx_path]
}]

if {$can_reuse} {
    set build_action REUSED_EXISTING_IMPLEMENTATION
    puts "Reusing completed implementation with matching input fingerprint $input_fingerprint"
} else {
    set build_action REBUILT
    reset_run [cowork::cfg impl_run]
    reset_run [cowork::cfg synth_run]
    launch_runs [cowork::cfg impl_run] -to_step write_bitstream -jobs 4
    wait_on_run [cowork::cfg impl_run]
}

set synth_status [get_property STATUS $synth_run]
set impl_status [get_property STATUS $impl_run]
if {![string match "*Complete*" $synth_status]} {
    error "synthesis did not complete: $synth_status"
}
if {![string match "*Complete*" $impl_status]} {
    error "implementation did not complete: $impl_status"
}

cowork::assert_no_constraint_critical [list \
    [file join [cowork::cfg project_dir] led.runs [cowork::cfg synth_run] runme.log] \
    [file join [cowork::cfg project_dir] led.runs [cowork::cfg impl_run] runme.log]]

open_run [cowork::cfg impl_run]
set report_dir [cowork::cfg report_dir]
cowork::write_signoff_reports $report_dir
cowork::assert_timing_coverage [file join $report_dir check_timing.rpt]
cowork::assert_bus_skew [file join $report_dir bus_skew.rpt]

lassign [cowork::drc_summary] blocking_drc warning_drc
if {[llength $blocking_drc] != 0} {
    error "blocking DRC violations: [join $blocking_drc {, }]"
}

lassign [cowork::worst_slacks] wns whs
if {$wns eq "N/A" || $whs eq "N/A"} {
    error "timing paths are unavailable: WNS=$wns WHS=$whs"
}
if {$wns < 0.0} { error "setup timing failed: WNS=$wns" }
if {$whs < 0.0} { error "hold timing failed: WHS=$whs" }

cowork::require_file bitstream $bit_path
cowork::require_file probes-file $ltx_path

cowork::record PROJECT [cowork::cfg project_file]
cowork::record PART [cowork::cfg part]
cowork::record TOP [cowork::cfg design_top]
cowork::record SYNTH_RUN [cowork::cfg synth_run]
cowork::record IMPL_RUN [cowork::cfg impl_run]
cowork::record SYNTH_STATUS $synth_status
cowork::record IMPL_STATUS $impl_status
cowork::record INPUT_FINGERPRINT $input_fingerprint
cowork::record BUILD_ACTION $build_action
cowork::record DRC_BLOCKING_COUNT [llength $blocking_drc]
cowork::record DRC_WARNING_COUNT [llength $warning_drc]
cowork::record WNS $wns
cowork::record WHS $whs
cowork::record BITSTREAM [file normalize $bit_path]
cowork::record LTX [file normalize $ltx_path]
cowork::record REPORT_DIR [file normalize $report_dir]
cowork::finish AD9517_BUILD_PASS

close_project
exit 0
