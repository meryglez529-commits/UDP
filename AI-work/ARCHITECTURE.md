# FPGA 工程架构

状态：`ACTIVE`

## 项目身份

| 项目 | 当前值 |
|---|---|
| 仓库 | `D:\MyFPGAProject\UDP` |
| Git remote | `git@github.com:meryglez529-commits/UDP.git` |
| 核心板 | MK7XCORE676（图纸 2019-06-14） |
| FPGA | Xilinx Kintex-7 `xc7k325tffg676-2` |
| 工具链 | Vivado 2021.1 |
| 共享 Vivado 工程 | `D:\MyFPGAProject\UDP\fpga\led\led.xpr` |

## 当前 Vivado 上下文

| Fileset | 当前 active top | 当前任务 |
|---|---|---|
| `sources_1` | `udp_data_test_top` | DB500 CONTROL 测试 bank + DATA Jumbo 回环镜像；已完成构建、JTAG 下载与双端口板测 |
| `sim_1` | `ad9517_clock_manager_tb` | AD9517 已验收的初始化与错误场景仿真基线 |

## 工程模块树

当前工程包含多个可切换顶层，其中 `udp_control_test_top` 处于激活状态。下图用状态文字区分当前
板级入口、保留的回归入口和未来规划节点：

```text
ad9517_clock_manager                        [已验收独立顶层；当前未激活]

led_static                                 [工程级根节点；当前未激活]
└── m88e1111_runtime_probe                  [已形成的模块间例化关系]

ethernet_link_top                          [UDP链路层候选顶层；RTL/IP已登记，当前未激活]
├── ethernet_clk_wiz_200m
├── pcs_pma_sgmii_gtx
└── temac_sgmii_tri_speed + RX/TX Ethernet FIFO

udp_top                                    [已登记；CONTROL/DATA 双端口]
├── IBUF + BUFG                            [AA3 100 MHz 统一输入缓冲]
├── ad9517_clock_manager                   [ENABLE_ILA=0；导出合格时钟状态]
├── ethernet_link_top
│   ├── ethernet_clk_wiz_200m              [No_buffer 输入；输出自带 BUFG]
│   ├── pcs_pma_sgmii_gtx
│   └── temac_sgmii_tri_speed + RX/TX Ethernet FIFO
└── udp_transport_dual_host              [共享 ARP/IPv4/UDP parser 与帧级仲裁]
    ├── CONTROL RX4/TX2 固定槽环          [端口 32000]
    └── DATA RX/TX 32 KiB 字节环          [端口 32001；各16描述符]

udp_echo_test_top                           [保留的开发回显与回归外壳]
├── udp_top                                 [完整 AD9517 + Ethernet + UDP 系统]
└── udp_payload_echo                        [透明消费 RX 消息并送回 TX]

db500_udp_application                      [通信架构；CONTROL/DATA 已实现]
├── db500_udp_control                      [协议与六子模块 RTL 已实现并板级验证]
└── DATA 通路                              [透明 payload；双端口/Jumbo 已板级验证]

udp_control_test_top                       [保留；CONTROL 板级验证外壳]
├── udp_top                                [首阶段沿用单端口 32000 和现有消息接口]
├── db500_udp_control                      [已实现的 CONTROL 协议核心]
└── db500_ctrl_test_reg_bank               [已实现的寄存器边界验收模型]

udp_data_test_top                          [当前 active top；双端口板级验证外壳]
├── udp_top                                [CONTROL 32000 + DATA 32001]
├── db500_udp_control + test_reg_bank      [CONTROL 回归]
└── udp_data_echo_bridge                   [DATA 透明 Jumbo 回环]

udp_perf_diag_top                           [未激活；仅用于 sequence 三边界 ILA 归因]
├── udp_top + udp_payload_echo              [与回显镜像相同的数据路径]
├── udp_sequence_order_monitor × 3          [纯旁路：RX frame/RX message/TX frame]
└── ila_udp_sequence                        [125 MHz，任一倒序触发]
```

## 模块登记

