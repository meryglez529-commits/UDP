set expected_vivado_version "2021.1"
set project_path "D:/MyFPGAProject/UDP/fpga/led/led.xpr"
set project_root "D:/MyFPGAProject/UDP/fpga/led"
set echo_top "udp_echo_test_top"
set synth_name "synth_udp_echo"
set impl_name "impl_udp_echo"

if {[version -short] ne $expected_vivado_version} {
    error "Vivado version mismatch: expected $expected_vivado_version, got [version -short]"
}

open_project $project_path
source "$project_root/scripts/sources.tcl"
led_register_manifest $project_root

# Select only the board constraints that match the echo wrapper ports.
set_property IS_ENABLED false [get_files "$project_root/led.srcs/constrs_1/new/led_static.xdc"]
set_property IS_ENABLED false [get_files "$project_root/led.srcs/constrs_1/new/ad9517_clock_manager.xdc"]
set_property IS_ENABLED true  [get_files "$project_root/led.srcs/constrs_1/new/udp_top.xdc"]
set_property top $echo_top [get_filesets sources_1]
update_compile_order -fileset sources_1

# ENABLE_AD_ILA=0 removes the ILA instance from this top.  Temporarily disable
# its XCI as well so implementation does not try to apply ila_ad9517 scoped
# constraints to a module which is intentionally absent.  Restore the shared
# project setting immediately after the dedicated route run finishes.
set ad_ila_file [get_files -quiet "$project_root/led.srcs/sources_1/ip/ila_ad9517/ila_ad9517.xci"]
set ad_ila_was_enabled 0
if {[llength $ad_ila_file] != 0} {
    set ad_ila_was_enabled [get_property IS_ENABLED $ad_ila_file]
    set_property IS_ENABLED false $ad_ila_file
}

set part_name [get_property PART [current_project]]
if {[llength [get_runs -quiet $synth_name]] == 0} {
    create_run $synth_name -part $part_name -flow {Vivado Synthesis 2021} \
        -strategy Flow_PerfOptimized_high -constrset constrs_1
}
if {[llength [get_runs -quiet $impl_name]] == 0} {
    create_run $impl_name -part $part_name -flow {Vivado Implementation 2021} \
        -strategy Performance_Explore -constrset constrs_1 -parent_run $synth_name
}

set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true [get_runs $impl_name]

# This is a dedicated test run; rebuild it from the current registered inputs.
# Stop at routed design first so timing/DRC are checked independently of the
# separately licensed TEMAC bitstream-generation feature.
reset_run $impl_name
reset_run $synth_name
launch_runs $impl_name -to_step route_design -jobs 4
wait_on_run $impl_name
if {[llength $ad_ila_file] != 0} {
    set_property IS_ENABLED $ad_ila_was_enabled $ad_ila_file
}

set synth_status [get_property STATUS [get_runs $synth_name]]
set impl_status [get_property STATUS [get_runs $impl_name]]
if {![string match "*Complete*" $synth_status]} {
    error "UDP echo synthesis did not complete: $synth_status"
}
if {![string match "*Complete*" $impl_status]} {
    error "UDP echo implementation did not complete: $impl_status"
}

open_run $impl_name
set report_dir "$project_root/led.runs/$impl_name/reports"
file mkdir $report_dir
report_utilization -file "$report_dir/utilization.rpt"
report_clock_utilization -file "$report_dir/clock_utilization.rpt"
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file "$report_dir/timing_summary.rpt"
report_drc -file "$report_dir/drc.rpt"
report_methodology -file "$report_dir/methodology.rpt"

set setup_paths [get_timing_paths -setup -max_paths 1]
set hold_paths  [get_timing_paths -hold -max_paths 1]
if {[llength $setup_paths] == 0 || [llength $hold_paths] == 0} {
    error "timing paths are unavailable"
}
set wns [get_property SLACK [lindex $setup_paths 0]]
set whs [get_property SLACK [lindex $hold_paths 0]]
if {$wns < 0.0} { error "setup timing failed: WNS=$wns" }
if {$whs < 0.0} { error "hold timing failed: WHS=$whs" }

set blocking_drc [get_drc_violations -quiet -filter {
    IS_ENABLED == 1 && (SEVERITY == "Error" || SEVERITY == "Critical Warning")
}]
if {[llength $blocking_drc] != 0} {
    error "blocking DRC violations: [join $blocking_drc {, }]"
}

puts "RESULT=UDP_ECHO_ROUTE_PASSED"

if {[info exists ::env(UDP_ECHO_ROUTE_ONLY)] &&
    $::env(UDP_ECHO_ROUTE_ONLY) eq "1"} {
    puts "PROJECT=$project_path"
    puts "TOP=[get_property top [get_filesets sources_1]]"
    puts "SYNTH_RUN=$synth_name"
    puts "SYNTH_STATUS=$synth_status"
    puts "IMPL_RUN=$impl_name"
    puts "IMPL_STATUS=$impl_status"
    puts "WNS=$wns"
    puts "WHS=$whs"
    puts "DRC_BLOCKING_COUNT=[llength $blocking_drc]"
    puts "REPORT_DIR=[file normalize $report_dir]"
    close_project
    exit 0
}

# Bitstream generation can require a licensed TEMAC feature even after the
# complete routed design has passed.  Keep that failure distinct from RTL,
# constraint, timing, and DRC failures.
close_design
launch_runs $impl_name -to_step write_bitstream -jobs 4
wait_on_run $impl_name
set impl_status [get_property STATUS [get_runs $impl_name]]
if {![string match "*Complete*" $impl_status]} {
    error "UDP echo bitstream generation did not complete: $impl_status"
}

set bit_path "$project_root/led.runs/$impl_name/${echo_top}.bit"
set bin_path "$project_root/led.runs/$impl_name/${echo_top}.bin"
if {![file exists $bit_path]} { error "bitstream is missing: $bit_path" }

puts "PROJECT=$project_path"
puts "TOP=[get_property top [get_filesets sources_1]]"
puts "SYNTH_RUN=$synth_name"
puts "SYNTH_STATUS=$synth_status"
puts "IMPL_RUN=$impl_name"
puts "IMPL_STATUS=$impl_status"
puts "WNS=$wns"
puts "WHS=$whs"
puts "DRC_BLOCKING_COUNT=[llength $blocking_drc]"
puts "BITSTREAM=[file normalize $bit_path]"
if {[file exists $bin_path]} { puts "BIN=[file normalize $bin_path]" }
puts "REPORT_DIR=[file normalize $report_dir]"
puts "RESULT=UDP_ECHO_BUILD_PASSED"

close_project
exit 0
