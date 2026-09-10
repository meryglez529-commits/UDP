# MCON LED1: J7.A36 -> HT3.B36 -> B150L20P -> FPGA A18.
# Bank 15 is 3.3 V; MCON Q1 turns the LED on for a logic-high FPGA output.
set_property PACKAGE_PIN A18 [get_ports {led1}]
set_property IOSTANDARD LVCMOS33 [get_ports {led1}]

# Core-board 100 MHz oscillator: IC2 -> sys_clk_i -> AA3 (Bank 34, 1.5 V).
set_property PACKAGE_PIN AA3 [get_ports {sys_clk_i}]
set_property IOSTANDARD LVCMOS15 [get_ports {sys_clk_i}]
create_clock -name sys_clk_i -period 10.000 [get_ports {sys_clk_i}]

# M88E1111 Clause 22 management interface:
# PHY_MDC_L -> U82 -> MCON J6.B54 -> CORE HT2.A53 -> B16_L21_P -> B14.
# PHY_MDIO_L -> U82 -> MCON J6.B55 -> CORE HT2.A54 -> B16_L21_N -> A14.
# Bank 16 is 3.3 V. MDIO's open-drain behavior is implemented by an IOBUF;
# the board-level pull-up supplies the released-high level.
set_property PACKAGE_PIN B14 [get_ports {mdc}]
set_property IOSTANDARD LVCMOS33 [get_ports {mdc}]

set_property PACKAGE_PIN A14 [get_ports {mdio}]
set_property IOSTANDARD LVCMOS33 [get_ports {mdio}]

# Configuration Bank 0 is supplied by VCC3V3.
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
