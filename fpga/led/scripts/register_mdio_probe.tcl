# Register the approved MDIO probe sources and create its 48-bit ILA in the
# existing led.xpr. This script never creates or clones a Vivado project.
set project_path "D:/MyFPGAProject/UDP/fpga/led/led.xpr"
set project_root "D:/MyFPGAProject/UDP/fpga/led"
open_project $project_path

add_files -norecurse -fileset sources_1 [list \
    "$project_root/led.srcs/sources_1/new/mdio_clause22_reader.v" \
    "$project_root/led.srcs/sources_1/new/m88e1111_runtime_probe.v"]
add_files -norecurse -fileset sim_1 [list \
    "$project_root/led.srcs/sim_1/new/mdio_clause22_model.v"]

set ila_dir "$project_root/led.srcs/sources_1/ip"
if {[llength [get_ips -quiet ila_mdio]] == 0} {
    create_ip -name ila -vendor xilinx.com -library ip -version 6.2 \
        -module_name ila_mdio -dir $ila_dir
    set_property -dict [list \
        CONFIG.C_NUM_OF_PROBES {1} \
        CONFIG.C_PROBE0_WIDTH {48} \
        CONFIG.C_DATA_DEPTH {16384} \
        CONFIG.C_INPUT_PIPE_STAGES {0} \
        CONFIG.C_EN_STRG_QUAL {0} \
        CONFIG.C_ADV_TRIGGER {false} \
        CONFIG.C_TRIGIN_EN {false} \
        CONFIG.C_TRIGOUT_EN {false}] [get_ips ila_mdio]
    generate_target all [get_ips ila_mdio]
}

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
save_project_as -force led $project_root
close_project
