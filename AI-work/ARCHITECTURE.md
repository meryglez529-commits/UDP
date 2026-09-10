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
| `sources_1` | `ad9517_clock_manager` | AD9517 独立配置与 125 MHz 输出验证 |
| `sim_1` | `ad9517_clock_manager_tb` | AD9517 初始化与错误场景仿真 |

## 工程模块树

当前工程存在三个同层根节点，其中 AD9517 根节点处于激活状态：

```text
ad9517_clock_manager                        [工程级根节点；当前 active top]

led_static                                 [工程级根节点；当前未激活]
└── m88e1111_runtime_probe                  [已形成的模块间例化关系]

udp_top                                    [规划根节点；尚无 RTL/IP/XDC]
```

## 模块登记

| 工程级模块 | 状态 | 代码根/计划根 | 设计文档 |
|---|---|---|---|
| LED | 已实现，可切换为独立顶层 | `led_static` | [`modules/led/MODULE.md`](modules/led/MODULE.md) |
| M88E1111 MDIO | 已实现，当前由 `led_static` 例化 | `m88e1111_runtime_probe` | [`modules/m88e1111-mdio/MODULE.md`](modules/m88e1111-mdio/MODULE.md) |
| AD9517 时钟管理 | RTL、仿真、构建和数字侧板验通过；125 MHz 外部实测待完成 | `ad9517_clock_manager` | [`modules/ad9517/MODULE.md`](modules/ad9517/MODULE.md) |
| UDP | 方案已选，尚未开始 RTL/IP 集成 | `udp_top`（规划） | [`modules/udp/MODULE.md`](modules/udp/MODULE.md) |

## 模块间关系

### 当前已经形成的关系

- `led_static` 例化 `m88e1111_runtime_probe`，通过 MDC/MDIO 读取 PHY 运行状态。
- `ad9517_clock_manager` 当前独立运行，不例化 LED、MDIO、GT、PCS/PMA、TEMAC 或 UDP 模块。
- 不同候选顶层之间没有 RTL 连接；它们通过切换 Vivado active top 分别验证。

### 后续明确的集成关系

- AD9517 独立验收完成后，未来的系统/UDP 顶层将复用 AD9517 时钟管理模块的
  `clock_ready` 语义，并接收板上 OUT0 经缓冲后到达的 GT 参考时钟。
- 上述关系目前只是跨模块依赖，不属于当前 `ad9517_clock_manager` 的 RTL，也不能作为
  AD9517 本阶段的通过条件。

## 共享板级资源

| 资源 | FPGA/板级连接 | 当前归属或约束 |
|---|---|---|
| 100 MHz 管理时钟 | FPGA `AA3`，Bank 34，`LVCMOS15` | LED、MDIO、AD9517 候选顶层共用；当前供 AD9517 控制和 ILA 使用 |
| LED1 | FPGA `A18`，Bank 15，`LVCMOS33`，高电平点亮 | 多个候选顶层可使用，但只由当前 active top 驱动 |
| MDC/MDIO | `B14/A14`，Bank 16，`LVCMOS33` | `led_static` / M88E1111 模块使用；AD9517 顶层不使用 |
| AD9517 SPI/RESET/LD | `G19/F20/J20/K20/K18/J19` | `ad9517_clock_manager` 使用 |
| AD9517 REF_SEL | `J18` | AD9517 profile 忽略硬件选择脚，当前固定输出 0 |
| AD9517 OUT0 | U65 OUT0/OUT0# → SN65LVDS100 → FPGA `D5/D6` | 当前只在 U65/缓冲器节点外部测量，不在 FPGA 内实例化 GT 接收 |
| SGMII TX/RX | MGT116 lane 3：TX `A3/A4`，RX `B5/B6` | 预留给后续 UDP 根模块，当前未使用 |

## 当前集成边界

当前工程只把 `ad9517_clock_manager` 作为 active top，完成 U65 的配置、读回、校准、判锁和
OUT0 使能。GTX、PCS/PMA、TEMAC、Clocking Wizard 和 UDP 数据面均未加入这一顶层。下一项
工程级里程碑是用外部仪器确认 U65 OUT0 为 125 MHz；通过后再切换到 UDP 模块规划与集成。
