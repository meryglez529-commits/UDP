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

原理图和协议资料支持开展受限 UDP bring-up 的准备。被动 JTAG 扫描已确认上电板卡通过 Digilent 目标暴露一个 xc7k325t 器件；主机以太网口已协商为 1 Gbps。协议已经确认 ARP 扩展发现、UDP 端口 32000 和寄存器帧格式；M88E1111 的 SGMII PHY 端 P/N、MDIO/MDC/RESET 网络以及 MGT116 时钟对也已定位。SGMII 实际 lane、GT 端极性、有效参考频率、PHY strap/MDIO 地址和复位时序、板卡实物版本、部署 MAC/IP 与 UDP 校验策略仍未确认；在相关契约事实确认前，任何设计或配置阶段不得宣称已就绪。

## 必需 Demo

| Demo | 接口 | 必需 | 状态 | 证据 |
|---|---|---:|---|---|
| configuration-safe | JTAG、配置与安全 GPIO | 是 | PLANNED | JTAG 链可见；配置约束待确认 |
| clock-reset | 板级时钟与复位 | 是 | PLANNED | 仅有原理图，频率和引脚待确认 |
| sgmii-link | M88E1111、SGMII 与 GTX | 是 | PLANNED | PHY 与 SGMII 网络已识别；通道和时钟待确认 |
| udp-smoke | ARP、IPv4、UDP 回包 | 是 | PLANNED | 端口 32000 和载荷帧已确认；MAC/IP 和校验策略待确认 |
| db500-protocol | 设备发现与只读寄存器命令 | 是 | PLANNED | 指令 0x0002/0x0003 与大端载荷格式已确认；安全可读寄存器集待确认 |

## 阻塞项与下一关卡

| 阻塞项 | FPGA / 硬件 / 外部 | 责任方 | 下一证据 |
|---|---|---|---|
| 缺少 MGT116 到 SGMII 的确切通道、GT 端极性和参考频率 | FPGA / 硬件 | 板卡资料提供方 | PCB 网表导出或经审核连接器映射，以及 AD9517 输出频率配置 |
| 缺少 PHY 地址、strap 和复位时序 | 硬件 | 板卡资料提供方 | M88E1111 数据手册、原理图 strap 网络复核和无侵入板级观测 |
| 缺少部署 MAC/IP 和 UDP 校验策略 | 外部 | 协议/上位机责任方 | 既有上位机抓包，或书面批准的隔离 Demo 网络配置 |
| 尚无正式源码工程 | FPGA | Bring-up 流程 | 关闭接口契约后创建 configuration-safe Demo |
