# Open, validate, and update the user-created LED Vivado project.
# It never creates, overwrites, builds, or programs the project.

set expected_vivado_version "2021.1"
set project_name "led"
set part_name "xc7k325tffg676-2"
set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set project_file [file join $project_dir "${project_name}.xpr"]

if {[version -short] ne $expected_vivado_version} {
    error "Vivado version mismatch: expected $expected_vivado_version, got [version -short]"
}
if {![file exists $project_file]} {
    error "existing user-created project not found: $project_file"
}

open_project $project_file
if {[get_property PART [current_project]] ne $part_name} {
    error "project part mismatch: expected $part_name, got [get_property PART [current_project]]"
}

source [file join $script_dir sources.tcl]
led_register_manifest $project_dir
set_property top led_static [get_filesets sources_1]
update_compile_order -fileset sources_1

# Vivado 2021.1 persists add_files and set_property changes in the project;
# there is no valid no-argument save_project command in that version.
puts "PROJECT=$project_file"
puts "PART=[get_property PART [current_project]]"
puts "RESULT=PROJECT_READY"
close_project
