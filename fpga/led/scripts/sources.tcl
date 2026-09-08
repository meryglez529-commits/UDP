# Explicit source manifest for the user-created LED Vivado project.
# Keep every design, constraint, and simulation file in these lists.  Do not
# discover project inputs through directory globs.

proc led_require_file {kind path} {
    if {![file exists $path]} {
        error "required $kind file is missing: $path"
    }
}

proc led_register_file {fileset path} {
    set matches [get_files -quiet $path]
    if {[llength $matches] == 0} {
        add_files -norecurse -fileset $fileset $path
    } elseif {[llength $matches] != 1} {
        error "source is ambiguous in project: $path"
    }
}

proc led_validate_manifest {project_dir} {
    set rtl_files [list \
        [file join $project_dir led.srcs sources_1 new led_static.v]]
    set ip_files [list \
        [file join $project_dir led.srcs sources_1 ip ila_led ila_led.xci]]
    set xdc_files [list \
        [file join $project_dir led.srcs constrs_1 new led_static.xdc]]
    set sim_files [list \
        [file join $project_dir led.srcs sim_1 new led_static_tb.v]]

    foreach path $rtl_files { led_require_file RTL $path }
    foreach path $ip_files { led_require_file IP $path }
    foreach path $xdc_files { led_require_file XDC $path }
    foreach path $sim_files { led_require_file simulation $path }
    return [list $rtl_files $ip_files $xdc_files $sim_files]
}

proc led_register_manifest {project_dir} {
    lassign [led_validate_manifest $project_dir] rtl_files ip_files xdc_files sim_files
    foreach path $rtl_files { led_register_file sources_1 $path }
    foreach path $ip_files { led_register_file sources_1 $path }
    foreach path $xdc_files { led_register_file constrs_1 $path }
    foreach path $sim_files { led_register_file sim_1 $path }
}
