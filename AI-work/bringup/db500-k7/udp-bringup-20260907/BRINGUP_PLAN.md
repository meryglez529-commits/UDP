# UDP bring-up plan

## Process rule

Every phase below has three mandatory records: a pre-execution Plan, an
Execution record with commands or board procedure and evidence, and an
Acceptance decision against the criteria written in advance. A later phase
cannot rely on an earlier phase merely because work was attempted.

## Scope and order

| Order | Phase / demo | Plan: question and safe behavior | Execute: bounded work | Accept: required evidence and gate | State |
|---:|---|---|---|---|---|
| 0 | Governance and environment preflight | Establish custody, source provenance, toolchain, Git remote, physical link, and passive JTAG identity. Do not program or send packets. | Initialize Git, register inputs, enumerate host link and JTAG chain. | Documentation is committed and pushed; scan identifies the expected FPGA without changing board state. | ACCEPTED |
| 1 | configuration-safe | Can an authored minimal image be built and safely configured? All nonessential outputs remain benign. | Create canonical project Tcl, base XDC, clock/reset logic, and a configuration-safe GPIO demo after the board contract closes. | Self-checking simulation where applicable, implementation/timing evidence, exact candidate image identity, and explicit board observation. | PLANNED |
| 2 | clock-reset | Are the actual board clocks and resets usable at declared frequencies? Keep external interfaces inactive. | Add reviewed clock constraints and reset sequencing to the shared board layer. | Timing is met for declared clocks; board observation confirms deterministic reset exit. | PLANNED |
| 3 | sgmii-link | Can the FPGA and M88E1111 establish and maintain the intended Ethernet link? No protocol command affects acquisition. | Configure verified PHY management settings and SGMII PCS/PMA plus MAC only after lane, polarity, and clock facts are confirmed. | MDIO identity/status, PCS lock, link status, and error counters recorded. | PLANNED |
| 4 | udp-smoke | Can the board answer a bounded UDP request over ARP and IPv4? Reply data is static or read-only. | Add ARP, IPv4, UDP parser/formatter and a host test script. | Simulation protocol oracle plus packet capture showing correct ARP and UDP reply. | PLANNED |
| 5 | db500-protocol | Can a safe DB500 protocol subset be decoded and answered? Only discovery, information, and read-only register commands are included. | Implement only fields reconciled to the unlocked protocol specification. | Host oracle and capture match the specified frame fields; no control, acquisition, or upgrade command is enabled. | PLANNED |

## Phase 0 execution record

- Git: initialized local main branch with origin
  https://github.com/meryglez529-commits/UDP.git.
- Toolchain: Vivado 2021.1 is installed at
  D:/Xilinx/Vivado/2021.1/bin/vivado.bat.
- Host network: ASIX USB Gigabit Ethernet adapter named 以太网 2 is Up at
  1 Gbps; host IPv4 address is 192.168.1.10/24; zero receive packet errors
  were observed in the preflight query.
- Passive JTAG scan: Vivado opened one target,
  localhost:3121/xilinx_tcf/Digilent/E3077BAA4210, and one device,
  xc7k325t_0 with part xc7k325t. The scan closed the target and Hardware
  Manager afterward. No bitstream, LTX, register write, reset, or capture was
  performed.
- Source integrity: SHA-256 recorded for the three readable PDFs. The Word
  protocol file was locked by another application and is recorded as pending.

## Phase 0 acceptance record

- Criterion: repository process records, source register, contract, matrices,
  plan, and first UDP demo plan are committed and visible on origin/main.
- Decision: ACCEPTED
- Evidence: Git commit d5725bf, chore: establish UDP FPGA bring-up workflow,
  pushed to origin/main on 2026-09-07. The commit includes all readable
  schematic PDFs and all process records; the Word protocol source remains
  outside the commit because its lock prevented safe Git reading.

## Product-baseline promotion plan

| Verified asset | Expected class | Canonical destination | Product consumer |
|---|---|---|---|
| Reviewed board pin and clock constraints | BOARD_FACT | fpga/boards/db500-k7/constraints/ | All demos and product |
| Clock and reset controller | REUSABLE_CORE | fpga/common/clock_reset/ | All synchronous designs |
| SGMII PCS/PMA and MAC configuration | VENDOR_CONFIG | fpga/boards/db500-k7/ip/ | UDP product |
| ARP/IP/UDP transport | REUSABLE_CORE | fpga/common/udp_transport/ | UDP product |
| Protocol parser and soft register map | REUSABLE_CORE | fpga/product/rtl/ | DB500 protocol product |
| GPIO and initial link test tops | TEST_ONLY | Demo-local paths | NONE |

## Authorization boundary

- Official source writes: fpga/ after the relevant contract row reaches
  CONFIRMED and a phase plan is accepted for execution.
- Board programming and active Ethernet traffic: not authorized by this
  preparation phase.
- Hardware-fault boundary: capture one decisive observation, record it under
  hardware-handoff/, and stop FPGA changes that cannot distinguish the cause.
