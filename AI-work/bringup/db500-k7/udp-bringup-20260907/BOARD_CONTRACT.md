# Board contract

## Target identity

| Item | Value | Evidence | Status |
|---|---|---|---|
| Board/revision | DB500 K7 control-platform stack / NOT_CONFIRMED | Source names and current hardware context | OPEN |
| FPGA part/package/speed | XC7K325T-2FFG676I | SRC-001 configuration page; SRC-005 JTAG reports xc7k325t | CONFIRMED |
| JTAG chain | One Digilent target, one xc7k325t device | SRC-005 passive Vivado scan | CONFIRMED |
| Configuration storage | S25FL256 serial flash on core schematic | SRC-001 | CONFIRMED component; mode and qualified constraints OPEN |
| Configuration voltage and mode straps | NOT_CONFIRMED | No direct contract evidence collected | OPEN |

## Banks and voltages

| Bank/resource | Voltage/reference | Interfaces | Evidence | Status |
|---|---|---|---|---|
| MGT115 and MGT116 transceiver resources | Differential GT resources; exact quad/channel for Ethernet unresolved | High-speed board connector and SGMII candidate | SRC-001, SRC-002 | PARTIAL |
| DDR3 interface | 64-bit DDR3 signal groups visible | External memory | SRC-001 | PARTIAL; not selected for first UDP demo |
| User I/O banks | Pins and VCCO not reconciled | GPIO, control, AFE | No PCB pin export | OPEN |

## Clocks and resets

| Signal | Source | Frequency/polarity | FPGA resource/pin | Consumers | Evidence | Status |
|---|---|---|---|---|---|---|
| MGT116_CLK0_P/N and CLK1_P/N | Core-board connector | Frequency and selected pair NOT_CONFIRMED | MGT116 reference-clock inputs | Candidate SGMII path | SRC-001, SRC-002 | OPEN |
| PHY_RESET_L | MCON control interface | Active-low net visible; timing NOT_CONFIRMED | User I/O pin NOT_CONFIRMED | M88E1111 | SRC-002 | PARTIAL |
| PHY_MDC_L and PHY_MDIO_L | MCON control interface | MDIO electrical details and address NOT_CONFIRMED | User I/O pins NOT_CONFIRMED | M88E1111 management | SRC-002 | PARTIAL |

## Physical-interface contract

| Interface | Signal/group | Direction | Pins/sites | I/O standard/resource | Rate/clock | Polarity | Evidence | Status |
|---|---|---|---|---|---|---|---|---|
| JTAG | TCK, TMS, TDI, TDO | Bidirectional chain | FPGA JTAG pins | JTAG | Tool-managed | N/A | SRC-001, SRC-005 | CONFIRMED chain; constraints not created |
| Ethernet PHY | M88E1111 to integrated 10/100/1000 RJ45 | External network | MCON board | PHY | 1 Gbps capable | Per PHY schematic | SRC-002 | CONFIRMED components |
| SGMII | SGMII_TX_P/N, SGMII_RX_P/N, MDIO, MDC, reset, interrupt | FPGA to PHY | Exact MGT116 lane and GPIO sites NOT_CONFIRMED | GTX plus LVCMOS management | SGMII rate and reference frequency NOT_CONFIRMED | Exact lane polarity NOT_CONFIRMED | SRC-002, SRC-001 | OPEN |
| UDP protocol | Ethernet payload carried over IPv4/UDP after ARP | Bidirectional | FPGA packet pipeline | RTL | Host/board network configuration OPEN | N/A | SRC-004 | PARTIAL |

No inferred site, voltage, frequency, or differential polarity may be used in
an XDC or an IP configuration until directly reconciled against the final board
net export or equivalent authoritative evidence.