| 工程级模块 | 状态 | 代码根/计划根 | 设计文档 |
|---|---|---|---|
| LED | 已实现，可切换为独立顶层 | `led_static` | [`modules/led/MODULE.md`](modules/led/MODULE.md) |
| M88E1111 MDIO | 已实现，当前由 `led_static` 例化 | `m88e1111_runtime_probe` | [`modules/m88e1111-mdio/MODULE.md`](modules/m88e1111-mdio/MODULE.md) |
| AD9517 时钟管理 | RTL、仿真、构建和板级验收通过；OUT0 已外部验收为 125 MHz | `ad9517_clock_manager` | [`modules/ad9517/MODULE.md`](modules/ad9517/MODULE.md) |
| UDP | 固定主机传输 RTL 与回显外壳已通过协议仿真、构建、标准 MTU 回显、十次过载恢复及 797.9 Mbit/s/10 分钟长稳；外部主机发送乱序为已知非阻断缺口 | `ethernet_link_top`、`udp_transport_fixed_host`、`udp_top`、`udp_echo_test_top` | [`modules/udp/MODULE.md`](modules/udp/MODULE.md) |
| UDP 载荷报文槽环 | RTL、单元/集成仿真、完整展开、构建和板级回显通过；RX 4 槽、TX 2 槽均使用同步 BRAM | `udp_rx_payload_ring`、`udp_tx_payload_ring` | [`modules/udp-payload-ring/MODULE.md`](modules/udp-payload-ring/MODULE.md) |
| DB500 UDP 用户通信架构 | CONTROL 测试 bank 与 DATA 双端口已上板；共享 parser/仲裁、差异化缓存、Jumbo 和 watchdog 隔离已实现 | `db500_udp_control`、`udp_transport_dual_host`、DATA rings | [`modules/db500-udp-application/MODULE.md`](modules/db500-udp-application/MODULE.md) |
| DB500 UDP DATA | RTL、XSim、实现和实板通过；仅 1G 全双工，MTU9000/payload8972、RX/TX 各32 KiB/16描述符，Ethernet RX/TX 各16 KiB | `udp_transport_dual_host`、`udp_data_rx_ring`、`udp_data_tx_ring`、`udp_data_test_top` | [`modules/db500-udp-data/MODULE.md`](modules/db500-udp-data/MODULE.md) |
| DB500 UDP CONTROL | 固定 16-Byte QUERY/SET、W=4 有序窗口、去重/重放、静默 watchdog 和跨代恢复已通过仿真、实现、抓包及 60 秒板测；产品寄存器适配待接入 | `db500_udp_control`、`db500_ctrl_watchdog`、`udp_control_test_top` | [`modules/db500-udp-control/MODULE.md`](modules/db500-udp-control/MODULE.md) |

## 模块间关系

### 当前已经形成的关系

- `led_static` 例化 `m88e1111_runtime_probe`，通过 MDC/MDIO 读取 PHY 运行状态。
- `ad9517_clock_manager` 当前独立运行，不例化 LED、MDIO、GT、PCS/PMA、TEMAC 或 UDP 模块。
- `udp_top` 已实际例化 `ad9517_clock_manager` 和 `ethernet_link_top`：前者的 `clock_ready_o`
  控制后者复位释放，AD9517 OUT0 则经板上缓冲和专用 MGTREFCLK 管脚进入 PCS/PMA。
- `udp_top` 同时例化 `udp_transport_dual_host`，在 125 MHz 域收口 Ethernet FIFO 帧接口并对外提供
  CONTROL/DATA 两组载荷接口。
- `udp_top` 对 AA3 只例化一组 `IBUF+BUFG`，同时驱动 AD9517 控制域和配置为 `No_buffer`
  输入的 200 MHz Clocking Wizard，避免一个封装输入被重复缓冲。
- `udp_echo_test_top` 例化 `udp_top + udp_payload_echo`，在不引入产品业务协议的情况下闭合
  RX/TX 消息接口，用于上位机 UDP 回显验收。

### 用户通信关系

- `udp_top` 已扩展为 CONTROL/DATA 两个固定逻辑端口、独立排队资源、
  共享帧级 TX 仲裁和 TX 队列提交完成接口。DATA 透明传输业务已经组好的 UDP payload；业务头、图像分包、
  块身份、存储和重传由外部业务负责。`db500_udp_application` 是架构归属，不是新增同名 RTL。
