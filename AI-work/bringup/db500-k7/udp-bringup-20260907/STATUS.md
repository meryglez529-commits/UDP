# 新板卡 bring-up 状态

以下 State 行为校验器读取的机器字段，状态码保持英文。

- State: DISCOVERED
- 板卡：DB500 K7 控制平台组合板
- 板卡版本：NOT_CONFIRMED
- Bring-up 单元：udp-bringup-20260907
- 已授权设计根目录：fpga/
- 产品工程：NOT_CREATED
- 产品顶层 / FPGA：NOT_CREATED / XC7K325T-2FFG676I
- 工具 / 版本：Vivado 2021.1
- 当前状态唯一依据：本文件

## 当前结论

原理图和协议资料支持开展受限 UDP bring-up 的准备。被动 JTAG 扫描已确认上电板卡通过 Digilent 目标暴露一个 xc7k325t 器件；主机以太网口已协商为 1 Gbps。协议已经确认 ARP 扩展发现、UDP 端口 32000 和寄存器帧格式；M88E1111 的 SGMII PHY 端 P/N、MDIO/MDC/RESET 网络以及 MGT116 时钟对也已定位。用户确认本实物组合板的跨板配对后，SGMII 已闭合为 MGT116 lane 3：`J6 B26/B27 → HT2 A25/A26 → MGT116_TX3_N/P`，`J6 A26/A27 → HT2 B25/B26 → MGT116_RX3_N/P`。故不再存在 lane 或 GT 极性冲突；但有效参考频率、PHY strap/MDIO 地址和复位时序、板卡实物版本、部署 MAC/IP 与 UDP 校验策略仍未确认。在这些剩余契约事实确认前，任何设计或配置阶段不得宣称已就绪。

## 必需 Demo

| Demo | 接口 | 必需 | 状态 | 证据 |
|---|---|---:|---|---|
| configuration-safe | JTAG、配置与安全 GPIO | 是 | PLANNED | JTAG 链可见；配置约束待确认 |
| clock-reset | 板级时钟与复位 | 是 | PLANNED | 仅有原理图，频率和引脚待确认 |
| sgmii-link | M88E1111、SGMII 与 GTX | 是 | PLANNED | MGT116 lane 3、TX/RX 与 P/N 已确认；参考时钟及 PHY 管理参数待确认 |
| udp-smoke | ARP、IPv4、UDP 回包 | 是 | PLANNED | 端口 32000 和载荷帧已确认；MAC/IP 和校验策略待确认 |
| db500-protocol | 设备发现与只读寄存器命令 | 是 | PLANNED | 指令 0x0002/0x0003 与大端载荷格式已确认；安全可读寄存器集待确认 |

## 阻塞项与下一关卡

| 阻塞项 | FPGA / 硬件 / 外部 | 责任方 | 下一证据 |
|---|---|---|---|
| 缺少 MGT116 实际参考频率；lane 3 与 GT 端极性已由用户硬件确认 | FPGA / 硬件 | 板卡资料提供方 | AD9517 输出频率配置；PCB 网表/ODB++ 或 HT2-J6 pin-to-pin 表用于正式发布前的书面追溯 |
| 缺少 PHY 地址、strap 和复位时序 | 硬件 | 板卡资料提供方 | M88E1111 数据手册、原理图 strap 网络复核和无侵入板级观测 |
| 缺少部署 MAC/IP 和 UDP 校验策略 | 外部 | 协议/上位机责任方 | 既有上位机抓包，或书面批准的隔离 Demo 网络配置 |
| 尚无正式源码工程 | FPGA | Bring-up 流程 | 关闭接口契约后创建 configuration-safe Demo |
