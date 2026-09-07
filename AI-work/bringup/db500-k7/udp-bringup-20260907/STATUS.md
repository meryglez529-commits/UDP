# New-board bring-up status

- State: DISCOVERED
- Board: DB500 K7 control-platform stack
- Board revision: NOT_CONFIRMED
- Bring-up unit: udp-bringup-20260907
- Authorized design root: fpga/
- Product project: NOT_CREATED
- Product top / part: NOT_CREATED / XC7K325T-2FFG676I
- Tool/version: Vivado 2021.1
- Current authority: this file

## Current conclusion

The schematic and protocol inputs support a UDP bring-up path. A passive JTAG
scan confirms that the powered hardware exposes one xc7k325t device through a
Digilent target. The host Ethernet adapter is linked at 1 Gbps. Exact SGMII
lane mapping, reference clock, PHY straps, board revision, and deployed
network parameters remain unresolved; no design or configuration stage may
claim readiness until its applicable contract facts are confirmed.

## Required demos

| Demo | Interface | Required | State | Evidence |
|---|---|---:|---|---|
| configuration-safe | JTAG, configuration, safe GPIO | YES | PLANNED | JTAG chain visible; configuration constraints still open |
| clock-reset | board clock and reset | YES | PLANNED | Schematic only; frequency and pin facts open |
| sgmii-link | M88E1111, SGMII, GTX | YES | PLANNED | PHY and SGMII nets identified; lane and clock mapping open |
| udp-smoke | ARP, IPv4, UDP reply | YES | PLANNED | Protocol specification identified |
| db500-protocol | discovery and read-only register command | YES | PLANNED | Protocol document is locked by Word; detailed fields pending |

## Blockers and next gate

| Blocker | FPGA / hardware / external | Owner | Next evidence |
|---|---|---|---|
| Exact MGT116 to SGMII channel, polarity, and reference frequency absent | FPGA / hardware | Board documentation owner | PCB net export or reviewed connector map |
| PHY address, straps, and reset timing absent | Hardware | Board documentation owner | M88E1111 data sheet and schematic review |
| Protocol document currently locked by another application | External | Document editor | Close the document so its contents and hash can be registered |
| No official source project exists yet | FPGA | Bring-up workflow | Close interface contract, then create the configuration-safe demo |
