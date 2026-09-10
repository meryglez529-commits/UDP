# Build-signoff helpers shared by module flows.
namespace eval cowork {}

proc cowork::read_latest_vivado_invocation {path} {
    cowork::require_file run-log $path
    set handle [open $path r]
    set text [read $handle]
    close $handle
    set start [string last "****** Vivado v" $text]
    if {$start < 0} {
        error "missing Vivado invocation marker in $path"
    }
    return [string range $text $start end]
}

proc cowork::assert_no_constraint_critical {paths} {
    foreach path $paths {
        set latest [cowork::read_latest_vivado_invocation $path]
        if {[regexp {CRITICAL WARNING: \[Constraints} $latest]} {
            error "constraint critical warning found in latest invocation of $path"
        }
    }
}

proc cowork::write_signoff_reports {report_dir} {
    file mkdir $report_dir
    report_timing_summary -delay_type min_max -report_unconstrained \
        -check_timing_verbose -file "$report_dir/timing_summary.rpt"
    report_utilization -file "$report_dir/utilization.rpt"
    report_drc -file "$report_dir/drc.rpt"
    report_route_status -file "$report_dir/route_status.rpt"
    report_clock_interaction -file "$report_dir/clock_interaction.rpt"
    report_bus_skew -warn_on_violation -file "$report_dir/bus_skew.rpt"
    check_timing -verbose -file "$report_dir/check_timing.rpt"
}

proc cowork::assert_timing_coverage {check_timing_report} {
    cowork::require_file check-timing-report $check_timing_report
    set handle [open $check_timing_report r]
    set text [read $handle]
    close $handle

    if {![regexp {checking unconstrained_internal_endpoints \(0\)} $text]} {
        error "check_timing does not report zero unconstrained internal endpoints"
    }
    if {[regexp {There (?:is|are) [1-9][0-9]* pins? that (?:is|are) not constrained for maximum delay} $text]} {
        error "check_timing found unconstrained internal maximum-delay endpoints"
    }
}

proc cowork::assert_bus_skew {bus_skew_report} {
    cowork::require_file bus-skew-report $bus_skew_report
    set handle [open $bus_skew_report r]
    set text [read $handle]
    close $handle
    if {[regexp {Slack \(VIOLATED\)} $text]} {
        error "report_bus_skew contains a violated requirement"
    }
}

proc cowork::drc_summary {} {
    set blocking {}
    set warnings {}
    foreach violation [get_drc_violations -quiet] {
        set severity [get_property SEVERITY $violation]
        set item "[get_property NAME $violation]($severity)"
        if {$severity in {Error {Critical Warning}}} {
            lappend blocking $item
        } else {
            lappend warnings $item
        }
    }
    return [list $blocking $warnings]
}

proc cowork::worst_slacks {} {
    set max_path [get_timing_paths -quiet -delay_type max -max_paths 1]
    set min_path [get_timing_paths -quiet -delay_type min -max_paths 1]
    set wns "N/A"
    set whs "N/A"
    if {[llength $max_path] != 0} {
        set wns [get_property SLACK $max_path]
    }
    if {[llength $min_path] != 0} {
        set whs [get_property SLACK $min_path]
    }
    return [list $wns $whs]
}
