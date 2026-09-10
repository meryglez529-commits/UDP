# M88E1111 启动绑带与最终配置可追溯记录

**状态：已由原理图与官方数据手册闭合；正确 B14/A14 端点的运行时只读验证已通过。**
**诊断日期：2026-09-08（Asia/Shanghai）。**
**范围：** 只确定 `RESETn` 释放后 M88E1111 的硬件默认配置。不修改 Vivado 工程、RTL、XDC、IP，也未进行 MDIO/JTAG/网络或板级操作。

## 1. 结论

M88E1111 在本板的复位后默认接口模式为：

```text
HWCFG_MODE[3:0] = 0100
=> SGMII without clock with SGMII Auto-Negotiation to copper
```

铜口的默认自协商配置为：

```text
ANEG[3:0] = 1110
=> Auto-Negotiation；通告全部能力；preferred master
```

该结论与硬件连线一致：`S_IN+/-`、`S_OUT+/-` 接 FPGA MGT，`S_CLK+/-` 未接。这里的 “without clock” 指 SGMII 没有单独的 `S_CLK` 信号对；SGMII 数据流使用嵌入式时钟。FPGA GTX 仍需要自己的 MGT 差分参考时钟，此时钟不是 M88E1111 工作方式的绑带条件。

## 2. 证据登记

| ID | 证据 | 定位 / 完整性 | 用途 |
|---|---|---|---|
| E-01 | MCON 原理图 | `D:\MyFPGAProject\UDP\sem-sgsc2450-mcon_v1_3_2021-9-2(1).pdf`，第 9 页，SHA-256 `6907B4EB59EF93496C5089E01728EEACEC5F187277A8971088201137FDDE5772` | U79（M88E1111）配置脚、LED 常量网、SGMII 与 RGMII 连线 |
| E-02 | 用户提供的原理图裁图 | `C:\Users\Administrator\AppData\Local\Temp\codex-clipboard-aceff68e-f02c-4479-95c0-168435fe9e24.png`，SHA-256 `2194210BCB6CC394DE76C0191E6B1FD6044C6461DDF17F9702747D2B215CF2F1`；临时目录文件，不作为唯一长期来源 | 明确校正 `CONFIG[4] → R373 → LED_LINK1000` 的连线阅读 |
| E-03 | 官方数据手册（浏览器现场审阅） | Marvell，*Alaska 88E1111 Datasheet*，Doc. No. `MV-S100649-00`, Rev. M, 2020-08-31；URL：`https://www.marvell.com/content/dam/marvell/en/public-collateral/transceivers/marvell-phys-transceivers-alaska-88e1111-datasheet.pdf`；在 Codex In-app Browser 中打开，标题 `88E1111 Datasheet`，共 262 页 | 绑带常量编码、配置位映射、模式与自协商定义 |
| E-04 | 用户提供的 MCON J6 / CORE HT2 互连裁图 | `C:\Users\Administrator\AppData\Local\Temp\codex-clipboard-b7547566-c24d-416b-8a45-71e46445d44c.png`，SHA-256 `4B5EDE44AF9CECB4E703ED6151BF1088E5CA27147834997D154D4B513CB67325`；`C:\Users\Administrator\AppData\Local\Temp\codex-clipboard-f582b125-3459-4b68-b0dd-ad660817bea5.png`，SHA-256 `D7E8ACDF63FE94B85E858211B9E2F5983A12F17EAFAF373685C6BD04C30DF9BE`；临时目录文件，不作为唯一长期来源 | 以网络名闭合 MCON `B16_L21_P/N` 至 CORE HT2.A53/A54、FPGA B14/A14（Bank 16 / 3.3 V）；早期按相同行号得出的 E13/E12 已撤销 |

E-03 的浏览器审阅页和引用内容如下：

