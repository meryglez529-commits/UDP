# Shared project/file/run guards for Vivado project-mode flows.
namespace eval cowork {}

proc cowork::cfg {key} {
    if {![info exists ::cowork_module_config]} {
        error "cowork module config has not been loaded"
    }
    if {![dict exists $::cowork_module_config $key]} {
        error "cowork module config is missing key: $key"
    }
    return [dict get $::cowork_module_config $key]
}

proc cowork::require_file {kind path} {
    if {![file exists $path]} {
        error "required $kind file is missing: $path"
    }
}

proc cowork::require_files {kind paths} {
    foreach path $paths {
        cowork::require_file $kind $path
    }
}

proc cowork::validate_static_inputs {{include_simulation false}} {
    cowork::require_file project [cowork::cfg project_file]
    cowork::require_file source-manifest [cowork::cfg source_manifest]
    cowork::require_files RTL [cowork::cfg rtl_files]
    cowork::require_files XDC [cowork::cfg xdc_files]
    cowork::require_files IP [cowork::cfg ip_files]
    if {$include_simulation} {
        cowork::require_files simulation [cowork::cfg simulation_files]
    }
}

proc cowork::assert_vivado_identity {} {
    set expected [cowork::cfg vivado_version]
    if {[version -short] ne $expected} {
        error "Vivado version mismatch: expected $expected, got [version -short]"
    }
}

proc cowork::open_validated_project {{check_simulation_top false}} {
    cowork::assert_vivado_identity
    open_project [cowork::cfg project_file]

    if {[get_property PART [current_project]] ne [cowork::cfg part]} {
        error "part mismatch: expected [cowork::cfg part], got [get_property PART [current_project]]"
    }

    set design_fileset [get_filesets -quiet [cowork::cfg design_fileset]]
    if {[llength $design_fileset] != 1} {
        error "design fileset is missing or ambiguous"
    }
    if {[get_property top $design_fileset] ne [cowork::cfg design_top]} {
        error "design top mismatch: expected [cowork::cfg design_top], got [get_property top $design_fileset]"
    }

    if {$check_simulation_top} {
        set sim_fileset [get_filesets -quiet [cowork::cfg simulation_fileset]]
        if {[llength $sim_fileset] != 1} {
            error "simulation fileset is missing or ambiguous"
        }
        if {[get_property top $sim_fileset] ne [cowork::cfg simulation_top]} {
            error "simulation top mismatch: expected [cowork::cfg simulation_top], got [get_property top $sim_fileset]"
        }
    }
}

proc cowork::validate_registered_manifest {} {
    source [cowork::cfg source_manifest]
    led_validate_manifest [cowork::cfg project_dir]

    foreach path [concat \
            [cowork::cfg rtl_files] \
            [cowork::cfg simulation_files] \
            [cowork::cfg xdc_files] \
            [cowork::cfg ip_files]] {
        if {[llength [get_files -quiet $path]] != 1} {
            error "configured project input is not registered exactly once: $path"
        }
    }
}

proc cowork::assert_xdc_selection {} {
    set active [get_files -quiet [cowork::cfg active_xdc]]
    set inactive [get_files -quiet [cowork::cfg inactive_xdc]]
    if {[llength $active] != 1 || ![get_property IS_ENABLED $active]} {
        error "required active XDC is missing or disabled: [cowork::cfg active_xdc]"
    }
    if {[llength $inactive] != 1 || [get_property IS_ENABLED $inactive]} {
        error "legacy XDC is missing or still enabled: [cowork::cfg inactive_xdc]"
    }
}

proc cowork::assert_ila_ip {} {
    set ila [get_ips -quiet [cowork::cfg ila_ip]]
    if {[llength $ila] != 1} {
        error "expected exactly one [cowork::cfg ila_ip] IP"
    }
    if {[get_property CONFIG.C_PROBE0_WIDTH $ila] ne [cowork::cfg ila_probe_width]} {
        error "ILA probe width mismatch"
    }
}

proc cowork::assert_runs_idle {} {
    foreach run_name [list [cowork::cfg synth_run] [cowork::cfg impl_run]] {
        set run [get_runs -quiet $run_name]
        if {[llength $run] != 1} {
            error "Vivado run is missing: $run_name"
        }
        set status [get_property STATUS $run]
        puts "${run_name}_STATUS_BEFORE=$status"
        if {[string match "*Running*" $status]} {
            error "$run_name reports an active or stale Running state; inspect/recover it before starting another build"
        }
    }
}

proc cowork::fingerprint_files {paths} {
    # Vivado 2021.1's bundled Tcl does not expose the optional zlib command.
    # Use a deterministic 32-bit FNV-1a fingerprint for fast stale-input
    # detection.  Programming artifacts receive a separate SHA-256 identity
    # from the PowerShell dispatcher.
    set hash 2166136261
    foreach path [lsort -dictionary $paths] {
        cowork::require_file fingerprint-input $path
        set handle [open $path rb]
        fconfigure $handle -translation binary
        set bytes [read $handle]
        close $handle
        binary scan "$path\u0000$bytes" c* octets
        foreach octet $octets {
            set hash [expr {(($hash ^ ($octet & 0xff)) * 16777619) & 0xffffffff}]
        }
    }
    return [format "%08X" $hash]
}

proc cowork::build_input_fingerprint {} {
    return [cowork::fingerprint_files [concat \
        [cowork::cfg rtl_files] \
        [cowork::cfg xdc_files] \
        [cowork::cfg ip_files] \
        [list [cowork::cfg source_manifest]]]]
}

proc cowork::simulation_input_fingerprint {} {
    return [cowork::fingerprint_files [concat \
        [cowork::cfg rtl_files] \
        [cowork::cfg simulation_files] \
        [cowork::cfg ip_files] \
        [list [cowork::cfg source_manifest]]]]
}
