# UDP 模块

状态：`DESIGN_SELECTED_DEFERRED_UNTIL_AD9517_VALIDATION`

## 当前设计决策（2026-09-09）

- 从头采用两个独立的 AMD/Xilinx 官方 IP：`gig_ethernet_pcs_pma`（SGMII PCS/PMA）和
  `tri_mode_ethernet_mac`（Ethernet MAC）。不采用 `AXI Ethernet Subsystem` 作为本项目的
  网络接口方案。
- 当前项目只复用器件/板级连接事实，不复用其他工程的 RTL、XCI、XDC、参数、生成 example
  design 或构建产物。此前查看的旧工程仅作为架构对比背景，不能作为当前项目的设计输入。
- 这两个 IP 尚未创建、尚未登记到 `led.xpr`，也尚未确定新的 UDP 顶层。
- 当前阶段暂停网络 IP 集成：AD9517 的 RTL、仿真、构建和板上数字侧配置/判锁已经通过，
  但仍需用仪器确认 U65 OUT0 确实为 125 MHz。该主验收项通过之前，不创建 GT、PCS/PMA、
  TEMAC、Clocking Wizard 或 example design。

## 目标

在现有 `led.xpr` 的基础上逐步实现 DB500 千兆网版的最小 UDP 控制链路：标准 ARP 应答、
UDP 32000 端口的版本读取，以及心跳寄存器写入/读回。当前没有 UDP RTL、MAC/SGMII IP、
UDP XDC 或 UDP 仿真输入，不能把本模块描述为已完成。

## 计划架构

```text
M88E1111（已确认硬件模式）
  ↕ SGMII / MGT116 lane 3
SGMII PCS/PMA → Ethernet MAC → ethernet_rx_tx
                         → arp_ipv4_udp_min
                         → db500_control_min
```

建议将网络数据面放在 MAC/PCS 输出的以太网时钟域；LED 和调试状态跨域时使用明确同步器。
不把 `AA3` 的 100 MHz 调试时钟当作 GT 参考时钟。

## SGMII 时钟架构（2026-09-09）

以下内容是后续网络阶段的已知架构，不是当前实施范围。当前只验证 AD9517 OUT0=125 MHz，
不在 FPGA 内部接收 `MGTREFCLK0_P/N`。

- 本项目 Kintex-7 GTX 的外部差分参考时钟确定为 **125 MHz**。依据是当前项目的器件、
  `gig_ethernet_pcs_pma v16.2` SGMII/Transceiver 配置和 AMD PG047，不引用旧工程参数。
- 板上 U5 `SG-8101CE` 提供的 50 MHz 是 AD9517-4 的参考输入，不直接接入 GTX；U65
  `AD9517-4` 需要配置为产生 125 MHz，OUT0 的 LVPECL 经 `SN65LVDS100DR` 转为 LVDS，
  再送到 `MGT116_CLK0_P/N` 和 FPGA `D5/D6`。
- SGMII 串行线速率是 1.25 Gb/s，不等于 GT REFCLK。当前 IP 配置使用 GTXE2 channel
  CPLL；GT `TXOUTCLK` 为 62.5 MHz，共享时钟逻辑再提供 62.5 MHz `userclk` 和 125 MHz
  `userclk2`，其中 125 MHz `userclk2` 可供 PCS/PMA 与 TEMAC 的 GMII 数据面使用。
- PCS/PMA 的 GT 启动/复位逻辑还需要自由运行的 `independent_clock_bufg`。官方 7 系列
  example design 使用 200 MHz（`STABLE_CLOCK_PERIOD=5 ns`）；本项目建议由 AA3 的 100 MHz
  经新建 Clocking Wizard/MMCM 产生 200 MHz，而 AD9517 配置状态机仍运行在原始 100 MHz 域。

AD9517 的频率规划、板载环路滤波器、控制管脚、`SGMII_125M_V1` 寄存器表以及 SPI/校准/
锁定模块架构已独立维护在 [`../ad9517/MODULE.md`](../ad9517/MODULE.md)。当前没有 UDP
集成层；后续创建时只消费其 `clock_ready` 状态，不直接拥有或重复实现 AD9517 配置。

建议的上电顺序是：100 MHz 系统时钟稳定并保持网络链路复位；产生并锁定 200 MHz 独立
时钟；配置 AD9517、执行寄存器更新和 VCO 校准并等待 `PLL_LD`；随后释放 GTX/PCS/PMA
复位并等待 CPLL/GT reset-done 和 PCS 链路状态；最后释放 TEMAC 与 UDP 数据面。

## 已知输入

| 项目 | 当前事实/来源 | 状态 |
|---|---|---|
| PHY 模式 | `HWCFG_MODE=0100`：SGMII without clock；铜口自协商 `ANEG=1110` | 已确认，见 `../m88e1111-mdio/MODULE.md` |
| FPGA→PHY TX | MGT116 lane 3 `A3/A4` | 已确认 |
| PHY→FPGA RX | MGT116 lane 3 `B5/B6` | 已确认 |
| GT REFCLK | `D5/D6`（MGT116 `MGTREFCLK0P/N`） | 后续目标频率为 125 MHz；链路为 50 MHz U5 → AD9517-4 OUT0 → SN65LVDS100 → GTX。AD9517 数字侧配置/读回/校准/判锁已在板上通过，当前只等待 OUT0 外部频率实测；GT 暂不实例化 |
| 控制协议 | 大端、帧头 `55 55 AA AA`；UDP 端口 32000；最小命令 WRITE/READ/READ_RESPONSE；寄存器 `0x000A`、`0x000D` | 依据 `DB500千兆网版通讯协议V1.4_20250113.docx`，需在设计前固定字段解释 |
| 网络地址 | FPGA MAC/IP、目标主机 IP/MAC、子网和测试拓扑 | 需要用户提供，当前不假设 |

## 设计边界

首版只覆盖 ARP、非分片 IPv4/UDP 和两个已确认寄存器；扫描、ADC、升级、Flash、TCP、DHCP、
IPv6、IP 分片和未确认的协议字段不属于当前模块。PHY 的主动复位/写寄存器若成为必要条件，
先扩展 M88E1111 模块的设计记录，再集成到网络顶层。

## 实施入口与验证

所有新 RTL、testbench、IP、XDC 和 top 都登记到 `D:\MyFPGAProject\UDP\fpga\led\led.xpr`，
并同步 `fpga/led/scripts/sources.tcl`。设计讨论确定模块边界后，先在本文件补齐接口和时钟，
再按目标独立选择 S、B、H 或 D：S 验证协议帧，B 验证综合/实现/时序/DRC，H 只在需要真实链路
或 ILA 时使用，D 用于只读检查。流程不会因为另一个流程完成而自动触发。

当前最小下一步完全位于 AD9517 模块：其 SPI/profile/校准/判锁逻辑及 active-register
readback 已通过，只需用仪器实测 U65 OUT0=125 MHz 并完成重复启动记录。UDP 模块在该硬件
验收完成前保持暂缓；验收后再
单独启动 Clocking Wizard、`gig_ethernet_pcs_pma`、`tri_mode_ethernet_mac` 和 `udp_top`
的设计，不把它们混入当前测试镜像。
