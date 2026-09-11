# Vivado 2021.1 Ethernet IP 与官方例程调研

状态：`EXAMPLES_GENERATED_INTEGRATION_REVIEW_COMPLETE`

调研日期：2026-09-10

## 1. 调研目标与证据边界

本记录回答三个问题：`gig_ethernet_pcs_pma` 与 `tri_mode_ethernet_mac` 各自负责什么；Vivado
2021.1 为它们提供哪些官方 example design；哪些例程内容适合后续 DB500 SGMII/UDP 工程使用。

最初调研阶段没有创建 IP。随后经用户批准，在隔离的 `fpga/ip_examples/` 下生成了学习用 IP 和
官方 example project；它们没有加入 `led.xpr`，也没有改变其 fileset、active top、run 或板上镜像。
结论来自以下证据：

- Vivado 2021.1 本地 IP Catalog 与安装包：
  - `D:\Xilinx\Vivado\2021.1\data\ip\xilinx\gig_ethernet_pcs_pma_v16_2\component.xml`
  - `D:\Xilinx\Vivado\2021.1\data\ip\xilinx\tri_mode_ethernet_mac_v9_0\component.xml`
- Vivado 内存工程中的只读 IP Catalog 查询，日志位于：
  - `D:\MyFPGAProject\UDP\fpga\led\logs\ip_catalog_research_20260910_1.log`
  - `D:\MyFPGAProject\UDP\fpga\led\logs\ip_catalog_research_20260910_1.jou`
- 使用目标器件和候选参数实际生成的独立官方 example project：
  - `D:\MyFPGAProject\UDP\fpga\ip_examples\generated\pcs_pma_sgmii\pcs_pma_sgmii_gtx_ex\pcs_pma_sgmii_gtx_ex.xpr`
  - `D:\MyFPGAProject\UDP\fpga\ip_examples\generated\temac_sgmii\temac_sgmii_tri_speed_ex\temac_sgmii_tri_speed_ex.xpr`
