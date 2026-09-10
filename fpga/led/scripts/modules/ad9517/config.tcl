# Declarative identity for every AD9517 Vivado flow.  Stage scripts consume
# this dictionary instead of repeating project paths, tops, constraints and
# debug-core expectations.
set ad9517_project_dir "D:/MyFPGAProject/UDP/fpga/led"

set ad9517_rtl_files [list \
    "$ad9517_project_dir/led.srcs/sources_1/new/ad9517_clock_manager.v" \
    "$ad9517_project_dir/led.srcs/sources_1/new/ad9517/ad9517_init_ctrl.v" \
    "$ad9517_project_dir/led.srcs/sources_1/new/ad9517/ad9517_profile_rom.v" \
    "$ad9517_project_dir/led.srcs/sources_1/new/ad9517/ad9517_spi_master.v" \
    "$ad9517_project_dir/led.srcs/sources_1/new/ad9517/pll_ld_sync_and_filter.v"]

set ad9517_sim_files [list \
    "$ad9517_project_dir/led.srcs/sim_1/new/ad9517_model.v" \
    "$ad9517_project_dir/led.srcs/sim_1/new/ad9517_clock_manager_tb.v"]

set ad9517_xdc_files [list \
    "$ad9517_project_dir/led.srcs/constrs_1/new/ad9517_clock_manager.xdc"]

set ad9517_ip_files [list \
    "$ad9517_project_dir/led.srcs/sources_1/ip/ila_ad9517/ila_ad9517.xci"]

set ::cowork_module_config [dict create \
    module              ad9517 \
    vivado_version      2021.1 \
    project_dir         $ad9517_project_dir \
    project_file        "$ad9517_project_dir/led.xpr" \
    part                xc7k325tffg676-2 \
    hw_part             xc7k325t \
    design_fileset      sources_1 \
    simulation_fileset  sim_1 \
    constraint_fileset  constrs_1 \
    design_top          ad9517_clock_manager \
    simulation_top      ad9517_clock_manager_tb \
    synth_run           synth_1 \
    impl_run            impl_1 \
    source_manifest     "$ad9517_project_dir/scripts/sources.tcl" \
    active_xdc          "$ad9517_project_dir/led.srcs/constrs_1/new/ad9517_clock_manager.xdc" \
    inactive_xdc        "$ad9517_project_dir/led.srcs/constrs_1/new/led_static.xdc" \
    ila_ip              ila_ad9517 \
    ila_cell            g_ila.u_ila_ad9517 \
    ila_probe           debug_bus \
    ila_probe_width     64 \
    bitstream           "$ad9517_project_dir/led.runs/impl_1/ad9517_clock_manager.bit" \
    probes_file         "$ad9517_project_dir/led.runs/impl_1/ad9517_clock_manager.ltx" \
    report_dir          "$ad9517_project_dir/led.runs/impl_1/reports" \
    hardware_output_dir "$ad9517_project_dir/led.hw/hw_1" \
    rtl_files           $ad9517_rtl_files \
    simulation_files    $ad9517_sim_files \
    xdc_files           $ad9517_xdc_files \
    ip_files            $ad9517_ip_files]
