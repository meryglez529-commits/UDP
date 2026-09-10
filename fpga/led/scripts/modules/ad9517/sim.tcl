# AD9517 behavioral simulation stage (S).  This stage never starts a build or
# opens Hardware Manager.
set module_dir [file dirname [file normalize [info script]]]
set scripts_dir [file normalize [file join $module_dir .. ..]]

source [file join $module_dir config.tcl]
source [file join $scripts_dir common project_guard.tcl]
source [file join $scripts_dir common run_identity.tcl]

cowork::validate_static_inputs true
cowork::init_run ad9517 sim
cowork::open_validated_project true
cowork::validate_registered_manifest
cowork::assert_xdc_selection

update_compile_order -fileset [cowork::cfg design_fileset]
update_compile_order -fileset [cowork::cfg simulation_fileset]

set input_fingerprint [cowork::simulation_input_fingerprint]
cowork::record PROJECT [cowork::cfg project_file]
cowork::record PART [cowork::cfg part]
cowork::record DESIGN_TOP [cowork::cfg design_top]
cowork::record SIMSET [cowork::cfg simulation_fileset]
cowork::record SIM_TOP [cowork::cfg simulation_top]
cowork::record INPUT_FINGERPRINT $input_fingerprint
cowork::record NATIVE_SIM_DIR [file join [cowork::cfg project_dir] led.sim]

launch_simulation -mode behavioral -simset [cowork::cfg simulation_fileset]
run all
close_sim

cowork::finish AD9517_SIM_PASS
close_project
exit 0
