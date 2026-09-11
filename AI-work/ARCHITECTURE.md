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
| `sources_1` | `udp_echo_test_top` | 固定上位机 UDP 板级回显测试；已完成许可构建、JTAG 下载与主机回显实测 |
| `sim_1` | `ad9517_clock_manager_tb` | AD9517 已验收的初始化与错误场景仿真基线 |

## 工程模块树

当前工程存在五个可选顶层，其中 `udp_echo_test_top` 处于激活状态：

```text
ad9517_clock_manager                        [已验收独立顶层；当前未激活]

led_static                                 [工程级根节点；当前未激活]
└── m88e1111_runtime_probe                  [已形成的模块间例化关系]

ethernet_link_top                          [UDP链路层候选顶层；RTL/IP已登记，当前未激活]
├── ethernet_clk_wiz_200m
├── pcs_pma_sgmii_gtx
└── temac_sgmii_tri_speed + RX/TX Ethernet FIFO

udp_top                                    [已登记的组合展开骨架；当前未激活]
├── IBUF + BUFG                            [AA3 100 MHz 统一输入缓冲]
├── ad9517_clock_manager                   [ENABLE_ILA=0；导出合格时钟状态]
├── ethernet_link_top
│   ├── ethernet_clk_wiz_200m              [No_buffer 输入；输出自带 BUFG]
│   ├── pcs_pma_sgmii_gtx
│   └── temac_sgmii_tri_speed + RX/TX Ethernet FIFO
└── udp_transport_fixed_host            [ARP/IPv4/UDP + 完整载荷槽位]

udp_echo_test_top                           [当前 active top；开发回显外壳]
├── udp_top                                 [完整 AD9517 + Ethernet + UDP 系统]
└── udp_payload_echo                        [透明消费 RX 消息并送回 TX]
```

## 模块登记

| 工程级模块 | 状态 | 代码根/计划根 | 设计文档 |
|---|---|---|---|
| LED | 已实现，可切换为独立顶层 | `led_static` | [`modules/led/MODULE.md`](modules/led/MODULE.md) |
| M88E1111 MDIO | 已实现，当前由 `led_static` 例化 | `m88e1111_runtime_probe` | [`modules/m88e1111-mdio/MODULE.md`](modules/m88e1111-mdio/MODULE.md) |
| AD9517 时钟管理 | RTL、仿真、构建和板级验收通过；OUT0 已外部验收为 125 MHz | `ad9517_clock_manager` | [`modules/ad9517/MODULE.md`](modules/ad9517/MODULE.md) |
| UDP | 固定主机传输 RTL 与回显测试外壳已通过协议仿真、完整展开、许可构建、JTAG 下载及标准 MTU 板级回显 | `ethernet_link_top`、`udp_transport_fixed_host`、`udp_top`、`udp_echo_test_top`（当前激活） | [`modules/udp/MODULE.md`](modules/udp/MODULE.md) |

## 模块间关系

### 当前已经形成的关系

- `led_static` 例化 `m88e1111_runtime_probe`，通过 MDC/MDIO 读取 PHY 运行状态。
- `ad9517_clock_manager` 当前独立运行，不例化 LED、MDIO、GT、PCS/PMA、TEMAC 或 UDP 模块。
- `udp_top` 已实际例化 `ad9517_clock_manager` 和 `ethernet_link_top`：前者的 `clock_ready_o`
  控制后者复位释放，AD9517 OUT0 则经板上缓冲和专用 MGTREFCLK 管脚进入 PCS/PMA。
- `udp_top` 同时例化 `udp_transport_fixed_host`，在 125 MHz 域收口 Ethernet FIFO 帧接口并对外提供
  载荷消息接口。
- `udp_top` 对 AA3 只例化一组 `IBUF+BUFG`，同时驱动 AD9517 控制域和配置为 `No_buffer`
  输入的 200 MHz Clocking Wizard，避免一个封装输入被重复缓冲。