- `db500_udp_control` 已从总体协议文档分离为独立设计单元。它负责单寄存器 QUERY/SET、W=4
  有序窗口、去重、结果保留与重放、寄存器握手和统一复位边界；不引入长任务、批量事务或业务
  状态机。内部按接收解码、窗口、寄存器执行、回复选择、发送编码和统计拆分为六个单一职责
  子模块，每类状态仅有一个写者。产品寄存器地址表、默认值、位域和读写权限由 CONTROL 外部的
  register adapter/register bank 维护。
- `udp_top` 分离 `comm_base_resetn_o` 与 CONTROL `comm_resetn_o`。独立 watchdog 在
  500 ms CONTROL 静默后清空 CONTROL RX/TX ring、CONTROL 和 register adapter 事务状态，
  不复位 Ethernet client FIFO、产品寄存器数值或业务状态；它不增加普通 CONTROL 复位报文。
- 独立 `udp_control_test_top` 已完成 CONTROL 构建和上板；当前 active top 为
  `udp_data_test_top`，`udp_echo_test_top` 保留为 UDP 回归基线。
- DATA 不增加同名 `db500_udp_data.v`；实现上扩展现有 UDP，
  接口适配或结果逻辑按状态所有权决定是否抽出辅助模块。集成关系归
  用户通信架构，传输层改造归 UDP；DATA 字节环契约归 DATA，既有固定槽实现归 payload ring，存储不重复叠加。
  Jumbo 至少覆盖原工程默认 8172-byte payload（IP MTU 至少 8200）；默认不是全模式最大值，
  主机已核对 JumboPacket=9KB、IPv4 MTU=9000。DATA 首版设计 MTU9000/payload8972，RX/TX 各32 KiB、
  各16描述符，默认 DATA 端口32001；FPGA、共享仲裁与端到端 Jumbo 已完成实板验收。
  集成版仅开放 1G 全双工；保留自动协商，低速连接按通信未就绪处理，不设计低速包长降级。
  当前板级镜像为 `udp_data_test_top`。

### 已形成的 UDP 缓存关系

- `udp_transport_dual_host` 复用 `udp_rx_payload_ring` / `udp_tx_payload_ring` 管理 CONTROL，
  并以 `udp_data_rx_ring` / `udp_data_tx_ring` 管理 DATA 可变长报文；TEMAC Ethernet FIFO 继续保留。

### 当前验证状态与尚未完成项

- 上述组合关系已经进入 RTL/XDC，通过 Vivado/XSim 静态展开，并以重新生成的完整许可 TEMAC
  checkpoint 完成 `udp_echo_test_top` 综合、布局、布线和 bitstream；最终
  `WNS=+0.614 ns`、`WHS=+0.063 ns`，阻断级 DRC 为 0。固定主机 UDP 传输层已按解析、
  RX 消息槽、TX 消息暂存、帧发送和统计五种所有权拆分，外部接口保持不变。
- `udp_top.xdc` 当前已启用并作用于 `udp_echo_test_top`；其中包含 DB500 管脚、AD9517 SPI
  时序、reset synchronizer 例外及 125 MHz GTREFCLK 主时钟约束。
- `udp_transport_fixed_host` 已在 125 MHz 数据面实现 ARP、固定端点 IPv4/UDP、完整载荷槽位和
  强制 UDP checksum，作为单端口回归模块保留。当前 `udp_top` 由 `udp_transport_dual_host`
  直接消费/驱动 Ethernet FIFO AXI4-Stream。
- DATA 镜像实现结果为 `WNS=+0.371 ns`、`WHS=+0.021 ns`、阻断 DRC=0；实板已覆盖
  8972-Byte payload、256 个连续最大包、CONTROL/DATA 共存和 watchdog 隔离。
- `udp_top` 现在暴露载荷消息接口与调试状态；它们仍是未约束的逻辑端口，在业务模块或专用板级
  测试外壳消费这些端口前，不能直接作为最终 bitstream 顶层。
- 业务层接入前的 UDP payload 缓存重构已经完成并成为工程基线；RX 4 槽占 2 个 RAMB36，TX
  2 槽占 1 个 RAMB36。旧 RX/TX 缓存实现已从工程移除。
