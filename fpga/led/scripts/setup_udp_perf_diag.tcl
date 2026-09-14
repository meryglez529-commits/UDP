set expected_vivado_version "2021.1"
set project_path "D:/MyFPGAProject/UDP/fpga/led/led.xpr"
set project_root "D:/MyFPGAProject/UDP/fpga/led"

if {[version -short] ne $expected_vivado_version} {
    error "Vivado version mismatch: expected $expected_vivado_version, got [version -short]"
}

open_project $project_path

# Remove two obsolete project entries left behind when the former packet
# buffers were replaced by the RX/TX payload rings.  Only missing file entries
# are removed; no filesystem content is deleted.
foreach obsolete_name {udp_rx_message_fifo.v udp_tx_message_buffer.v} {
    set obsolete_files [get_files -quiet -filter "NAME =~ *$obsolete_name"]
    if {[llength $obsolete_files] != 0} {
        remove_files $obsolete_files
    }
}

set monitor_file "$project_root/led.srcs/sources_1/new/ethernet/udp_sequence_order_monitor.v"
set diag_top_file "$project_root/led.srcs/sources_1/new/udp_perf_diag_top.v"
set monitor_tb_file "$project_root/led.srcs/sim_1/new/udp_sequence_order_monitor_tb.v"

foreach path [list $monitor_file $diag_top_file] {
    if {[llength [get_files -quiet $path]] == 0} {
        add_files -norecurse -fileset sources_1 $path
    }
}
if {[llength [get_files -quiet $monitor_tb_file]] == 0} {
    add_files -norecurse -fileset sim_1 $monitor_tb_file
}

set ila_xci "$project_root/led.srcs/sources_1/ip/ila_udp_sequence/ila_udp_sequence.xci"
if {![file exists $ila_xci]} {
    create_ip -name ila -vendor xilinx.com -library ip -version 6.2 \
        -module_name ila_udp_sequence \
        -dir "$project_root/led.srcs/sources_1/ip"
    set ila_file [get_ips ila_udp_sequence]
    set_property -dict [list \
        CONFIG.C_DATA_DEPTH {2048} \
        CONFIG.C_NUM_OF_PROBES {23} \
        CONFIG.C_PROBE0_WIDTH {1} \
        CONFIG.C_PROBE1_WIDTH {1} \
        CONFIG.C_PROBE2_WIDTH {32} \
        CONFIG.C_PROBE3_WIDTH {32} \
        CONFIG.C_PROBE4_WIDTH {32} \
        CONFIG.C_PROBE5_WIDTH {32} \
        CONFIG.C_PROBE6_WIDTH {32} \
        CONFIG.C_PROBE7_WIDTH {1} \
        CONFIG.C_PROBE8_WIDTH {32} \
        CONFIG.C_PROBE9_WIDTH {32} \
        CONFIG.C_PROBE10_WIDTH {32} \
        CONFIG.C_PROBE11_WIDTH {32} \
        CONFIG.C_PROBE12_WIDTH {32} \
        CONFIG.C_PROBE13_WIDTH {1} \
        CONFIG.C_PROBE14_WIDTH {32} \
        CONFIG.C_PROBE15_WIDTH {32} \
        CONFIG.C_PROBE16_WIDTH {32} \
        CONFIG.C_PROBE17_WIDTH {32} \
        CONFIG.C_PROBE18_WIDTH {32} \
        CONFIG.C_PROBE19_WIDTH {5} \
        CONFIG.C_PROBE20_WIDTH {11} \
        CONFIG.C_PROBE21_WIDTH {11} \
        CONFIG.C_PROBE22_WIDTH {11}] $ila_file
    generate_target all $ila_file
} elseif {[llength [get_files -quiet $ila_xci]] == 0} {
    add_files -norecurse -fileset sources_1 $ila_xci
}

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "RESULT=UDP_PERF_DIAG_PROJECT_READY"
close_project
exit 0