| 手册页 | 章节 / 表 | 读取到的关键事实 |
|---|---|---|
| 68 | 2.4 Hardware Configuration，Table 32 *Pin to Constant Mapping* | `VDDO=111`、`LED_LINK10=110`、`LED_LINK100=101`、`LED_LINK1000=100`、`LED_DUPLEX=011`、`LED_RX=010`、`LED_TX=001`、`VSS=000`；配置值在 `RESETn` 去使能时锁存。 |
| 70 | 2.4.1，Table 34 *Device Pin to Configuration Bit Mapping* | `CONFIG[4]→HWCFG_MODE[2:0]`；`CONFIG[5][0]→HWCFG_MODE[3]`；`CONFIG[2]→ANEG[3:1]`；`CONFIG[3][2]→ANEG[0]`；并给出 PHY 地址和管理接口选择位映射。 |
| 71 | Table 35 *Device Configuration Register Definitions* | `ANEG=1110` 为铜口自协商、通告全部能力、preferred master。 |
| 72 | Table 35（续） | `HWCFG_MODE=0100` 为 “SGMII without clock with SGMII Auto-Negotiation to copper”。 |
| 64 | 2.3.1.5 *SGMII to Copper Modes* | `0000` 为 SGMII with clock，`0100` 为 SGMII without clock；说明 SGMII 接口与铜口之间的工作关系。 |

## 3. 原理图绑带到数据手册位的逐项译码

下表只按 E-01 第 9 页的实际网络名读取，不根据 LED 名称的位置猜测。

| 配置脚 | 原理图实际连接 | Table 32 编码 | Table 34 配置字段 | 解码结果 |
|---|---|---:|---|---|
| `CONFIG[0]` (D8) | `VCC2V5` (`VDDO`) | `111` | `PHYADR[2:0]` | `111` |
| `CONFIG[1]` (E9) | `GND` (`VSS`) | `000` | `ENA_PAUSE`、`PHYADR[4:3]` | `ENA_PAUSE=0`，`PHYADR[4:3]=00` |
| `CONFIG[2]` (F8) | `VCC2V5` (`VDDO`) | `111` | `ANEG[3:1]` | `ANEG[3:1]=111` |
| `CONFIG[3]` (G7) | `GND` (`VSS`) | `000` | `ANEG[0]`、`ENA_XC`、`DIS_125` | `ANEG[0]=0`，`ENA_XC=0`，`DIS_125=0` |
| `CONFIG[4]` (F9) | 经 `R373`（0 ohm）接 `LED_LINK1000` | `100` | `HWCFG_MODE[2:0]` | `100` |
| `CONFIG[5]` (G9) | `LED_LINK10` | `110` | `DIS_FC`、`DIS_SLEEP`、`HWCFG_MODE[3]` | `DIS_FC=1`，`DIS_SLEEP=1`，`HWCFG_MODE[3]=0` |
| `CONFIG[6]` (G8) | `LED_RX` | `010` | `SEL_TWSI`、`INT_POL`、`75/50 OHM` | `SEL_TWSI=0`（选择 MDC/MDIO），`INT_POL=1`（`INTn` 低有效），`75/50 OHM=0` |

由此可复算：

```text
PHY address = PHYADR[4:0] = 00_111b = 0x07
ANEG[3:0] = CONFIG[2][2:0] + CONFIG[3][2] = 111_0b = 1110
HWCFG_MODE[3:0] = CONFIG[5][0] + CONFIG[4][2:0] = 0_100b = 0100
```

## 4. 管理接口的端到端物理路径

早期记录把相对插接的 J6/HT2 以同一 A/B 行号直接对应，错误地得出 E13/E12。2026-09-08 重新逐网络视觉核对后，以下为当前有效的闭合路径；完整更正见 `AI-work/history/legacy-2026-09-08/diagnostics/m88e1111-mdio-pin-mapping-2026-09-08/PIN_MAPPING_CORRECTION.md`。

| 功能 | PHY / MCON 侧 | MCON J6 与 CORE HT2 | FPGA 侧 | 电气结论 |
|---|---|---|---|---|
| MDC | `PHY_MDC_L` → U82（TXS0104）→ `B16_L21_P` | J6.B54 / `B16_L21_P` → CORE HT2.A53 / `B16_L21_P` | **B14**，Bank 16 | Bank 16 为 3.3 V；实施时使用 `LVCMOS33`。 |
| MDIO | `PHY_MDIO_L` → U82（TXS0104）→ `B16_L21_N` | J6.B55 / `B16_L21_N` → CORE HT2.A54 / `B16_L21_N` | **A14**，Bank 16 | Bank 16 为 3.3 V；MDIO 在 FPGA 端必须用三态/开漏实现。 |
| INT（首轮不驱动） | `PHY_INT_L` → U82 → `B16_L24_P` | J6.B56 / `B16_L24_P` → CORE HT2.A55 / `B16_L24_P` | A13，Bank 16 | 可用于后续中断观察；本工作包不驱动。 |

