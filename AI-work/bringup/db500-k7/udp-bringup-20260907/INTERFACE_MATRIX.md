# Interface matrix

| Interface | Purpose | Required | Contract state | Minimum demo | Acceptance evidence | Current state |
|---|---|---:|---|---|---|---|
| JTAG and configuration | Establish safe, repeatable FPGA image loading | YES | PARTIAL | configuration-safe | JTAG target identity, generated bitstream, verified safe board behavior | PLANNED |
| Board clocks and resets | Provide deterministic logic startup | YES | OPEN | clock-reset | Reviewed XDC and timing report; reset behavior observed | PLANNED |
| SGMII PHY path | Connect M88E1111 through GTX to Ethernet MAC | YES | OPEN | sgmii-link | Link status, MDIO readback, SGMII/PCS lock | PLANNED |
| ARP, IPv4, UDP | Provide interoperable packet transport | YES | PARTIAL | udp-smoke | Host ARP resolution and checked UDP request/reply capture | PLANNED |
| DB500 protocol subset | Exercise the custom command framing safely | YES | PARTIAL | db500-protocol | Device information and read-only register response match the specification | PLANNED |
| DDR3 | Future buffering and acquisition data path | NO for first demo | PARTIAL | NOT_SELECTED | Explicitly excluded from UDP smoke scope | NOT_APPLICABLE |
| ADC/DAC AFE | Future scanning and acquisition behavior | NO for first demo | PARTIAL | NOT_SELECTED | Explicitly excluded from UDP smoke scope | NOT_APPLICABLE |

Every required interface has an assigned demo. Interfaces not selected for the
first UDP demo are neither implicitly validated nor available to product logic.
