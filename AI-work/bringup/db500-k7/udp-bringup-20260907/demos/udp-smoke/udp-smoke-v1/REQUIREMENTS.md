# Demo requirements

- Demo: udp-smoke-v1
- Interface: ARP, IPv4, UDP reply over SGMII Ethernet
- Required by: INTERFACE_MATRIX.md ARP, IPv4, UDP row
- Question answered: Can the FPGA return a validated UDP response to a host
  over the board's intended 1 Gbps Ethernet path without enabling acquisition
  or motion behavior?
- Official source root: fpga/
- Target board/revision: DB500 K7 control-platform stack / NOT_CONFIRMED

## Plan

The minimal board behavior is:

1. Respond only to ARP for the configured demo IPv4 address.
2. Accept only unfragmented IPv4 UDP packets for the configured destination
   port and local MAC/IP pair.
3. Return a deterministic UDP echo or read-only status payload.
4. Drop malformed, unsupported, broadcast UDP, and every DB500 control,
   acquisition, image-upload, or upgrade command.

The host address observed during preflight is 192.168.1.10/24. The board MAC,
board IP, and UDP port must be taken from the unlocked protocol specification
or an explicitly approved isolated-demo configuration; they are not guessed.

## Acceptance

| Stage | Criterion | Evidence |
|---|---|---|
| Plan | Scope, safe defaults, dependent contract facts, and no-side-effect behavior are documented before source work. | This file and ARCHITECTURE.md |
| Contract | Exact SGMII lane/polarity/reference clock, PHY control parameters, and network settings are confirmed. | BOARD_CONTRACT.md updated with authoritative evidence |
| Simulation | Self-checking tests cover valid ARP and UDP, malformed frame rejection, and deterministic response payload. | Simulation transcript, wave database, and test result |
| Build | Source-driven Vivado run meets timing for every declared clock and emits a candidate bitstream tied to Git revision. | Synth/implementation/timing reports and candidate hash |
| Board | Host resolves ARP and receives the expected UDP reply; packet capture shows correct Ethernet, IPv4, UDP, and payload fields. | Host test log and packet capture summary |

## Scope and safe behavior

Included interfaces are JTAG/configuration, selected board clocks/resets,
M88E1111 management, one SGMII Ethernet link, and the minimal Ethernet/IP/UDP
pipeline. DDR3, ADC/DAC, AFE controls, scanning, motion, image upload, remote
upgrade, and real hardware register writes are excluded. All externally visible
controls remain inactive until a separately accepted phase authorizes them.
