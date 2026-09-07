# Demo reuse manifest

| Artifact/source | Class | Canonical official path | Promoted identity | Product consumer | Demo evidence | Notes |
|---|---|---|---|---|---|---|
| Board constraint fragments | BOARD_FACT | fpga/boards/db500-k7/constraints/ | NOT_CREATED | UDP product | Future reviewed contract and board demo | Must not contain inferred pins |
| Clock/reset controller | REUSABLE_CORE | fpga/common/clock_reset/ | NOT_CREATED | UDP product | Future clock-reset demo | Not yet implemented |
| SGMII PCS/PMA and MAC configuration | VENDOR_CONFIG | fpga/boards/db500-k7/ip/sgmii_ethernet/ | NOT_CREATED | UDP product | Future SGMII link demo | Not yet configured |
| ARP/IP/UDP transport | REUSABLE_CORE | fpga/common/udp_transport/ | NOT_CREATED | UDP product | Future UDP smoke demo | Not yet implemented |
| UDP smoke top and host test script | TEST_ONLY | fpga/demos/udp-smoke/ | NOT_CREATED | NONE | Future UDP smoke board evidence | Never promote directly to product |
