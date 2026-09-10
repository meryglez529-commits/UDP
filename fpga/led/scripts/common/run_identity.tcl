# Per-invocation result recording.  The PowerShell launcher supplies a unique
# directory; direct Tcl use falls back to a unique manual-run directory.
namespace eval cowork {
    variable result_file ""
    variable run_dir ""
    variable run_id ""
}
proc cowork::init_run {module stage} {
    variable result_file
    variable run_dir
    variable run_id

    if {[info exists ::env(COWORK_RUN_ID)] && $::env(COWORK_RUN_ID) ne ""} {
        set run_id $::env(COWORK_RUN_ID)
    } else {
        set run_id "[clock format [clock seconds] -format {%Y%m%d_%H%M%S}]_[pid]"
    }

    if {[info exists ::env(COWORK_RUN_DIR)] && $::env(COWORK_RUN_DIR) ne ""} {
        set run_dir [file normalize $::env(COWORK_RUN_DIR)]
    } else {
        set run_dir [file normalize [file join [cowork::cfg project_dir] logs $module $stage $run_id]]
    }

    file mkdir $run_dir
    set result_file [file join $run_dir result.properties]
    set handle [open $result_file w]
    puts $handle "SCHEMA_VERSION=1"
    close $handle

    cowork::record RUN_ID $run_id
    cowork::record MODULE $module
    cowork::record STAGE $stage
    cowork::record STARTED_AT [clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S%z}]
    cowork::record VIVADO_VERSION [version -short]
}

proc cowork::record {key value} {
    variable result_file
    set clean $value
    regsub -all {[\r\n]} $clean { } clean
    puts "COWORK_RESULT $key=$clean"
    if {$result_file ne ""} {
        set handle [open $result_file a]
        puts $handle "$key=$clean"
        close $handle
    }
}

proc cowork::finish {result} {
    cowork::record RESULT $result
    cowork::record FINISHED_AT [clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S%z}]
}

proc cowork::read_properties {path} {
    set values [dict create]
    if {![file exists $path]} {
        return $values
    }
    set handle [open $path r]
    while {[gets $handle line] >= 0} {
        set separator [string first "=" $line]
        if {$separator <= 0} {
            continue
        }
        set key [string range $line 0 [expr {$separator - 1}]]
        set value [string range $line [expr {$separator + 1}] end]
        dict set values $key $value
    }
    close $handle
    return $values
}
