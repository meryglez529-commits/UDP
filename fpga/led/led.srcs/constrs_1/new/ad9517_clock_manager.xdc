# AD9517-only validation top: ad9517_clock_manager
# Kintex-7 xc7k325tffg676-2 on MK7XCORE676 + MCON.

# Existing core-board oscillator.  All control RTL, SPI timing and ILA use this
# single 100 MHz domain; the AD9517-generated 125 MHz clock is not received by
# FPGA logic in this validation image.
set_property PACKAGE_PIN AA3 [get_ports {sys_clk_i}]
set_property IOSTANDARD LVCMOS15 [get_ports {sys_clk_i}]
create_clock -name sys_clk_i -period 10.000 [get_ports {sys_clk_i}]

# MCON LED1: J7.A36 -> HT3.B36 -> FPGA A18, active high.
set_property PACKAGE_PIN A18 [get_ports {led1}]
set_property IOSTANDARD LVCMOS33 [get_ports {led1}]

# AD9517 U65 serial/configuration interface through MCON J7 / core HT3.
set_property PACKAGE_PIN G19 [get_ports {pll_cs_n_o}]
set_property PACKAGE_PIN F20 [get_ports {pll_sclk_o}]
set_property PACKAGE_PIN K20 [get_ports {pll_sdo_i}]
set_property PACKAGE_PIN J20 [get_ports {pll_sdio_o}]
set_property PACKAGE_PIN J18 [get_ports {pll_ref_sel_o}]
set_property PACKAGE_PIN J19 [get_ports {pll_ld_i}]
set_property PACKAGE_PIN K18 [get_ports {pll_reset_n_o}]

set_property IOSTANDARD LVCMOS33 [get_ports {
    pll_cs_n_o pll_sclk_o pll_sdo_i pll_sdio_o
    pll_ref_sel_o pll_ld_i pll_reset_n_o
}]

# Slow edges are sufficient at 5 MHz and reduce unnecessary board-level edge
# rate.  Eight-mA drive is also used for the status LED output.
set_property DRIVE 8 [get_ports {
    led1 pll_cs_n_o pll_sclk_o pll_sdio_o pll_ref_sel_o pll_reset_n_o
}]
set_property SLEW SLOW [get_ports {
    led1 pll_cs_n_o pll_sclk_o pll_sdio_o pll_ref_sel_o pll_reset_n_o
}]

# Describe the source-synchronous serial waveform produced from sys_clk_i.
# The implementation uses clock-enable pulses and does not use pll_sclk_o as
# an internal FPGA clock.  This generated clock is solely an interface timing
# reference for the external AD9517 pins.
create_generated_clock -name pll_sclk_gen \
    -source [get_ports {sys_clk_i}] -divide_by 20 [get_ports {pll_sclk_o}]

# SCLK is a data pin driven by clock-enable logic, not an internal capture
# clock.  SDIO changes and SDO samples are deliberately separated by one
# 100 ns SCLK half-period.  A conventional set_input/output_delay constraint
# against the generated waveform would make Vivado pair those I/O paths with
# adjacent 100 MHz system-clock edges and would therefore model a false 10 ns
# requirement.  Bound only the FPGA datapath delay to 20 ns here; this leaves
# at least 80 ns of the protocol half-period for package, board and AD9517
# timing.  Functional edge placement is checked by the SPI RTL simulation.
set_max_delay -datapath_only -from [get_ports {pll_sdo_i}] 20.000
set_max_delay -datapath_only \
    -from [get_clocks {sys_clk_i}] -to [get_ports {
    pll_cs_n_o pll_sclk_o pll_sdio_o pll_ref_sel_o pll_reset_n_o
}] 20.000

# LED1 is a human-visible status indicator and has no external sampling
# requirement.  Mark it intentionally asynchronous rather than leaving an
# unexplained unconstrained output in check_timing.
set_false_path -to [get_ports {led1}]

# PLL_LD is asynchronous and enters a marked two-flop synchronizer before it
# reaches the qualification logic.  Only this asynchronous input path is cut.
set_false_path -from [get_ports {pll_ld_i}]

# Configuration Bank 0 is supplied by VCC3V3.
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
