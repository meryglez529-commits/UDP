# Demo status

- State: PLANNED
- Demo: udp-smoke-v1
- Interface: ARP, IPv4, UDP reply over the M88E1111 SGMII link
- Official source path: fpga/demos/udp-smoke/
- Top / part: NOT_CREATED / XC7K325T-2FFG676I
- Tool/version: Vivado 2021.1
- Candidate image: NONE
- Qualified image: NONE

## Stage evidence

| Stage | State | Command/procedure | Evidence | Conclusion |
|---|---|---|---|---|
| Plan | ACCEPTED | REQUIREMENTS.md and ARCHITECTURE.md | This planned unit | Scope limited to safe ARP/UDP reply |
| Contract | OPEN | Reconcile SGMII lane, clock, PHY control, MAC/IP/port | BOARD_CONTRACT.md and OQ-002 through OQ-005 | No implementation permitted |
| Simulation | NOT_RUN | Future self-checking Ethernet packet testbench | NONE | NOT_RUN |
| Synthesis | NOT_RUN | Future source-driven Vivado build | NONE | NOT_RUN |
| Implementation | NOT_RUN | Future source-driven Vivado build | NONE | NOT_RUN |
| Bitstream | NOT_RUN | Candidate image only after build acceptance | NONE | NOT_RUN |
| Board | NOT_RUN | Authorized direct-link host procedure and packet capture | NONE | NOT_RUN |

## Current conclusion and next gate

The demo has an accepted scope but no closed physical contract. Its next gate
is a reviewed MGT116/SGMII lane and reference-clock mapping, followed by an
explicit authorization to create source and test the board.
