# Build the approved LED bitstream. Invoke with:
#   <AI-work/work-packages/.../out/build/<build-id>> ?reset_authorized?
#
# The optional token is required to reset stale project runs. It is never
# inferred by an ordinary build invocation.

set expected_vivado_version "2021.1"
set project_name "led"
set part_name "xc7k325tffg676-2"
set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set project_file [file join $project_dir "${project_name}.xpr"]

proc led_write_build_result {path result fields} {
    file mkdir [file dirname $path]
    set fp [open $path w]
    puts $fp "result=$result"
    foreach {key value} $fields {
        puts $fp "$key=$value"
    }
    close $fp
}

if {[llength $argv] < 1 || [llength $argv] > 2} {
    error "usage: build.tcl <AI-work build result directory> ?reset_authorized?"
}
set ai_run [file normalize [lindex $argv 0]]
set reset_policy ""
if {[llength $argv] == 2} {
    set reset_policy [lindex $argv 1]
}
if {![regexp {(^|/)AI-work(/|$)} [string map {\\ /} $ai_run]]} {
    error "build result directory must be below AI-work: $ai_run"
}
if {$reset_policy ni {"" reset_authorized}} {
    error "second argument must be reset_authorized when supplied"
}
set result_file [file join $ai_run BUILD_RESULT.txt]
set result "BUILD_SETUP_BLOCKED"
set detail ""
set bit_file ""
set ltx_file ""
set report_dir ""
set drc_violations ""
set drc_blocking_violations ""
set drc_warning_violations ""
set synth_status ""
set impl_status ""
set build_started 0

if {[catch {
    if {[version -short] ne $expected_vivado_version} {
        error "Vivado version mismatch: expected $expected_vivado_version, got [version -short]"
    }
    if {![file exists $project_file]} {
        error "project file not found: $project_file"
    }
    open_project $project_file
    if {[get_property PART [current_project]] ne $part_name} {
        error "project part mismatch: expected $part_name, got [get_property PART [current_project]]"
    }

    source [file join $script_dir sources.tcl]
    led_validate_manifest $project_dir
    foreach run_name {synth_1 impl_1} {
        set run_status [get_property STATUS [get_runs $run_name]]
        if {$run_name eq "synth_1"} {
            set synth_status $run_status
        } else {
            set impl_status $run_status
        }
        puts "${run_name}_STATUS_BEFORE=$run_status"
        if {[string match "*Running*" $run_status]} {
            error "BUILD_OUTPUT_LOCKED: $run_name is running"
        }
    }
    if {[get_property top [get_filesets sources_1]] ne "led_static"} {
        error "top-level mismatch: expected led_static"
    }
    if {$reset_policy eq "reset_authorized"} {
        puts "RESET_AUTHORIZED=reset stale synth_1 and impl_1 for this declared build"
        reset_run impl_1
        reset_run synth_1
    } elseif {[get_property NEEDS_REFRESH [get_runs impl_1]]} {
        error "BUILD_SETUP_BLOCKED: impl_1 is stale; rerun only with explicit reset_authorized"
    }

    set current_impl_status [get_property STATUS [get_runs impl_1]]
    if {[string match "*Complete*" $current_impl_status] &&
        ![get_property NEEDS_REFRESH [get_runs impl_1]]} {
        puts "REUSE_CURRENT_IMPL=impl_1 is complete and up to date"
    } else {
        set build_started 1
        launch_runs impl_1 -to_step write_bitstream -jobs 4
        wait_on_run impl_1
    }
    set synth_status [get_property STATUS [get_runs synth_1]]
    set impl_status [get_property STATUS [get_runs impl_1]]
    puts "impl_1_STATUS_AFTER=$impl_status"
    if {![string match "*Complete*" $impl_status]} {
        error "implementation did not complete: $impl_status"
    }

    open_run impl_1
    set report_dir [file join $project_dir "${project_name}.runs" impl_1 reports]
    file mkdir $report_dir
    report_timing_summary -file [file join $report_dir timing_summary.rpt]
    report_utilization -file [file join $report_dir utilization.rpt]
    report_drc -file [file join $report_dir drc.rpt]
    set drc_violations [get_drc_violations -quiet]
    foreach violation $drc_violations {
        set severity [get_property SEVERITY $violation]
        set identifier "[get_property NAME $violation]($severity)"
        if {$severity in {Error {Critical Warning}}} {
            lappend drc_blocking_violations $identifier
        } else {
            lappend drc_warning_violations $identifier
        }
    }
    if {[llength $drc_blocking_violations] != 0} {
        error "DRC blocking violations remain: [join $drc_blocking_violations {, }]"
    }

    set bit_candidates [glob -nocomplain -directory [file join $project_dir "${project_name}.runs" impl_1] *.bit]
    if {[llength $bit_candidates] != 1} {
        error "expected exactly one bitstream in impl_1, found [llength $bit_candidates]"
    }
    set bit_file [file normalize [lindex $bit_candidates 0]]
    if {[file size $bit_file] == 0} {
        error "bitstream is empty: $bit_file"
    }
    set ila_xci [file join $project_dir led.srcs sources_1 ip ila_led ila_led.xci]
    if {[file exists $ila_xci]} {
        # Vivado emits both <bit-basename>.ltx and debug_nets.ltx for this
        # RTL-instantiated core.  The same-basename file is the canonical
        # bit/LTX pair; a count-based selection would be ambiguous.
        set ltx_file "[file rootname $bit_file].ltx"
        if {![file exists $ltx_file]} {
            error "matching ILA probes file is missing: $ltx_file"
        }
        if {[file size $ltx_file] == 0} {
            error "ILA probes file is empty: $ltx_file"
        }
    }
    set result "BUILD_PASS"
} detail]} {
    if {[string match "BUILD_OUTPUT_LOCKED:*" $detail]} {
        set result "BUILD_OUTPUT_LOCKED"
    } elseif {$build_started} {
        set result "BUILD_TOOL_FAIL"
    }
}

catch {close_project}
set fields [list \
    project $project_file \
    part $part_name \
    synth_status $synth_status \
    impl_status $impl_status \
    bitstream $bit_file \
    ltx_file $ltx_file \
    report_dir $report_dir \
    drc_violation_count [llength $drc_violations] \
    drc_blocking_violation_count [llength $drc_blocking_violations] \
    drc_warning_count [llength $drc_warning_violations] \
    drc_warnings [join $drc_warning_violations {; }] \
    detail $detail]
led_write_build_result $result_file $result $fields
puts "BUILD_RESULT=$result_file"
puts "BITSTREAM=$bit_file"
puts "RESULT=$result"
if {$result ne "BUILD_PASS"} {
    exit 1
}
exit 0
