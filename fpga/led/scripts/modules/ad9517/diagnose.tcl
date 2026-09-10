# Read-only AD9517 project diagnosis stage (D).  It does not update compile
# order, reset/launch runs, simulate, program hardware or capture ILA data.
set module_dir [file dirname [file normalize [info script]]]
set scripts_dir [file normalize [file join $module_dir .. ..]]

source [file join $module_dir config.tcl]
source [file join $scripts_dir common project_guard.tcl]
source [file join $scripts_dir common run_identity.tcl]

cowork::validate_static_inputs true
cowork::init_run ad9517 diagnose
cowork::open_validated_project true
cowork::validate_registered_manifest
cowork::assert_xdc_selection
cowork::assert_ila_ip

cowork::record PROJECT [cowork::cfg project_file]
cowork::record PART [get_property PART [current_project]]
cowork::record DESIGN_TOP [get_property top [get_filesets [cowork::cfg design_fileset]]]
cowork::record SIM_TOP [get_property top [get_filesets [cowork::cfg simulation_fileset]]]
cowork::record SYNTH_STATUS [get_property STATUS [get_runs [cowork::cfg synth_run]]]
cowork::record IMPL_STATUS [get_property STATUS [get_runs [cowork::cfg impl_run]]]
cowork::record BUILD_INPUT_FINGERPRINT [cowork::build_input_fingerprint]
cowork::record SIM_INPUT_FINGERPRINT [cowork::simulation_input_fingerprint]
cowork::record BITSTREAM_EXISTS [file exists [cowork::cfg bitstream]]
cowork::record LTX_EXISTS [file exists [cowork::cfg probes_file]]
cowork::finish AD9517_DIAGNOSE_PASS

close_project
exit 0
