# Demo 复用清单

| 制品或源码 | 类别 | 规范正式路径 | 提升身份 | 产品使用方 | Demo 证据 | 备注 |
|---|---|---|---|---|---|---|
| 板卡约束片段 | BOARD_FACT | fpga/boards/db500-k7/constraints/ | NOT_CREATED | UDP 产品 | 未来已审核契约和板级 Demo | 不得包含推测引脚 |
| 时钟或复位控制器 | REUSABLE_CORE | fpga/common/clock_reset/ | NOT_CREATED | UDP 产品 | 未来时钟复位 Demo | 尚未实现 |
| SGMII PCS/PMA 与 MAC 配置 | VENDOR_CONFIG | fpga/boards/db500-k7/ip/sgmii_ethernet/ | NOT_CREATED | UDP 产品 | 未来 SGMII 链路 Demo | 尚未配置 |
| ARP/IP/UDP 传输层 | REUSABLE_CORE | fpga/common/udp_transport/ | NOT_CREATED | UDP 产品 | 未来 UDP Smoke Demo | 尚未实现 |
| UDP Smoke 顶层和主机测试脚本 | TEST_ONLY | fpga/demos/udp-smoke/ | NOT_CREATED | NONE | 未来 UDP Smoke 板级证据 | 不得直接提升到产品 |
