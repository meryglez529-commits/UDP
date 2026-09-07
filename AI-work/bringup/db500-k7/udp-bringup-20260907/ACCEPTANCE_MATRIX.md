# Interface acceptance matrix

| Interface | Required | Demo unit | Contract | Build | Ready for board | Board result | Waiver | Release/evidence |
|---|---:|---|---|---|---|---|---|---|
| Governance and environment preflight | YES | udp-bringup-20260907 | PARTIAL | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE | NONE | ACCEPTED: d5725bf on origin/main |
| JTAG and configuration | YES | configuration-safe | PARTIAL | NOT_RUN | NO | NOT_RUN | NONE | Candidate image not created |
| Board clocks and resets | YES | clock-reset | OPEN | NOT_RUN | NO | NOT_RUN | NONE | No qualified XDC |
| SGMII PHY path | YES | sgmii-link | OPEN | NOT_RUN | NO | NOT_RUN | NONE | Lane and PHY facts open |
| ARP, IPv4, UDP | YES | udp-smoke-v1 | PARTIAL | NOT_RUN | NO | NOT_RUN | NONE | Planned only |
| DB500 protocol subset | YES | db500-protocol | PARTIAL | NOT_RUN | NO | NOT_RUN | NONE | Protocol document locked |

Build evidence, link indication, and schematic review are not substitutes for a
board result. No interface has a BOARD_PASS result in this preparation unit.
