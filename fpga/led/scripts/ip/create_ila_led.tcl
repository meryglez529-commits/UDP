# Create the approved RTL-instantiated LED ILA in the existing project.
# Usage: vivado -mode batch -source create_ila_led.tcl

set expected_vivado_version "2021.1"
set project_name "led"
set part_name "xc7k325tffg676-2"
set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir .. ..]]
set project_file [file join $project_dir "${project_name}.xpr"]
set ip_dir [file join $project_dir led.srcs sources_1 ip]
set xci_file [file join $ip_dir ila_led ila_led.xci]

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

set ip_matches [get_ips -quiet ila_led]
if {[llength $ip_matches] == 0} {
    file mkdir $ip_dir
    create_ip -name ila -vendor xilinx.com -library ip -module_name ila_led -dir $ip_dir
    set_property -dict [list \
        CONFIG.C_DATA_DEPTH {1024} \
        CONFIG.C_NUM_OF_PROBES {1} \
        CONFIG.C_PROBE0_WIDTH {1} \
        CONFIG.C_PROBE0_TYPE {0}] [get_ips ila_led]
} elseif {[llength $ip_matches] != 1} {
    error "ILA IP is ambiguous: expected one ila_led, found [llength $ip_matches]"
} else {
    foreach {property expected} {
        CONFIG.C_DATA_DEPTH 1024
        CONFIG.C_NUM_OF_PROBES 1
        CONFIG.C_PROBE0_WIDTH 1
        CONFIG.C_PROBE0_TYPE 0
    } {
        set actual [get_property $property [get_ips ila_led]]
        if {$actual ne $expected} {
            error "existing ila_led property mismatch: $property expected $expected, got $actual"
        }
    }
}

generate_target all [get_ips ila_led]

if {![file exists $xci_file]} {
    error "ILA XCI was not generated: $xci_file"
}
if {[llength [get_files -quiet $xci_file]] == 0} {
    add_files -norecurse $xci_file
}
update_compile_order -fileset sources_1
puts "ILA_XCI=$xci_file"
puts "RESULT=ILA_IP_READY"
close_project
