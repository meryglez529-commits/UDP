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

原理图和协议资料支持开展 UDP bring-up。被动 JTAG 扫描已确认上电板卡通过 Digilent 目标暴露一个 xc7k325t 器件；主机以太网口已协商为 1 Gbps。SGMII 实际通道、参考时钟、PHY strap、板卡版本和部署网络参数仍未确认；在相关契约事实确认前，任何设计或配置阶段不得宣称已就绪。

## 必需 Demo

| Demo | 接口 | 必需 | 状态 | 证据 |
|---|---|---:|---|---|
| configuration-safe | JTAG、配置与安全 GPIO | 是 | PLANNED | JTAG 链可见；配置约束待确认 |
| clock-reset | 板级时钟与复位 | 是 | PLANNED | 仅有原理图，频率和引脚待确认 |
| sgmii-link | M88E1111、SGMII 与 GTX | 是 | PLANNED | PHY 与 SGMII 网络已识别；通道和时钟待确认 |
| udp-smoke | ARP、IPv4、UDP 回包 | 是 | PLANNED | 已找到协议规范 |
| db500-protocol | 设备发现与只读寄存器命令 | 是 | PLANNED | 协议 Word 正被占用，详细字段待确认 |

## 阻塞项与下一关卡

| 阻塞项 | FPGA / 硬件 / 外部 | 责任方 | 下一证据 |
|---|---|---|---|
| 缺少 MGT116 到 SGMII 的确切通道、极性和参考频率 | FPGA / 硬件 | 板卡资料提供方 | PCB 网表导出或经审核连接器映射 |
| 缺少 PHY 地址、strap 和复位时序 | 硬件 | 板卡资料提供方 | M88E1111 数据手册和原理图复核 |
| 协议 Word 文档正被其他程序占用 | 外部 | 文档编辑者 | 关闭文档，以登记内容和哈希 |
| 尚无正式源码工程 | FPGA | Bring-up 流程 | 关闭接口契约后创建 configuration-safe Demo |
