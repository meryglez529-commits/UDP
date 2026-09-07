# 板卡契约

## 目标身份

| 项目 | 值 | 证据 | 状态 |
|---|---|---|---|
| 板卡或版本 | DB500 K7 控制平台组合板；实物版本 NOT_CONFIRMED | SRC-001 标注 2019-06-14；SRC-002 文件名标注 MCON v1.3、2021-09-02；未见实物丝印或 BOM 对照 | BLOCKED：资料版本不等于实物版本 |
| FPGA 型号、封装、速度等级 | XC7K325T-2FFG676I | SRC-001 配置页；SRC-005 JTAG 报告 xc7k325t | 已确认 |
| JTAG 链 | 一个 Digilent 目标、一个 xc7k325t 器件 | SRC-005 被动 Vivado 扫描 | 已确认 |
| 配置存储 | 核心板原理图中存在 S25FL256 串行 Flash | SRC-001 | 器件已确认；模式和合格约束待确认 |
| 配置电压与模式 strap | NOT_CONFIRMED | 尚未收集直接证据 | 待确认 |

## Bank 与电压

| Bank 或资源 | 电压或参考 | 接口 | 证据 | 状态 |
|---|---|---|---|---|
| MGT115 与 MGT116 收发器资源 | MGT116 的四组 TX/RX 差分对和两组参考时钟对均已引至核心板连接器；用于 SGMII 的确切 lane 仍未知 | 高速板间连接器与 SGMII 候选链路 | SRC-001 第 5、10 页；SRC-002 第 4 页 | 部分确认；lane 绑定 BLOCKED |
| DDR3 接口 | 可见 64 位 DDR3 信号组 | 外部存储器 | SRC-001 | 部分确认；首个 UDP Demo 不选用 |
| 用户 I/O Bank | 引脚和 VCCO 尚未核对 | GPIO、控制、AFE | 缺少 PCB 引脚导出 | 待确认 |

## 时钟与复位

| 信号 | 来源 | 频率或极性 | FPGA 资源或引脚 | 使用方 | 证据 | 状态 |
|---|---|---|---|---|---|---|
| MGT116_CLK0_P/N 与 CLK1_P/N | MCON 的 AD9517-4 输出 0、输出 2 经板间连接器引至核心板 MGT116 时钟对 | AD9517 输入晶振标注 50.000000 MHz；两个 MGT116 输出频率和 SGMII 所用时钟对均 NOT_CONFIRMED | MGT116 参考时钟输入 | SGMII 候选链路 | SRC-001 第 5、10 页；SRC-002 第 4、8 页 | 部分确认；不得将 50 MHz 输入晶振误作 MGT 参考频率 |
| PHY_RESET_L | MCON 控制接口，接 M88E1111 的 RESETN（K3） | 网络名和器件管脚均表明低有效；复位时序 NOT_CONFIRMED | 用户 I/O 引脚 NOT_CONFIRMED | M88E1111 | SRC-002 第 4、9 页 | 部分确认；时序 BLOCKED |
| PHY_MDC_L、PHY_MDIO_L、PHY_INT_L | MCON 控制接口，分别接 M88E1111 的 MDC（L3）、MDIO（M1）、INTN（L1） | 管脚网络已确认；MDIO 地址、strap、I/O 电气细节 NOT_CONFIRMED | 用户 I/O 引脚 NOT_CONFIRMED | M88E1111 管理接口 | SRC-002 第 4、9 页 | 部分确认；地址和 strap BLOCKED |

## 物理接口契约

| 接口 | 信号或信号组 | 方向 | 引脚或站点 | I/O 标准或资源 | 速率或时钟 | 极性 | 证据 | 状态 |
|---|---|---|---|---|---|---|---|---|
| JTAG | TCK、TMS、TDI、TDO | 双向链路 | FPGA JTAG 引脚 | JTAG | 由工具管理 | 不适用 | SRC-001、SRC-005 | 链已确认；约束未创建 |
| 以太网 PHY | M88E1111 至集成 10/100/1000 RJ45 | 外部网络 | MCON 板 | PHY | 支持 1 Gbps | 以 PHY 原理图为准 | SRC-002 | 器件已确认 |
| SGMII | M88E1111 的 S_IN+/- 接 SGMII_TX_P/N，S_OUT+/- 接 SGMII_RX_P/N；另有 MDC、MDIO、复位、中断 | PHY 端信号端接和 P/N 标识已确认；FPGA 端 GT lane、站点和端到端极性未确认 | 确切 MGT116 通道和 GPIO 站点 NOT_CONFIRMED | GTX 加 LVCMOS 管理 | SGMII 速率与参考频率 NOT_CONFIRMED | PHY 到命名网络的 P/N 已确认；GT 端极性 BLOCKED | SRC-002 第 4、9 页；SRC-001 第 5、10 页 | BLOCKED：不得创建 GTX XDC 或 PCS/PMA IP |
| UDP 协议 | ARP 后基于 IPv4/UDP 的以太网载荷；寄存器读写端口为 FPGA/主机 32000 | 双向 | FPGA 报文通路 | RTL | 固定端口和 DB500 载荷格式已确认；板卡 MAC/IP 与 UDP 校验策略未指定 | 不适用 | SRC-004 第 1、2.1、2.2、2.3 节及表 3 至表 6 | 部分确认；部署网络参数 BLOCKED |

未被最终 PCB 网表或等效权威资料直接确认的站点、电压、频率或差分极性，不得写入 XDC 或 IP 配置。
