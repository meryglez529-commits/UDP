# 板卡契约

## 目标身份

| 项目 | 值 | 证据 | 状态 |
|---|---|---|---|
| 板卡或版本 | DB500 K7 控制平台组合板 / NOT_CONFIRMED | 文件名称与当前硬件上下文 | 待确认 |
| FPGA 型号、封装、速度等级 | XC7K325T-2FFG676I | SRC-001 配置页；SRC-005 JTAG 报告 xc7k325t | 已确认 |
| JTAG 链 | 一个 Digilent 目标、一个 xc7k325t 器件 | SRC-005 被动 Vivado 扫描 | 已确认 |
| 配置存储 | 核心板原理图中存在 S25FL256 串行 Flash | SRC-001 | 器件已确认；模式和合格约束待确认 |
| 配置电压与模式 strap | NOT_CONFIRMED | 尚未收集直接证据 | 待确认 |

## Bank 与电压

| Bank 或资源 | 电压或参考 | 接口 | 证据 | 状态 |
|---|---|---|---|---|
| MGT115 与 MGT116 收发器资源 | 差分 GT 资源；用于以太网的确切 Quad 或通道待确认 | 高速板间连接器与 SGMII 候选链路 | SRC-001、SRC-002 | 部分确认 |
| DDR3 接口 | 可见 64 位 DDR3 信号组 | 外部存储器 | SRC-001 | 部分确认；首个 UDP Demo 不选用 |
| 用户 I/O Bank | 引脚和 VCCO 尚未核对 | GPIO、控制、AFE | 缺少 PCB 引脚导出 | 待确认 |

## 时钟与复位

| 信号 | 来源 | 频率或极性 | FPGA 资源或引脚 | 使用方 | 证据 | 状态 |
|---|---|---|---|---|---|---|
| MGT116_CLK0_P/N 与 CLK1_P/N | 核心板连接器 | 频率与所用时钟对均 NOT_CONFIRMED | MGT116 参考时钟输入 | SGMII 候选链路 | SRC-001、SRC-002 | 待确认 |
| PHY_RESET_L | MCON 控制接口 | 已见低有效网络；时序 NOT_CONFIRMED | 用户 I/O 引脚 NOT_CONFIRMED | M88E1111 | SRC-002 | 部分确认 |
| PHY_MDC_L 与 PHY_MDIO_L | MCON 控制接口 | MDIO 电气细节与地址 NOT_CONFIRMED | 用户 I/O 引脚 NOT_CONFIRMED | M88E1111 管理接口 | SRC-002 | 部分确认 |

## 物理接口契约

| 接口 | 信号或信号组 | 方向 | 引脚或站点 | I/O 标准或资源 | 速率或时钟 | 极性 | 证据 | 状态 |
|---|---|---|---|---|---|---|---|---|
| JTAG | TCK、TMS、TDI、TDO | 双向链路 | FPGA JTAG 引脚 | JTAG | 由工具管理 | 不适用 | SRC-001、SRC-005 | 链已确认；约束未创建 |
| 以太网 PHY | M88E1111 至集成 10/100/1000 RJ45 | 外部网络 | MCON 板 | PHY | 支持 1 Gbps | 以 PHY 原理图为准 | SRC-002 | 器件已确认 |
| SGMII | SGMII_TX_P/N、SGMII_RX_P/N、MDIO、MDC、复位、中断 | FPGA 至 PHY | 确切 MGT116 通道和 GPIO 站点 NOT_CONFIRMED | GTX 加 LVCMOS 管理 | SGMII 速率与参考频率 NOT_CONFIRMED | 确切差分极性 NOT_CONFIRMED | SRC-002、SRC-001 | 待确认 |
| UDP 协议 | ARP 后基于 IPv4/UDP 的以太网载荷 | 双向 | FPGA 报文通路 | RTL | 主机与板卡网络配置待确认 | 不适用 | SRC-004 | 部分确认 |

未被最终 PCB 网表或等效权威资料直接确认的站点、电压、频率或差分极性，不得写入 XDC 或 IP 配置。