- UDP 完整 echo pipeline 已在 125 MHz 字节域按 1 Gb/s 线路节奏完成 64-byte 与 1472-byte
  payload 各 1000 包的周期效率仿真，分别达到理论 goodput 且零内部 stall/drop/error。真实板级
  条件已于 2026-09-14 恢复：1472-byte 尽力 offered 达 `956.417 Mbit/s`，过载后降到 100 Mbit/s
  可全量恢复，但 25 Mbit/s 短包、420 Mbit/s/60 秒长包和 893.2 Mbit/s 高负载均出现少量回包
  sequence 倒序。开发专用 ILA 已在 TEMAC RX client AXIS、RX message 和 TEMAC TX client AXIS
  依次捕获完全相同的 `0x5FE,0x600,0x5FF,0x601`，证明 UDP parser、RX/TX 槽环、echo 与 TX
  engine 都保持了输入顺序；异常位于主机 pktmon/NDIS 发送点之后、FPGA UDP parser 之前，状态为
  `EXTERNAL_HOST_TX_ORDERING`。该问题作为已知缺口记录，不阻断吞吐、PPS、丢包、内容完整性、
  过载恢复和长稳测试；当前 ASIX 链路只不承担顺序保证验收。

## 共享板级资源

| 资源 | FPGA/板级连接 | 当前归属或约束 |
|---|---|---|
| 100 MHz 管理时钟 | FPGA `AA3`，Bank 34，`LVCMOS15` | 当前由 `udp_control_test_top/udp_top` 统一缓冲，供 AD9517 控制及 200 MHz Clocking Wizard 使用；CONTROL 顶层关闭 AD9517 ILA |
| LED1 | FPGA `A18`，Bank 15，`LVCMOS33`，高电平点亮 | 多个候选顶层可使用，但只由当前 active top 驱动 |
| MDC/MDIO | `B14/A14`，Bank 16，`LVCMOS33` | `led_static` / M88E1111 模块使用；AD9517 顶层不使用 |
| AD9517 SPI/RESET/LD | `G19/F20/J20/K20/K18/J19` | 当前由 CONTROL 顶层内的 `ad9517_clock_manager` 使用 |
| AD9517 REF_SEL | `J18` | AD9517 profile 忽略硬件选择脚，当前固定输出 0 |
| AD9517 OUT0 | U65 OUT0/OUT0# → SN65LVDS100 → FPGA `D5/D6`；`MGTREFCLK0` 位于 `GTXE2_COMMON_X0Y1` 所在 tile | 当前 active top 已作为 PCS/PMA 的 125 MHz GT 参考时钟，并已建立主时钟约束 |
| SGMII TX/RX | MGT116 lane 3：TX `A3/A4`，RX `B5/B6`；`GTXE2_CHANNEL_X0Y7` | 当前由已启用的 `udp_top.xdc` 约束并用于 CONTROL 顶层 |

## 当前集成边界

当前工程已把 `udp_control_test_top` 作为 active top，用 CONTROL 核心和测试寄存器适配器闭合
`udp_top` 的载荷消息接口；`udp_echo_test_top` 仍作为可切换的回归 top 保留。
AD9517 独立顶层已完成的 U65 配置、读回、校准、判锁、OUT0 使能及 125 MHz 外部验收结论不变。
UDP 固定端点、强制 checksum、标准 MTU 和 1472-byte 最大载荷均已进入 RTL；协议仿真、完整展开、
综合、路由时序和 bitstream 均通过。2026-09-11 已使用公司 TEMAC 完整许可重新生成 IP output
products，并把本次 `udp_echo_test_top.bit` 易失下载到唯一的 `xc7k325t_0`。主机“以太网 2”以
1 Gbps 建链后，向 `192.168.1.20:32000` 发送的 14、256 和 1472-byte 载荷均从同一端点逐字节
正确回显，标准 MTU 边界已完成真实链路验收。高速图像流使用的 RX 4 槽/TX 2 槽报文环、
同步 BRAM、提交/回滚已实现并完成相同的真实链路回归，细节见
`modules/udp-payload-ring/DEVELOPMENT.md`。

CONTROL 测试寄存器路径已经按 `modules/db500-udp-control/MODULE.md` 完成 RTL、仿真、实现、
抓包、板级压力和 watchdog 跨代恢复测试。DATA 双向透明通道、双端口隔离、差异化缓存、
Jumbo Frames 和 TX 队列提交结果也已实现并完成实板回归；产品寄存器与实际数据源适配暂缓。
