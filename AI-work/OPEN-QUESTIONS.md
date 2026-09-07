# 待确认问题

| 编号 | 问题 | 影响 | 责任人或下一证据 | 状态 |
|---|---|---|---|---|
| OQ-001 | 实际装配板卡的版本，以及 CORE、MCON、AFE 的具体版本是什么？ | 约束和验收必须对应明确硬件版本。 | 确认板卡丝印、BOM 或 PCB 版本。 | 待确认 |
| OQ-002 | M88E1111 的 SGMII 命名网络实际连接到哪一路 MGT116 TX/RX、GT 端差分极性和所用时钟对？PHY 端到 MCON J6 的 B26/B27/A26/A27 已确认；按 J5/HT1、J7/HT3 的已验证对照规则映射到 HT2 时，N/P 与 GND 出现冲突，详见 `SGMII_SIGNAL_TRACE.md`。 | 创建 GTX 约束和 PCS/PMA 配置前必须明确。 | 提供与实物版本一致的 PCB 网表/ODB++，或核心板 HT2 与 MCON J6 的 pin-to-pin 装配表。 | BLOCKED_BY_SOURCE_CONFLICT |
| OQ-003 | M88E1111 的 strap 配置、MDIO 地址、复位时序和有效 SGMII 参考时钟频率是什么？MDC/MDIO/INTN/RESETN 物理网络已由 SRC-002 第 9 页确认；AD9517 输入为 50 MHz 不足以确认 MGT 输出频率。 | 安全配置和验证 PHY 所必需。 | 提供 M88E1111 数据手册、原理图 strap 网络复核、AD9517 输出频率配置和无侵入板级观测。 | BLOCKED |
| OQ-004 | 已部署 DB500 协议使用的 MAC、板卡 IP 和 UDP 校验策略是什么？协议已确认寄存器读写端口为 32000，且载荷中无应用层校验字段。 | 与现有上位机互通所必需。 | 提供既有上位机抓包，或书面批准的隔离 Demo MAC/IP 与 IPv4/UDP 校验策略。 | BLOCKED |
| OQ-005 | Vivado 2021.1 中 SGMII 和以太网 MAC 所需 IP 的具体配置及许可状态是什么？ | 决定可复现的实现方案。 | 在 OQ-002 与 OQ-003 关闭后再创建 IP 配置。 | 待确认 |
