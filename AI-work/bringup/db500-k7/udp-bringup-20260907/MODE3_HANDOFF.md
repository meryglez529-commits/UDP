# Mode 3 handoff

- State: NOT_READY
- Official design root: fpga/
- Product project: NOT_CREATED
- Product top / part: NOT_CREATED / XC7K325T-2FFG676I
- Canonical build entry: NOT_CREATED
- Canonical simulation entry: NOT_CREATED
- Tool/IP versions: Vivado 2021.1; Ethernet IP configuration NOT_CREATED
- Source identity: Git initial commit pending
- Board contract identity: this unit, contract not frozen
- Acceptance matrix identity: this unit, no qualified interfaces
- Qualified release: NONE

## Shared sources and regressions

The future authoritative paths and their consumers are listed in
DEMO_DEPENDENCY_MATRIX.md. No source currently exists at those paths.

## Excluded assets

No generated project, run directory, bitstream, LTX, capture, or test-only top
may enter product source. Candidate and release artifacts do not exist.

## Remaining work and blockers

Close the SGMII lane/clock, PHY, and protocol-network contract facts; complete
the configuration-safe, clock-reset, SGMII, UDP, and protocol demos; then
establish a reproducible product baseline. This handoff may declare MODE3_READY
only after the required board acceptance evidence exists.
