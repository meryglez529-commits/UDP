# Create/validate the single-probe AD9517 debug ILA in the existing led.xpr.
set expected_vivado_version "2021.1"
set project_file "D:/MyFPGAProject/UDP/fpga/led/led.xpr"
set project_dir "D:/MyFPGAProject/UDP/fpga/led"
set ip_dir "$project_dir/led.srcs/sources_1/ip"
set xci_file "$ip_dir/ila_ad9517/ila_ad9517.xci"

if {[version -short] ne $expected_vivado_version} {
    error "Vivado version mismatch: expected $expected_vivado_version, got [version -short]"
}

open_project $project_file
set ip_matches [get_ips -quiet ila_ad9517]
if {[llength $ip_matches] == 0} {
    file mkdir $ip_dir
    create_ip -name ila -vendor xilinx.com -library ip -version 6.2 \
        -module_name ila_ad9517 -dir $ip_dir
    set_property -dict [list \
        CONFIG.C_NUM_OF_PROBES {1} \
        CONFIG.C_PROBE0_WIDTH {64} \
        CONFIG.C_DATA_DEPTH {16384} \
        CONFIG.C_INPUT_PIPE_STAGES {0} \
        CONFIG.C_EN_STRG_QUAL {0} \
        CONFIG.C_ADV_TRIGGER {false} \
        CONFIG.C_TRIGIN_EN {false} \
        CONFIG.C_TRIGOUT_EN {false}] [get_ips ila_ad9517]
} elseif {[llength $ip_matches] != 1} {
    error "expected one ila_ad9517 IP, found [llength $ip_matches]"
}

generate_target all [get_ips ila_ad9517]
if {![file exists $xci_file]} {
    error "ILA XCI was not generated: $xci_file"
}
update_compile_order -fileset sources_1
puts "ILA_XCI=$xci_file"
puts "RESULT=ILA_AD9517_READY"
close_project