- `udp_echo_test_top` 例化 `udp_top + udp_payload_echo`，在不引入产品业务协议的情况下闭合
  RX/TX 消息接口，用于上位机 UDP 回显验收。

### 当前验证状态与尚未完成项

- 上述组合关系已经进入 RTL/XDC，通过 Vivado/XSim 静态展开，并以重新生成的完整许可 TEMAC
  checkpoint 完成 `udp_echo_test_top` 综合、布局、布线和 bitstream；最终
  `WNS=+0.382 ns`、`WHS=+0.061 ns`，阻断级 DRC 为 0。固定主机 UDP 传输层已按解析、
  RX 消息槽、TX 消息暂存、帧发送和统计五种所有权拆分，外部接口保持不变。
- `udp_top.xdc` 当前已启用并作用于 `udp_echo_test_top`；其中包含 DB500 管脚、AD9517 SPI
  时序、reset synchronizer 例外及 125 MHz GTREFCLK 主时钟约束。
- `udp_transport_fixed_host` 已在 125 MHz 数据面实现 ARP、固定端点 IPv4/UDP、完整载荷槽位和
  强制 UDP checksum，并由 `udp_top` 直接消费/驱动 Ethernet FIFO AXI4-Stream。
- `udp_top` 现在暴露载荷消息接口与调试状态；它们仍是未约束的逻辑端口，在业务模块或专用板级
  测试外壳消费这些端口前，不能直接作为最终 bitstream 顶层。

## 共享板级资源

| 资源 | FPGA/板级连接 | 当前归属或约束 |
|---|---|---|
| 100 MHz 管理时钟 | FPGA `AA3`，Bank 34，`LVCMOS15` | 当前由 `udp_echo_test_top/udp_top` 统一缓冲，供 AD9517 控制及 200 MHz Clocking Wizard 使用；回显顶层关闭 AD9517 ILA |
| LED1 | FPGA `A18`，Bank 15，`LVCMOS33`，高电平点亮 | 多个候选顶层可使用，但只由当前 active top 驱动 |
| MDC/MDIO | `B14/A14`，Bank 16，`LVCMOS33` | `led_static` / M88E1111 模块使用；AD9517 顶层不使用 |
| AD9517 SPI/RESET/LD | `G19/F20/J20/K20/K18/J19` | 当前由回显顶层内的 `ad9517_clock_manager` 使用 |
| AD9517 REF_SEL | `J18` | AD9517 profile 忽略硬件选择脚，当前固定输出 0 |
| AD9517 OUT0 | U65 OUT0/OUT0# → SN65LVDS100 → FPGA `D5/D6`；`MGTREFCLK0` 位于 `GTXE2_COMMON_X0Y1` 所在 tile | 当前 active top 已作为 PCS/PMA 的 125 MHz GT 参考时钟，并已建立主时钟约束 |
| SGMII TX/RX | MGT116 lane 3：TX `A3/A4`，RX `B5/B6`；`GTXE2_CHANNEL_X0Y7` | 当前由已启用的 `udp_top.xdc` 约束并用于回显顶层 |

## 当前集成边界

当前工程已把 `udp_echo_test_top` 作为 active top，用透明回显外壳闭合 `udp_top` 的载荷消息接口。
AD9517 独立顶层已完成的 U65 配置、读回、校准、判锁、OUT0 使能及 125 MHz 外部验收结论不变。
UDP 固定端点、强制 checksum、标准 MTU 和 1472-byte 最大载荷均已进入 RTL；协议仿真、完整展开、
综合、路由时序和 bitstream 均通过。2026-09-11 已使用公司 TEMAC 完整许可重新生成 IP output
products，并把本次 `udp_echo_test_top.bit` 易失下载到唯一的 `xc7k325t_0`。主机“以太网 2”以
1 Gbps 建链后，向 `192.168.1.20:32000` 发送的 14、256 和 1472-byte 载荷均从同一端点逐字节
正确回显，标准 MTU 边界已完成真实链路验收。未来高速图像流的 TX 缓存深度与丢包策略仍作为
业务接入条件单独收口。
