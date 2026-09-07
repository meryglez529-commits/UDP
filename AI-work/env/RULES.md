# Engineering and authorization rules

- Project root: D:/MyFPGAProject/UDP
- Official design root: fpga/
- Active bring-up unit: AI-work/bringup/db500-k7/udp-bringup-20260907/
- Remote repository: https://github.com/meryglez529-commits/UDP.git
- FPGA target evidence: XC7K325T-2FFG676I schematic; live JTAG scan reports
  xc7k325t.
- Toolchain: Vivado 2021.1 at D:/Xilinx/Vivado/2021.1.

Authorized writes for this preparation unit are Git metadata, repository
process records, and files under AI-work/ and fpga/. Original root-level
schematics and protocol documents are input evidence and must not be edited or
renamed.

The only board operation authorized in this preparation unit was a passive
JTAG chain scan on 2026-09-07. It found the target but did not program,
refresh, reset, or otherwise change FPGA behavior. Bitstream programming,
PHY register writes, traffic generation, and any product behavior require a
later phase plan and explicit session authorization.

Each phase must have a plan, an execution record, and a separately recorded
acceptance decision before its status may advance.
