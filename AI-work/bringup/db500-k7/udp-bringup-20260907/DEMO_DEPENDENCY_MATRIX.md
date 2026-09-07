# Demo 依赖矩阵

| 规范源码或配置 | 资产类别 | Demo 使用方 | 产品使用方 | 变更后需要重新验证 | 最近合格身份 |
|---|---|---|---|---|---|
| fpga/boards/db500-k7/constraints/ | BOARD_FACT | configuration-safe、clock-reset、sgmii-link、udp-smoke-v1 | UDP 产品 | 所有依赖 Demo 与产品构建 | NOT_CREATED |
| fpga/common/clock_reset/ | REUSABLE_CORE | configuration-safe、clock-reset、sgmii-link、udp-smoke-v1 | UDP 产品 | 所有时钟使用方 | NOT_CREATED |
| fpga/boards/db500-k7/ip/sgmii_ethernet/ | VENDOR_CONFIG | sgmii-link、udp-smoke-v1 | UDP 产品 | SGMII 和 UDP Demo 及产品构建 | NOT_CREATED |
| fpga/common/udp_transport/ | REUSABLE_CORE | udp-smoke-v1、db500-protocol | UDP 产品 | UDP 与协议的仿真、构建和板级验收 | NOT_CREATED |
| fpga/product/rtl/db500_protocol/ | REUSABLE_CORE | db500-protocol | UDP 产品 | 协议的仿真、构建和板级验收 | NOT_CREATED |

Mode 3 修改已合格的共享路径前，必须将所有映射 Demo 标记为 STALE。TEST_ONLY 和 GENERATED 资产不得成为产品使用方。