- 对应的可复现生成脚本和 Vivado 日志位于 `fpga/ip_examples/scripts/`、`fpga/ip_examples/logs/`。
- AMD 官方产品指南：
  - [PG047 — 1G/2.5G Ethernet PCS/PMA or SGMII v16.2](https://docs.amd.com/r/16.2-English/pg047-gig-eth-pcs-pma)
  - [PG047 — Examine the Example Design](https://docs.amd.com/r/16.2-English/pg047-gig-eth-pcs-pma/Examine-the-Example-Design-Provided-with-the-Core)
  - [PG051 — Tri-Mode Ethernet MAC v9.0](https://docs.amd.com/r/en-US/pg051-tri-mode-eth-mac)
  - [PG051 — Example Design](https://docs.amd.com/r/en-US/pg051-tri-mode-eth-mac/Example-Design)
  - [PG051 — Using the Example Design as a Starting Point](https://docs.amd.com/r/en-US/pg051-tri-mode-eth-mac/Using-the-Example-Design-as-a-Starting-Point)

本地 IP Catalog 是本项目所用 Vivado 版本的直接证据。在线产品指南可能带有同一 IP 版本的
后续文档修订；具体端口名、生成目录和条件编译结果，必须以 Vivado 2021.1 按最终配置实际生成的
example design 为准。

## 2. 两个 IP 的职责边界

| IP | 工程中的位置 | 主要职责 | 不负责 |
|---|---|---|---|
| `gig_ethernet_pcs_pma:16.2` | GTX/SGMII 与 GMII 之间 | GTX 收发器、1.25 Gb/s SGMII、8b/10b、PCS 同步、速率适配、SGMII 自协商、链路状态 | Ethernet MAC 帧、ARP、IPv4、UDP |
| `tri_mode_ethernet_mac:9.0` | GMII 与用户 AXI4-Stream 之间 | Ethernet 帧收发、前导码/SFD、padding、FCS、IFG、MAC TX/RX 状态和可选统计/过滤 | SGMII 串行物理层、ARP、IPv4、UDP、用户指令 |

计划数据路径仍应是：

```text
M88E1111 ⇄ SGMII ⇄ gig_ethernet_pcs_pma ⇄ GMII ⇄ tri_mode_ethernet_mac
                                                     ⇅ 8-bit AXI4-Stream
                                             UDP 固定上位机传输层
```

两个官方例程分别围绕各自 IP 构建，不能把两个 example design 顶层直接串接。后续要从 PCS/PMA
例程取得 GT/共享时钟/复位方法，从 TEMAC 例程取得内部 GMII、AXI4-Stream FIFO、配置和帧测试
方法，再由本项目的 `udp_top` 统一拥有板级时钟、复位和状态。

## 3. `gig_ethernet_pcs_pma v16.2`

### 3.1 本地 Catalog 已确认的信息

| 项目 | Vivado 2021.1 结果 |
|---|---|
| VLNV | `xilinx.com:ip:gig_ethernet_pcs_pma:16.2` |
| Kintex-7 支持 | Production |
| 许可 | `REQUIRES_LICENSE=0` |
| 可生成目标 | example、simulation、synthesis、implementation、instantiation template |
| 标准 | `1000BASEX`、`SGMII`、`BOTH` |
| 物理接口 | Device Specific Transceiver、TBI、LVDS Serial |
| SGMII 速率模式 | 10/100/1000；或受限容差的 100/1000 模式 |
| GT 参考时钟选项 | 包含 125 MHz；与本板已验收的 AD9517 OUT0 一致 |
| MAC 侧选择 | TEMAC 或 Zynq GEM；本工程应选择 TEMAC |
| Shared Logic | 可放入 core，也可放入 example design |

与当前硬件相符的候选定制是：SGMII、1G maximum data rate、Device Specific Transceiver、
125 MHz REFCLK、单 lane、MAC-side SGMII、Select Ethernet=定制 TEMAC。若保留 M88E1111 铜口
10/100/1000 自协商，PCS/PMA 与 TEMAC 都必须采用 tri-speed 兼容配置；若项目明确只允许千兆链路，
两者才可一起收紧为 1000 Mb/s。

### 3.2 官方提供的 example design 类型

PG047 按定制方式提供五类 HDL 例程：

| 官方例程 | 适用配置 | 本项目相关性 |
|---|---|---|
| 1000BASE-X/2500BASE-X with Transceiver | 光口/BASE-X，器件 GT | 不适用当前 M88E1111 SGMII |
| SGMII/Dynamic Switching Using a Transceiver | SGMII 或动态切换，器件 GT | **本项目应生成和研究的例程** |
| Synchronous SGMII over LVDS | 非 Versal、LVDS 串行实现 | 不适用；本板使用 GTX lane 3 |
| 1000BASE-X with TBI | 外部十位接口 | 不适用 |
| SGMII/Dynamic Switching with TBI | 外部十位接口 | 不适用 |

### 3.3 相关例程包含什么

Vivado 2021.1 安装包为 Kintex-7/7 系列 transceiver 路径提供以下模板族，最终文件名会带用户
选择的 component name：

- `example_design_v7`：例程顶层，连接 core block、GT 支持逻辑、GMII 演示路径和状态。
- `tx_elastic_buffer`：当例程时钟方案需要时处理 GMII TX 时钟关系。
- `transceiver_sgmii_v7`、`gtwizard_sgmii_v7`：7 系列 GTX SGMII 收发器封装。
- `gtwizard_init_gtx`、TX/RX startup FSM、CPLL/reset 序列：GT 初始化与恢复逻辑。
- `pcs_pma_csl_in_example_design`、`reset_sync_ex`、`sync_block_ex`：共享时钟/复位和 CDC 示例。
- `demo_tb_v7`、`stimulus_tb`：官方演示 testbench 与激励。
- example XDC：参考时钟、GT、派生时钟和例程顶层约束的起点。

这些模板在安装包内是受保护的 TTCL 内容，未按某个具体 IP 配置展开；只有在创建 XCI 并执行
“Open IP Example Design”后，才会得到可读、可综合/仿真的具体 HDL 工程。因此现在能确认例程
类别和组成，但不能把尚未生成的端口表当作最终接口。

### 3.4 对本项目最有价值的部分

1. 125 MHz `MGTREFCLK0_P/N` 如何进入 GTXE2，以及 GT channel/CPLL 的实际配置。
2. `TXOUTCLK`、`userclk`、`userclk2` 的 BUFG/MMCM 关系。
3. 200 MHz `independent_clock`、PMA reset、GT startup FSM 和 reset-done 的先后关系。
4. SGMII auto-negotiation、`status_vector`、`an_interrupt` 与 link-up 判据。
5. tri-speed 时 `sgmii_clk_en` 如何送给 TEMAC；本地 Catalog 明确说明它是 10/100 Mb/s 的
   clock-enable。
6. GT/XDC 约束的生成形式，以及共享逻辑放在 core 或 example design 时端口如何变化。

PCS/PMA demo testbench 可以证明官方 core 与其链路伙伴模型在所选定制下工作，但它不等价于
M88E1111 实物、板上走线和 AD9517 时钟验收。板级 link-up 仍需独立 H 流程验证。

### 3.5 实际生成结果

2026-09-10 已按 SGMII、Device Specific Transceiver、125 MHz REFCLK、单 lane、TEMAC MAC
侧、10/100/1000 SGMII、自动协商和“shared logic in example design”生成例程。生成顶层
`pcs_pma_sgmii_gtx_example_design` 明确暴露 `gtrefclk_p/n`、`txp/txn`、`rxp/rxn`、GMII、
`independent_clock`、`an_interrupt` 和 `status_vector`；support wrapper 中包含 PCS/PMA、
clocking、reset 和 GT common 支持逻辑，生成文件中可见 `GTXE2_COMMON`。

学习工程 XCI 中的 `GT_Location=X0Y0` 只是生成时的输入占位值，不能用于 DB500。随后使用
`xc7k325tffg676-2` 器件数据库做了只读管脚映射，结果为：

| DB500 管脚 | 器件管脚功能 | Vivado 物理资源 |
|---|---|---|
| `A3/A4` | `MGTXTXN3/P3_116` | `GTXE2_CHANNEL_X0Y7` |
| `B5/B6` | `MGTXRXN3/P3_116` | `GTXE2_CHANNEL_X0Y7` |
| `D5/D6` | `MGTREFCLK0N/P_116` | `GTX_COMMON_X219Y231`，其中含 `GTXE2_COMMON_X0Y1` |

这里要区分 IP 参数与器件绝对 site：Vivado 2021.1 对该单 lane 定制的 `GT_Location` GUI 参数只
接受相对值 `X0Y0`；生成后的 XDC 才将它展开为绝对 LOC `GTXE2_CHANNEL_X0Y7`。因此生产 XCI
保持 `GT_Location=X0Y0`，同时用生产 XDC/生成约束确认实际 channel 为 X0Y7。最终 XDC 仍须显式
约束 DB500 的串行管脚与 `D5/D6` 125 MHz 差分参考时钟，不能直接照搬例程中被注释的演示板管脚。

## 4. `tri_mode_ethernet_mac v9.0`

### 4.1 本地 Catalog 已确认的信息

| 项目 | Vivado 2021.1 结果 |
|---|---|
| VLNV | `xilinx.com:ip:tri_mode_ethernet_mac:9.0` |
| Kintex-7 支持 | Production |
| 许可 | `REQUIRES_LICENSE=1`；许可键包含 `tri_mode_eth_mac@2015.04` |
| 可生成目标 | example、simulation、synthesis、implementation、instantiation template |
| PHY interface | GMII、RGMII、MII、Internal |
| MAC speed | Tri-speed、1000 Mb/s、10/100 Mb/s、2.5 Gb/s；Internal 模式允许 tri-speed 或 1000 Mb/s |
| Internal mode | BASE-X 或 SGMII；本工程应选 SGMII |
| 管理方式 | AXI4-Lite 或 Configuration Vector |
| 可选功能 | frame filter、statistics、AVB、1588、priority flow control 等 |

公司已与 AMD 确认本项目所需 IP 均可使用，因此许可证不再作为设计、实施或验收阻塞项，也不再
安排额外的许可探测。Vivado 在当前学习工程中显示的许可状态只描述这台机器生成例程时的工具环境，
不能反向改变公司的授权结论。

### 4.2 用户侧 AXI4-Stream 的关键不对称

本地 `component.xml` 明确显示：

- TX：`tx_axis_mac_tdata/tvalid/tlast/tuser/tready`，可以由 TEMAC 反压发送源。
- RX：`rx_axis_mac_tdata/tvalid/tlast/tuser`，**没有 `rx_axis_mac_tready`**。

因此 TEMAC 接收流不能被 UDP 解析器反压。接收路径必须每周期接住 MAC 输出，或通过官方 RX FIFO
吸收；缓冲不足时只能完整丢弃并计数。`rx_axis_mac_tuser` 可能到帧尾才宣告坏帧，这也支持当前
UDP 设计的“候选槽位写入，整帧结束与所有校验通过后再提交”策略。

### 4.3 官方 example design 的组成

TEMAC 不是按五种名称提供五套例程，而是依据当前 IP 定制生成一套 HDL example design。PG051
和 Vivado 2021.1 本地文件集表明它可以包含：

- `trimac_example_design`：例程顶层。
- `trimac_fifo_block`、`ten_100_1g_eth_fifo`、`rx_client_fifo`、`tx_client_fifo`、`bram_tdp`：
  10/100/1000 Ethernet 帧 FIFO。
- `axi_pat_gen`、`axi_pat_check`、`axi_mux`、`axi_pipe`、`basic_pat_gen`：AXI4-Stream 帧发生、
  检查与演示数据路径。
- `address_swap`：接收帧地址交换后回送的演示逻辑。
- `axi_lite_sm` 或 `config_vector_sm`：根据所选管理接口初始化 MAC。
- `demo_tb`、`loopback_module`、`frame_typ`：官方 testbench、PHY 侧/用户侧回环与帧定义。
- `trimac_example_design_xdc`、clock/reset reusable blocks：例程约束、时钟和复位示例。

官方文档还说明，例程可作为帧发生器/检查器或 MAC RX→TX 回环演示；其中所谓 PHY TX→RX
回环，是在 TEMAC 的物理接口一侧替代 testbench stimulus/checker 的外部回环语境，不表示例程
包含 PHY、GT 或 `gig_ethernet_pcs_pma`。官方例程可针对 KC705 和 AC701 等演示板实现，其板级
按键、拨码、外部 PHY 地址、MDIO 初始化和管脚约束均不能直接用于 DB500。

### 4.4 对本项目最有价值的部分

1. `Physical_Interface=Internal`、`Int_Mode_Type=SGMII` 时与 PCS/PMA 的 GMII 连接。
2. tri-speed 模式下 `user_clk2`、GMII 和 TX/RX clock-enable 的实际端口关系。
3. `rx_client_fifo` 如何处理无 `tready` 的 MAC RX、坏帧和帧边界。
4. TX `tready`、`tlast`、`tuser` 的合法握手与中止语义。
5. 无处理器时用 Configuration Vector 固定初始化 TEMAC 的方法。
6. pattern generator/checker 与 demo testbench，可用于在 UDP 逻辑之前单独闭环 MAC 帧收发。

例程中的 Ethernet FIFO 与 UDP 完整消息槽位不是同一层：前者解决 MAC RX 不可反压、帧状态和
可能的时钟适配；后者解决 UDP checksum 在帧尾才能确认以及业务侧消息原子交付。实现时可根据
最终时钟域关系简化层次，但不能在没有容量/时序证明的情况下同时删除两者。

### 4.5 实际生成结果

2026-09-10 已按 Internal、SGMII、tri-speed、`user_clk2`、Configuration Vector、无 MDIO、无
frame filter、无 statistics counter 生成例程。生成顶层 `temac_sgmii_tri_speed_example_design`
只暴露内部 GMII 和 `clk_enable`，层次中只有 TEMAC、Configuration Vector 状态机、RX/TX FIFO、
pattern generator/checker、时钟和复位支持逻辑；全文检索和工程 sources 均没有 PCS/PMA 或
GT 实例。这直接确认 TEMAC 与 PCS/PMA 必须作为两个独立 IP 集成。

Vivado 在生成 TEMAC synthesis/simulation target 时曾报告 `tri_mode_eth_mac@2015.04` 为
`Design_Linking`。该信息仅保留为本次例程生成环境的事实记录；根据公司的 AMD IP 使用结论，
后续不再把它列为生产设计风险或待确认项。

## 5. 两套例程组合后的确定结构

### 5.1 不是拼接两个 example top

生产设计新建项目自己的 `ethernet_link_top`。它使用两个 IP 及例程中必要的 support/FIFO 思路，
不例化两个 `*_example_design` 顶层：

| 来源 | 生产设计保留 | 仅用于学习/仿真，不进入生产层次 |
|---|---|---|
| PCS/PMA 例程 | PCS/PMA core、GT channel/common、参考时钟、`userclk/userclk2`、GT reset/support 逻辑 | 演示 GMII IOB 寄存器、外部 GMII 用 ODDR、`stimulus_tb`、演示顶层 |
| TEMAC 例程 | TEMAC support/core、Configuration Vector 初始化方法、RX/TX Ethernet FIFO | pattern generator/checker、地址交换、串行状态显示、演示板 clock/reset 顶层 |
| 本项目新增 | `ethernet_link_top`、链路/速率控制器、统一复位、DB500 XDC、面向 UDP 的 AXI4-Stream 边界 | — |

这样“合二为一”的对象是两个 IP 的必要数据面与 support 逻辑，而不是把两个带演示 I/O、演示
复位和 testbench 控制的顶层套在一起。

### 5.2 已确认的逐信号连接

| 源 | 目的 | 连接 |
|---|---|---|
| PCS/PMA | TEMAC | `userclk2_out -> gtx_clk` |
| PCS/PMA | TEMAC | `sgmii_clk_en -> clk_enable` |
| TEMAC | PCS/PMA | `gmii_txd/gmii_tx_en/gmii_tx_er` |
| PCS/PMA | TEMAC | `gmii_rxd/gmii_rx_dv/gmii_rx_er` |
| TEMAC | PCS/PMA | `speedis10100 -> speed_is_10_100` |
| TEMAC | PCS/PMA | `speedis100 -> speed_is_100` |

两个 IP 内连时不使用 PCS/PMA 例程顶层针对外部 GMII 演示所加的 IOB pipeline 与
`sgmii_clk_f/r` ODDR 时钟。PCS/PMA 的 `gmii_isolate` 可保留为状态/调试信号，但不作为片内
GMII 三态控制。

### 5.3 tri-speed 自动协商闭环

PG047 已确认 SGMII MAC mode 下，M88E1111 作为链路伙伴把铜口结果放在 SGMII 配置字中，
PCS/PMA 将其映射为：

| `status_vector` | 含义 |
|---|---|
| `[0]` | PCS 链路有效：GT reset 完成、8b/10b 同步且 SGMII auto-negotiation 完成 |
| `[7]` | M88E1111 铜口 link，只有 SGMII auto-negotiation 成功后才有效 |
| `[11:10]` | `00=10 Mb/s`、`01=100 Mb/s`、`10=1000 Mb/s`、`11=保留` |
| `[12]` | `1=full duplex`、`0=half duplex` |

TEMAC 不会自动读取这个状态。项目必须增加一个位于 `userclk2` 域的链路/速率控制器：

1. 复位后的默认 `mac_speed` 设为 `2'b10`（1000 Mb/s），保持 UDP/FIFO 不工作，让 PCS/PMA
   完成串行同步和 SGMII 协商。
2. 当 `status_vector[0]` 成立时锁存 `[11:10]`；仅接受 `00/01/10`。首版 TEMAC 配置为 full
   duplex，因此还必须要求 `[12]=1`。
3. 将协商速率送入 TEMAC Configuration Vector 的 RX/TX speed 字段，并产生一次
   `update_speed`。官方 `config_vector_sm` 会在更新时同时复位 MAC TX/RX、修改速度，再释放复位。
4. TEMAC 的 `speedis10100/speedis100` 反馈给 PCS/PMA 的两个 speed 输入；PCS/PMA 据此生成
   10/100/1000 对应的 `sgmii_clk_en`，再送回 TEMAC `clk_enable`。
5. 等 MAC/FIFO 复位释放，且 `[0] && [7]` 仍成立后，才置 `link_ready` 并允许 UDP 收发。
6. 铜口 link 丢失、PCS 链路失效、协商速率改变或出现保留/半双工结果时，立即撤销
   `link_ready`；停止并清理在途帧，重新走上述闭环。

这里虽然存在“PCS 状态 → TEMAC speed → PCS speed input”的反馈关系，但没有启动死锁：SGMII
串行线始终工作在 1.25 Gb/s，PCS/PMA 可以先完成配置字接收；两个 speed 输入控制的是协商后
GMII 数据的 10/100/1000 速率适配。

### 5.4 用户侧保持固定 125 MHz

PCS/PMA 的 `userclk2_out` 是 125 MHz，送给 TEMAC `gtx_clk`。TEMAC 内部 MAC client 时钟及
低速字节节拍由 IP 和 `clk_enable` 管理；官方 `ten_100_1g_eth_fifo` 在 MAC client clock 与
`tx_fifo_clock/rx_fifo_clock` 之间做双时钟缓冲。生产设计把两个 FIFO 用户侧时钟接到同一个
125 MHz `userclk2`，因此 UDP 逻辑保持固定 125 MHz AXI4-Stream 接口，不随铜口速率切换时钟。

这层 Ethernet FIFO 仍有两个不可替代的职责：接收 TEMAC 无 `tready` 的输出并丢弃坏帧；在
tri-speed 模式下跨接 MAC client clock 与固定 125 MHz 用户时钟。UDP 的完整消息槽位位于其后，
负责 UDP checksum 后提交和业务侧原子交付，两者不能合并为一个缓冲器。

### 5.5 管理接口边界

PCS/PMA 自身管理寄存器、TEMAC Configuration Vector、板上 M88E1111 Clause 22 MDIO 是三套
独立接口。当前适合无处理器首版的组合是：

- TEMAC 使用 Configuration Vector；不引入 AXI4-Lite 配置软件。
- PCS/PMA 关闭可选 MDIO，用 `configuration_vector[4]=1` 开启 auto-negotiation，其余控制位为
  正常模式；SGMII MAC mode 下 `an_adv_config_vector` 本来就被 core 内部固定为 `16'h0001`。
- 此时 `an_interrupt` 是持续的 AN Complete 电平，不需要 MDIO 清除；链路控制仍以
  `status_vector` 为准。
- M88E1111 外部 `B14/A14` MDC/MDIO 继续由现有 PHY 模块独立拥有，只用于 PHY 配置与观测，
  不能与 PCS/PMA 内部 MDIO 接口并线。

### 5.6 共享时钟和复位只有一个所有者

`ethernet_link_top` 接收 AD9517 `clock_ready`，并统一拥有从板上 100 MHz 经 Clocking Wizard
产生的已缓冲 200 MHz independent clock、PCS/PMA GT reset/support、TEMAC/FIFO reset 与
`link_ready`。生产设计不能同时保留两套 example design 的
MMCM/BUFG/reset controller。PCS/PMA shared logic 最终放在 core 还是生产 support wrapper 中，
只影响层次与端口，不改变上述时钟、复位和数据连接。

## 6. example design 学习与生产实现进度

两套学习例程已经在隔离工程中生成，并完成接口、时钟、FIFO、配置、自动协商状态和 DB500 GT
位置的静态对照。2026-09-10 已据此在共享 `led.xpr` 中建立第一版生产链路层：

- `led.srcs/sources_1/ip/pcs_pma_sgmii_gtx/pcs_pma_sgmii_gtx.xci`：SGMII MAC mode、
  10/100/1000 auto-negotiation、125 MHz GT REFCLK、shared logic in core、内部 MDIO 关闭。
- `led.srcs/sources_1/ip/temac_sgmii_tri_speed/temac_sgmii_tri_speed.xci`：Internal SGMII、
  tri-speed、Configuration Vector、MDIO/filter/statistics 关闭。
- `led.srcs/sources_1/ip/ethernet_clk_wiz_200m/ethernet_clk_wiz_200m.xci`：100 MHz单端输入，
  MMCM产生200 MHz，输出自带BUFG并导出 `locked`。
- `led.srcs/sources_1/new/ethernet/ethernet_link_top.v`：真实 GMII、clock-enable、speed 反馈、
  固定 125 MHz AXI4-Stream 和链路复位边界；接收板上100 MHz并在内部拥有上述 Clocking Wizard。
- `ethernet_link_speed_ctrl.v`：锁存 `status_vector[11:10]`，只接受 full-duplex 合法速率，触发
  TEMAC speed update，并在实际观察到 TX/RX reset 拉高再释放后产生 `link_ready`。
- TEMAC 例程中的 support、Configuration Vector 状态机和 RX/TX Ethernet FIFO 以原始模块名
  复制到工程自己的 `new/ethernet` 目录；pattern generator/checker 和 demo top 未进入生产层次。

控制器行为仿真已通过；Clocking Wizard 自检在100 MHz输入下测得200 MHz输出周期为5.000 ns，
并确认 `locked` 正常置位；完整 `ethernet_link_top` 也已通过 Vivado 2021.1/XSim 的源码编译和静态
展开。XSim 安装环境会额外报告缺少可选 `wbtcv.exe`，但 snapshot构建和仿真均正常完成。尚未
执行生产顶层综合/实现、时序收敛或真实 M88E1111 板级自动协商验收。

官方 example design 应作为可追溯的参考基线保留在 Vivado 生成位置，不应把整个演示顶层、演示
板 XDC、按键/拨码逻辑或 PHY 初始化状态机直接登记为 DB500 的生产设计输入。

## 7. 下一阶段入口

IP 选项已经收敛，不再列为待批准项。下一阶段按以下顺序进行：

1. 将已验收 AD9517 控制逻辑变成可复用实例并导出 `clock_ready_o`。
2. 建立包含 AD9517、M88E1111 MDIO 和 `ethernet_link_top` 的板级组合顶层及 DB500 XDC；active
   top 切换须作为单独评审动作，不能覆盖当前 AD9517 验收入口。
3. 对组合顶层执行综合、实现、时序和 GT/clock DRC，再在 M88E1111 铜口分别验证 10/100/1000
   自动协商、掉线恢复和 AXI 帧收发。
4. 地址参数确定后实现 `udp_transport_fixed_host`，将 Ethernet FIFO 的固定 125 MHz 帧接口接入
   ARP/IPv4/UDP 层。
