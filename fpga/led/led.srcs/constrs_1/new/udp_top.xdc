# DB500 board-level UDP pin and timing constraints.  The physical port names
# are shared by udp_top and udp_echo_test_top.  Keep this file disabled while
# the validated AD9517-only top remains active; enable it only for a UDP build.

set_property PACKAGE_PIN AA3 [get_ports {sys_clk_i}]
set_property IOSTANDARD LVCMOS15 [get_ports {sys_clk_i}]
create_clock -name sys_clk_i -period 10.000 [get_ports {sys_clk_i}]

set_property PACKAGE_PIN A18 [get_ports {led1}]
set_property IOSTANDARD LVCMOS33 [get_ports {led1}]

set_property PACKAGE_PIN G19 [get_ports {pll_cs_n_o}]
set_property PACKAGE_PIN F20 [get_ports {pll_sclk_o}]
set_property PACKAGE_PIN K20 [get_ports {pll_sdo_i}]
set_property PACKAGE_PIN J20 [get_ports {pll_sdio_o}]
set_property PACKAGE_PIN J18 [get_ports {pll_ref_sel_o}]
set_property PACKAGE_PIN J19 [get_ports {pll_ld_i}]
set_property PACKAGE_PIN K18 [get_ports {pll_reset_n_o}]
set_property IOSTANDARD LVCMOS33 [get_ports {
    pll_cs_n_o pll_sclk_o pll_sdo_i pll_sdio_o pll_ref_sel_o pll_ld_i pll_reset_n_o
}]

# MGT116 lane 3 and MGTREFCLK0.  MGT pins do not receive an LVCMOS I/O
# standard; the PCS/PMA XCI owns the GTX electrical configuration.
set_property PACKAGE_PIN A3 [get_ports {sgmii_txn_o}]
set_property PACKAGE_PIN A4 [get_ports {sgmii_txp_o}]
set_property PACKAGE_PIN B5 [get_ports {sgmii_rxn_i}]
set_property PACKAGE_PIN B6 [get_ports {sgmii_rxp_i}]
set_property PACKAGE_PIN D5 [get_ports {gtrefclk_n_i}]
set_property PACKAGE_PIN D6 [get_ports {gtrefclk_p_i}]

# AD9517 OUT0 supplies the 125 MHz differential reference used by the GTX.
# The PCS/PMA generated XDC constrains TXOUTCLK/RXOUTCLK but, just like its
# example-design XDC, the board-level design must declare the incoming GT
# reference clock so Vivado can derive and validate the transceiver clocks.
create_clock -add -name gtrefclk_125m -period 8.000 [get_ports {gtrefclk_p_i}]

set_property DRIVE 8 [get_ports {
    led1 pll_cs_n_o pll_sclk_o pll_sdio_o pll_ref_sel_o pll_reset_n_o
}]
set_property SLEW SLOW [get_ports {
    led1 pll_cs_n_o pll_sclk_o pll_sdio_o pll_ref_sel_o pll_reset_n_o
}]

# The SPI master creates a 5 MHz pin waveform with clock-enable logic while
# remaining entirely in the buffered 100 MHz system domain.  This generated
# clock is an external-interface timing reference, not an internal RTL clock.
create_generated_clock -name pll_sclk_gen \
    -source [get_ports {sys_clk_i}] -divide_by 20 [get_ports {pll_sclk_o}]

# Match the validated AD9517-only timing model.  SDIO changes and SDO samples
# are separated by a 100 ns SCLK half-period; bounding only the FPGA datapath
# to 20 ns avoids an artificial adjacent-edge 10 ns requirement.
set_max_delay -datapath_only -from [get_ports {pll_sdo_i}] 20.000
set_max_delay -datapath_only \
    -from [get_clocks {sys_clk_i}] -to [get_ports {
    pll_cs_n_o pll_sclk_o pll_sdio_o pll_ref_sel_o pll_reset_n_o
}] 20.000

set_false_path -to [get_ports {led1}]
set_false_path -from [get_ports {pll_ld_i}]

# Both link reset pipelines deliberately use asynchronous assertion and
# synchronous deassertion.  Recovery/removal timing on their PRE pins is not a
# synchronous data-path requirement; the following is the same exception used
# by the AMD PCS/PMA and TEMAC example designs for reset synchronizers.
set_false_path -to [get_pins -quiet -of_objects \
    [get_cells -hierarchical -filter {NAME =~ */pcs_reset_pipe_reg*}] \
    -filter {REF_PIN_NAME == PRE}]
set_false_path -to [get_pins -quiet -of_objects \
    [get_cells -hierarchical -filter {NAME =~ */mac_reset_pipe_reg*}] \
    -filter {REF_PIN_NAME == PRE}]

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
