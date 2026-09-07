# Demo dependency matrix

| Canonical source/configuration | Asset class | Demo consumers | Product consumers | Change invalidates | Latest qualified identity |
|---|---|---|---|---|---|
| fpga/boards/db500-k7/constraints/ | BOARD_FACT | configuration-safe, clock-reset, sgmii-link, udp-smoke-v1 | UDP product | All dependent demos and product build | NOT_CREATED |
| fpga/common/clock_reset/ | REUSABLE_CORE | configuration-safe, clock-reset, sgmii-link, udp-smoke-v1 | UDP product | All clock consumers | NOT_CREATED |
| fpga/boards/db500-k7/ip/sgmii_ethernet/ | VENDOR_CONFIG | sgmii-link, udp-smoke-v1 | UDP product | SGMII and UDP demos plus product build | NOT_CREATED |
| fpga/common/udp_transport/ | REUSABLE_CORE | udp-smoke-v1, db500-protocol | UDP product | UDP and protocol simulation/build/board acceptance | NOT_CREATED |
| fpga/product/rtl/db500_protocol/ | REUSABLE_CORE | db500-protocol | UDP product | Protocol simulation/build/board acceptance | NOT_CREATED |

Before a Mode 3 change to a qualified shared path, every mapped demo must be
marked STALE. No TEST_ONLY or GENERATED item is listed as a product consumer.