MCON 第 9 页的 4.7 kohm 上拉与 U82 的 2.5 V / 3.3 V 电平转换构成 MDIO 的板端电气环境。本工作包仅用 FPGA `IOBUF` 将 MDIO 输出为低或高阻，不会主动输出高电平。

## 5. 最终配置如何生效

1. 板卡把 `PHY_RESET_L` 释放（M88E1111 的 `RESETn` 去使能）。
2. PHY 在该时刻锁存上述 `CONFIG[6:0]` 的编码值。
3. 因而 PHY 自身进入 `HWCFG_MODE=0100`：FPGA 与 PHY 走无独立时钟的 SGMII，PHY 铜口和 SGMII 侧均使用该模式定义的自协商。
4. `CONFIG[6]=010` 还明确选择 MDC/MDIO 管理接口；后续 FPGA 可以通过该接口读状态或覆盖可写配置。硬件绑带和 FPGA 的 MDIO 配置不是互斥模式：前者提供复位后的默认值，后者用于运行时管理或改写。

当前 LED 工程没有 MDC/MDIO/SGMII 初始化逻辑，因此本记录仅证明芯片的硬件默认配置，**不证明**已执行 MDIO 读回、链路已建立或 FPGA 已完成 UDP 通信。

## 6. 更正历史

2026-09-08 曾将 `CONFIG[4]` 错读为 `LED_LINK10`，导致写出 `HWCFG_MODE=0110`。E-02 中用户提供的局部图与 E-01 第 9 页的稳定原理图一致地证明：`CONFIG[4]` 经 R373 接 `LED_LINK1000`，而 `CONFIG[5]` 接 `LED_LINK10`。此前关于 `0110` / “RGMII to SGMII” 的结论作废；本文件和同目录的 `ACCEPTANCE.md` 为当前有效结论。

## 7. 运行时最小核验

实现 MDIO 后，使用 PHY 地址 `0x07` 读取：

1. 标准寄存器 0（BMCR）：确认 Auto-Negotiation enable；
2. 标准寄存器 1（BMSR）：确认 link status 与 Auto-Negotiation complete；
3. 对应 Marvell 扩展状态 / 模式寄存器：确认运行时 `HWCFG_MODE` 未被后续软件覆盖。

2026-09-08 首次采集错误使用 E13/E12（`B16_L18_P/N`）；该次 E12 高阻释放低、PHYID1/2/reg27=`0x0000` 的记录均只说明错误端点状态，已作废为 M88E1111 证据。随后以网络名重建端点并将同一 `led.xpr` 约束更正为 B14/A14（`B16_L21_P/N`），重新构建、JTAG 易失下载和 ILA 采集。

正确端点读回为：PHYID1=`0x0141`、PHYID2=`0x0CC2`、reg27=`0x8484`（`[3:0]=0100`）、BMCR=`0x1140`（AN enable=1）、ANAR=`0x01E1`、1000BASE-T Control=`0x0300`、BMSR 双读均=`0x796D`（Link=1、AN Complete=1）。A14 开漏自检在释放后 100/250/400 ns 均为高，preamble 为高，turnaround 观测为 `TA=Z0`。因此运行态确认了地址 `0x07`、`HWCFG_MODE=0100`、自协商启用及采集时刻铜口协商完成。

错误端点的原始 `.ila`、CSV、逐 sample 位域解码、镜像哈希与无写入边界仍保留在：

`AI-work/history/legacy-2026-09-08/work-packages/m88e1111-runtime-validation-2026-09-08/out/hardware/MDIO_ILA_DECODE.md`

它们仅是错误端点的历史采集，并非 M88E1111 运行状态的验证，也不是本次原理图绑带结论的前提。当前有效的 B14/A14 ILA 证据、原始文件哈希和无写入边界记录在：

`AI-work/history/legacy-2026-09-08/work-packages/m88e1111-runtime-validation-2026-09-08/out/hardware/B14_A14_RUNTIME_ILA_DECODE.md`
