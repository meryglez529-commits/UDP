# 硬件环境总表

状态：`PARTIAL`

本文件是后续工作包的唯一全局硬件事实来源。2026-09-07 的首版采用 PDF 扁平文本抽取，无法可靠表示连接器两侧和跨板端到端关系，因此不再作为 XDC、IP 参数或板级操作的依据。本版按“Bank 电源 → 单信号映射 → 功能路径”的顺序重建；只有表中明确标为“可用于开发”的行才可被工作包引用。未闭合的接口保持待确认，但不阻塞已具备完整事实的工作包。

状态含义：

- `已确认（可用于开发）`：所需连接、电源和电气事实均能回溯到明确资料页。
- `核心板内已确认，跨板待确认`：FPGA 到核心板连接器已闭合，但尚未闭合到子板/器件。
- `待确认`：不得用于 XDC、IP 参数或板级动作。
- `用户确认`：用户提供的事实；仍须在表中写出适用范围。

## 1. 项目身份与资料

| 项目 | 值 | 来源与状态 |
|---|---|---|
| 项目路径 | `D:\MyFPGAProject\UDP` | 已确认 |
| Git 远程 | `git@github.com:meryglez529-commits/UDP.git` | 已确认 |
| FPGA 核心板 | MK7XCORE676，图纸日期 2019-06-14 | SRC-001，已确认 |
| FPGA | Xilinx Kintex-7 `XC7K325T-2FFG676I` | SRC-001 第 2、6 页，已确认 |
| 工具链 | Vivado 2021.1 | 用户指定，已确认 |
| 当前 JTAG 观测 | 已上电且 JTAG 已连接；只读枚举见一个 Digilent 目标和唯一 `xc7k325t_0` | 用户陈述 + `led-download-check` 日志，已确认；这不证明下载或 LED 行为 |

| 编号 | 文件 | 版本/日期 | 已视觉核对的页 | 哈希 SHA-256 | 用途与状态 |
|---|---|---|---|---|---|
| SRC-001 | `D:\MyFPGAProject\UDP\MK7XCORE676 20190614.pdf` | 2019-06-14 | 第 2、4、5、6、10 页 | `FC5AC7FEF237C4F0BB9DB24D1A23168A4D3D06B16DF8DF481C729EC4276C13FB` | 核心板 FPGA、Bank、配置、GT、HT 连接器；进行中 |
| SRC-002 | `D:\MyFPGAProject\UDP\sem-sgsc2450-mcon_v1_3_2021-9-2(1).pdf` | v1.3 / 2021-09-02 | 第 1、4、9 页 | `6907B4EB59EF93496C5089E01728EEACEC5F187277A8971088201137FDDE5772` | MCON、J6/J7、LED、PHY；进行中 |
| SRC-003 | `D:\MyFPGAProject\UDP\sem-scsg2450-afea-v10(2).pdf` | v1.0 | 尚未逐页核对 | `EB79E07E5B901887AB75EEBE46A5B01162658CA171A37383D2964BB0E2021166` | AFE 跨板路径，待确认 |
| SRC-004 | `D:\MyFPGAProject\UDP\DB500千兆网版通讯协议V1.4_20250113.docx` | V1.4 / 2025-01-13 | 不适用 | `33CC82847B3576AD432168390BA50987C5AF343513DCC110BC746DBBB3F902CF` | 后续 UDP 协议工作包；本环境不据此推导硬件 |
| SRC-005 | 用户对 MCON J6 SGMII 管脚的更正 | 2026-09-07 | 不适用 | 不适用 | TX：B26/B27；RX：A26/A27，用户确认 |
| SRC-006 | 用户提供的 `sys_clk_i` 原理图截图 | 2026-09-08 | AA3 与 `IO_L12P_T1_MRCC_34` 的连线 | 不适用 | 明确确认 `sys_clk_i → AA3 → IO_L12P_T1_MRCC_34`；用于本工作包 ILA 时钟约束 |
| SRC-007 | Marvell *Alaska 88E1111 Datasheet* | Rev. M / 2020-08-31 | 第 64、68、70-72 页 | 官方 URL 见 `AI-work/history/legacy-2026-09-08/diagnostics/m88e1111-mode-2026-09-08/TRACEABILITY.md` | 通过 Codex In-app Browser 审阅；用于 M88E1111 绑带译码 |
| SRC-008 | 用户提供的 MCON J6 / CORE HT2 互连截图 | 2026-09-08 | `B16_L21_P/N`、`B16_L24_P` 至 FPGA | SHA-256 见 `AI-work/history/legacy-2026-09-08/diagnostics/m88e1111-mode-2026-09-08/TRACEABILITY.md` | 视觉复核确认：以网络名跨接，`B16_L21_P/N` 分别经 HT2.A53/A54 至 B14/A14；不可按连接器同名 A/B 行号机械对应 |

## 2. Bank 与专用电源

电源网名和实际电压分列；`VADJ1/VADJ2` 的实际电压尚未由本次资料闭合。只有 Bank 0、15 的具体开发用途已完成电压确认。

| Bank / 资源 | 专用供电脚与电源网 | 已确认电压 | 允许 IOSTANDARD | 来源 | 状态 |
|---|---|---|---|---|---|
| Configuration Bank 0 | `VCCO_0`：T6/L7 → `VCC3V3`；`CFGBVS_0`：P7 → `VCC3V3` | 3.3 V | 配置属性：`CFGBVS=VCCO`、`CONFIG_VOLTAGE=3.3` | SRC-001 第 4、6 页 | 已确认（可用于开发） |
| Bank 12 | `VCCO_12`：U23/V20/Y24/AA21/AC25/AD22/AF26 → `VADJ2` | 待确认 | 待确认 | SRC-001 第 6 页 | 待确认 |
| Bank 13 | `VCCO_13`：K24/N25/P22/R19/T16/T26 → `VADJ2` | 待确认 | 待确认 | SRC-001 第 6 页 | 待确认 |
| Bank 14 | `VCCO_14`：A21/C25/D22/F26/G23/L21 → `VADJ1` | 待确认 | 待确认 | SRC-001 第 6 页 | 待确认 |
| Bank 15 | `VCCO_15`：B18/E19/F16/H20/J17/M18 → `VADJ1` | 用户确认 3.3 V | `LVCMOS33`（普通单端 IO） | SRC-001 第 6 页 + 用户确认 | 用户确认；仅当具体信号端到端闭合后可用于开发 |
| Bank 16 | `VCCO_16`：A11/B8/C15/D12/E9/G13/H10 → `VCC3V3` | 3.3 V | `LVCMOS33`（普通单端 IO） | SRC-001 第 6 页 + SRC-008 / 用户确认 | 已确认；MDC/MDIO 端点已闭合，其余接口按需确认 |
| Bank 32 | `VCCO_32`：W17/Y14/AB18/AC15/AE19/AF16 → `VCC1V5` | 1.5 V | 待具体接口确认 | SRC-001 第 6 页 | 已确认（电压）；接口待确认 |
| Bank 33 | `VCCO_33`：V10/W7/AA11/AB8/AD12/AE9 → `VCC1V5` | 1.5 V | 待具体接口确认 | SRC-001 第 6 页 | 已确认（电压）；接口待确认 |
| Bank 34 | `VCCO_34`：U3/Y4/AA1/AC5/AD2/AF6 → `VCC1V5` | 1.5 V | `LVCMOS15`（仅限已逐项核对的普通单端 IO） | SRC-001 第 6 页 | 已确认（电压）；接口待确认 |
| MGT115/MGT116 | `MGTAVCC`/`MGTAVTT`、`MGT1V0`、`MGT1V2`、`MGTAUX` | 电源网已见；接口使用时再逐项核对 | 不适用 | SRC-001 第 5、6 页 | 待确认 |

## 3. 已逐项核对的单信号映射

本节只列出已经按图页视觉核对的信号。它不是“全量完成”的声明；其余 FPGA 相连网络仍处于逐行重建队列中。

| FPGA ball / 专用站点 | Bank / 资源类型 | FPGA 原理图引脚名 | 核心板网络 | 核心板端点或连接器针脚 | 对端板/器件/针脚 | 电气事实 | 精确来源 | 状态 |
|---|---|---|---|---|---|---|---|---|
| P7 | Configuration Bank 0 | `CFGBVS_0` | `VCC3V3` | 直连配置电平 | 不适用 | 配置电压为 3.3 V | SRC-001 第 4、6 页 | 已确认（可用于开发） |
| T5 | Configuration Bank 0 | `M0_0` | `VCC3V3` | 直连模式脚 | 不适用 | 模式脚；不是 CFGBVS | SRC-001 第 4 页 | 已确认 |
| C8 | Configuration Bank 0 | `CCLK_0` | `FLASH_CLK` | QSPI IC1.SCK（经 R6） | `S25FL256SAGNFI00` | 33 Ω 串阻 | SRC-001 第 4 页 | 已确认；Flash 工作包才可引用 |
| B24 | Bank 14 | 普通 IO | `FLASH_IO0` | QSPI IC1.SDO/DQ1 | `S25FL256SAGNFI00` | Bank 14 电压未闭合 | SRC-001 第 2、4、6 页 | 待确认 |
| A25 | Bank 14 | 普通 IO | `FLASH_IO1` | QSPI IC1.SDI/DQ0 | `S25FL256SAGNFI00` | Bank 14 电压未闭合 | SRC-001 第 2、4、6 页 | 待确认 |
| B22 | Bank 14 | 普通 IO | `FLASH_IO2` | QSPI IC1.WP/DQ2 | `S25FL256SAGNFI00` | Bank 14 电压未闭合 | SRC-001 第 2、4、6 页 | 待确认 |
| A22 | Bank 14 | 普通 IO | `FLASH_IO3` | QSPI IC1.HOLD/DQ3 | `S25FL256SAGNFI00` | Bank 14 电压未闭合 | SRC-001 第 2、4、6 页 | 待确认 |
| C23 | Bank 14 | 普通 IO | `FLASH_nCS` | QSPI IC1.CS | `S25FL256SAGNFI00` | Bank 14 电压未闭合 | SRC-001 第 2、4、6 页 | 待确认 |
| P6 | Configuration Bank 0 | `PROGRAM_B_0` | `PROG` | R9 上拉至 `VCC3V3` | 不适用 | 配置专用脚 | SRC-001 第 4 页 | 已确认 |
| L8 | Configuration Bank 0 | `TCK_0` | `JTAG_TCK` | P1.9（核心板 JTAG Header） | JTAG 探头 | 配置专用调试脚 | SRC-001 第 4 页 | 已确认 |
| N8 | Configuration Bank 0 | `TMS_0` | `JTAG_TMS` | P1.5 | JTAG 探头 | 配置专用调试脚 | SRC-001 第 4 页 | 已确认 |
| R6 | Configuration Bank 0 | `TDI_0` | `JTAG_TDI` | P1.3 | JTAG 探头 | 配置专用调试脚 | SRC-001 第 4 页 | 已确认 |
| R7 | Configuration Bank 0 | `TDO_0` | `JTAG_TDO` | P1.1 | JTAG 探头 | 配置专用调试脚 | SRC-001 第 4 页 | 已确认 |
| U20 | Bank 13 | `IO_L18P_T2_13` | `B13_L18_N` | HT1.A36 | MCON J5.B36 | Bank 13 电压为 `VADJ2`，实际值待确认 | SRC-001 第 2、6、10 页；SRC-002 第 4 页 | 核心板到 MCON 连接器已确认；功能待确认 |
| U19 | Bank 13 | `IO_L17N_T2_13` | `B13_L18_P` | HT1.A35 | MCON J5.B35 | Bank 13 电压为 `VADJ2`，实际值待确认 | SRC-001 第 2、6、10 页；SRC-002 第 4 页 | 核心板到 MCON 连接器已确认；功能待确认 |
| A18 | Bank 15 | `IO_L1P_T0_AD0P_15` | `B150L20P`（连接器页标作 `B15_L2_P`） | HT3.B36 | MCON J7.A36 → `LED1` → R7/Q1/D1 | Bank 15 为用户确认 3.3 V；MCON 端 Q1 为 N-MOS 低端开关，控制高电平点亮 | SRC-001 第 2、6、10 页；SRC-002 第 1、4 页；用户确认（2026-09-07） | 用户确认（可用于 LED 开发） |
| AA3 | Bank 34 | `IO_L12P_T1_MRCC_34` | `sys_clk_i` | IC2.3 `OUT`，100 MHz 本振输出 | FPGA 系统/调试采样时钟 | Bank 34 为 1.5 V；该单端时钟输入使用 `LVCMOS15`；`MRCC` 可作全局时钟输入 | SRC-001 第 3 页；SRC-001 第 6 页；SRC-006 | 用户视觉确认（可用于 ILA 调试） |
| A3/A4 | MGT116 lane 3 TX | `MGTXTXN3_116` / `MGTXTXP3_116` | `MGT116_TX3_N/P` | HT2.A25/A26 | MCON J6.B26/B27 → C536/C535 → M88E1111 S_IN-/S_IN+ | 100 Ω 差分；AC 耦合；TX 相对 FPGA | SRC-001 第 5、10 页；SRC-002 第 4、9 页；SRC-005 | 已确认（可用于后续 SGMII 方案） |
| B5/B6 | MGT116 lane 3 RX | `MGTXRXN3_116` / `MGTXRXP3_116` | `MGT116_RX3_N/P` | HT2.B25/B26 | MCON J6.A26/A27 → C538/C537 → M88E1111 S_OUT-/S_OUT+ | 100 Ω 差分；AC 耦合；RX 相对 FPGA | SRC-001 第 5、10 页；SRC-002 第 4、9 页；SRC-005 | 已确认（可用于后续 SGMII 方案） |
| D5/D6 | MGT116 REFCLK0 | `MGTREFCLK0N/P_116` | `MGT116_CLK0_N/P` | HT2.A27/A28 | MCON J6.B30/B31；MCON 侧来源尚未闭合 | 差分 GT 参考时钟；频率待确认 | SRC-001 第 5、10 页；SRC-002 第 4 页 | 待确认 |
| B14 | Bank 16 | 普通 IO | `B16_L21_P` | CORE HT2.A53；MCON J6.B54 / `B16_L21_P` | U82.B1 → `PHY_MDC_L` → M88E1111 MDC | Bank 16 为用户确认 3.3 V；MDC 输出使用 `LVCMOS33` | SRC-001 第 10 页；SRC-002 第 4、9 页；视觉复核 | 已确认（正确 MDC 端点） |
| A14 | Bank 16 | 普通 IO | `B16_L21_N` | CORE HT2.A54；MCON J6.B55 / `B16_L21_N` | U82.B2 → `PHY_MDIO_L` → M88E1111 MDIO | Bank 16 为用户确认 3.3 V；MDIO 必须为三态/开漏 `LVCMOS33` | SRC-001 第 10 页；SRC-002 第 4、9 页；视觉复核 | 已确认（正确 MDIO 端点） |
| A13 | Bank 16 | 普通 IO | `B16_L24_P` | CORE HT2.A55；MCON J6.B56 / `B16_L24_P` | U82.B3 → `PHY_INT_L` → M88E1111 INTN | Bank 16 为用户确认 3.3 V；首轮不驱动 | SRC-001 第 10 页；SRC-002 第 4、9 页；视觉复核 | 已确认（后续中断观察可用） |
| E13/E12 | Bank 16 | 普通 IO | `B16_L18_P/N` | CORE HT2.B54/B55 | 非 PHY 管理网络；不得用于 MDC/MDIO | Bank 16 3.3 V，但端点功能未追踪 | SRC-001 第 10 页 | 已确认不用于 M88E1111 管理接口 |

## 4. 功能路径

| 功能 | 已证实路径 | 可用结论 | 来源与状态 |
|---|---|---|---|
| JTAG | FPGA `TCK/TMS/TDI/TDO` → Core P1 Header；MCON 另有 J4 JTAG 接口，但本次未重新追踪 Core 与 MCON 物理调试连接 | 可进行已经授权的被动枚举；下载仍需工作包明确授权 | SRC-001 第 4 页；SRC-002 第 4 页；只读日志，已确认 |
| QSPI 配置 | FPGA 配置 Bank 0 与 IC1 `S25FL256SAGNFI00` 已闭合 | Flash 型号与 FPGA 配置网络已知；Bank 14 的 VADJ1 电压未确认，不能制定 Flash XDC/写入方案 | SRC-001 第 2、4、6 页，部分确认 |
| SGMII | MGT116 lane 3 TX/RX 已闭合至 M88E1111 的 SGMII 收发引脚 | TX/RX lane、方向、P/N、AC 耦合已知；REFCLK 频率和 PHY 控制尚缺 | 上表 + SRC-005，部分确认 |
| M88E1111 启动配置 | U79 `CONFIG[0:6]` 在 `RESETn` 释放时锁存 | `HWCFG_MODE=0100`：SGMII without clock with SGMII Auto-Negotiation to copper；`ANEG=1110`：铜口自协商、全能力、preferred master；MDIO 地址 `0x07` | SRC-002 第 9 页 + SRC-007；详见 `AI-work/history/legacy-2026-09-08/diagnostics/m88e1111-mode-2026-09-08/TRACEABILITY.md`，已确认 |
| M88E1111 MDIO | FPGA B14/A14（Bank 16）→ CORE HT2.A53/A54 → MCON J6.B54/B55 → U82 → PHY MDC/MDIO | `MDC=B14`、`MDIO=A14`；Bank 16 为 3.3 V；MDIO 使用三态/开漏 `LVCMOS33`。E13/E12 为 `B16_L18_P/N`，不是 PHY 管理接口。 | SRC-001 第 10 页；SRC-002 第 4、9 页；SRC-008；视觉复核；详见 `AI-work/history/legacy-2026-09-08/diagnostics/m88e1111-mdio-pin-mapping-2026-09-08/PIN_MAPPING_CORRECTION.md`，已确认 |
| M88E1111 MDIO 运行态（历史错误端点） | 先前探针错误连接 FPGA E13/E12，即 `B16_L18_P/N` | ILA 中的低电平、PHYID1/2 与 reg27 的 `0x0000` 仅反映错误端点；不构成 M88E1111、U82、R374/R389、MDIO 上拉或 PHY 配置的运行态证据。该次验收已作废，正确端点结果见下一行。 | `AI-work/history/legacy-2026-09-08/diagnostics/m88e1111-mdio-pin-mapping-2026-09-08/PIN_MAPPING_CORRECTION.md`；先前验收 `INVALIDATED` |
| M88E1111 MDIO 运行态（B14/A14） | FPGA B14/A14 → HT2.A53/A54 → J6.B54/B55 → U82 → M88E1111 | A14 高阻释放后 100/250/400 ns 均回高，Clause 22 `TA=Z0`；地址 `0x07` 读回 PHYID=`0x0141_0CC2`、reg27=`0x8484`（mode=`0100`）、BMCR AN=1；BMSR 双读=`0x796D`（Link=1、AN Complete=1）。 | `AI-work/history/legacy-2026-09-08/work-packages/m88e1111-runtime-validation-2026-09-08/out/hardware/B14_A14_RUNTIME_ILA_DECODE.md`，已确认（2026-09-08） |
| MCON LED1 | MCON `LED1` → J7.A36 → Core HT3.B36 → `B15_L2_P/B150L20P` → FPGA A18 | LED 端到端路径由用户确认；MCON 第 1 页表明 FPGA 输出高电平使 Q1 导通、D1 点亮。 | SRC-001 第 2、6、10 页；SRC-002 第 1、4 页；用户确认（2026-09-07），可用于 LED 开发 |
| `sys_clk_i` | IC2（100 MHz）→ `sys_clk_i` → FPGA AA3（Bank 34） | 可为 LED ILA 提供 100 MHz 采样时钟；约束为 AA3 / `LVCMOS15` / 10.000 ns。该结论仅覆盖本工作包的 ILA 采样，不推出其他时钟或接口的时序约束。 | SRC-001 第 3、6 页；SRC-006，用户确认 |
| `B13_L18_N` | FPGA U20 → Core HT1.A36 → MCON J5.B36 | 这是独立已知 IO 路径；当前资料的 `LED1` 网络位于 MCON J7.A36，而非 J5.B36 | SRC-001 第 2、10 页；SRC-002 第 4 页，核心板到 MCON 连接器已确认 |

## 5. 待确认项

| 编号 | 事实 | 影响 | 最小下一证据 |
|---|---|---|---|
| OQ-001 | Core HT1/HT2/HT3 与 MCON J5/J6/J7 的其余接口互配关系、方向及装配版本 | 除 LED1 外的跨板接口 | 板卡照片/装配图/BOM，或连接器配对说明；LED1 路径已由用户确认，不受此项阻塞 |
| OQ-002 | `LED1` 的端到端路径 | 已解决：用户确认 `LED1→J7.A36→HT3.B36→B150L20P→A18`；`B13_L18_N/U20` 为另一条独立、非 LED 路径 | LED 下载验证可选择 A18/Bank 15，采用高电平点亮 |
| OQ-003 | `VADJ1`、`VADJ2` 实际电压 | Bank 12/13/14/15 的 IOSTANDARD | 电源/BOM/实测记录；不得用网名推断 |
| OQ-004 | MGT116 REFCLK0 的来源、频率、抖动 | SGMII/UDP GT IP | MCON 第 8 页与板级资料；M88E1111 strap 已由诊断记录闭合 |
| OQ-005 | `PHY_RESET_L` 的 FPGA 端点与复位时序 | 需要主动复位 PHY 时 | MCON J6/CORE HT2 互连资料、M88E1111 数据手册；首轮只读 MDIO 不受阻塞 |
| OQ-006 | 其余 FPGA 普通 IO、DDR、GT 和连接器网络的逐行重建 | 通用后续需求 | 按 SRC-001 页与对端资料逐项登记 |

## 6. 变更记录

| 日期 | 变更 | 结论 |
|---|---|---|
| 2026-09-07 | 首版 Mode 4 记录 | 已废止：401 条扁平文本映射不能证明端到端路径，不得继续引用。 |
| 2026-09-07 | Mode 4 重建 | 建立 Bank 电源表、单信号表和功能路径表；视觉核对 SRC-001 第 2/4/5/6/10 页与 SRC-002 第 1/4/9 页。 |
| 2026-09-07 | LED 路径复核 | 撤销旧的 `LED1 → M17/B150L230P` 结论。图纸连接器配对给出的候选为 `LED1 → J7.A36 → HT3.B36 → B150L20P → A18`，但它与用户提出的 `LED1→B13_L18_N` 冲突，故暂不用于开发。 |
| 2026-09-07 | `B13_L18_N` 复核 | 确认 `B13_L18_N → U20 → HT1.A36 → MCON J5.B36`；它与 MCON `LED1` 的 J7.A36 路径不同。 |
| 2026-09-07 | LED1 路径用户确认 | 用户确认端到端路径为 `LED1 → J7.A36 → HT3.B36 → B150L20P → FPGA A18`。A18 位于 Bank 15，使用已确认的 3.3 V 和 `LVCMOS33`；输出高电平点亮。 |
| 2026-09-08 | ILA 采样时钟核对 | 用户截图确认 `IC2（100 MHz）→sys_clk_i→AA3`，AA3 的 FPGA 引脚名为 `IO_L12P_T1_MRCC_34`；Bank 34 供电为 1.5 V，采用 `LVCMOS15`。此前从 PDF 文本抽取推断的 AA2 / `IO_L12P` 以及 AA3 / `IO_L11N` 均已撤销，不得用于约束。 |
| 2026-09-08 | M88E1111 启动绑带取证 | 原理图第 9 页和官方数据手册 Table 32/34/35 闭合：`HWCFG_MODE=0100`、`ANEG=1110`、MDIO 地址 `0x07`。用户提供局部图校正了 `CONFIG[4]→LED_LINK1000` 的读图位置；完整证据链见 `AI-work/history/legacy-2026-09-08/diagnostics/m88e1111-mode-2026-09-08/TRACEABILITY.md`。 |
| 2026-09-08 | M88E1111 管理 IO 映射更正 | 首轮把 J6.B54/B55 与 HT2.B54/B55 按行号机械对应，误得 E13/E12。以共同网络名 `B16_L21_P/N` 复核后，正确路径是 J6.B54/B55 → HT2.A53/A54 → FPGA B14/A14；INT 是 J6.B56 → HT2.A55 → A13。见 `AI-work/history/legacy-2026-09-08/diagnostics/m88e1111-mdio-pin-mapping-2026-09-08/PIN_MAPPING_CORRECTION.md`。 |
| 2026-09-08 | M88E1111 运行态 MDIO 采集 | 易失下载只读探针曾在 E13/E12 执行；`u_ila_mdio` 的低电平和 PHYID1/2/reg27 的 `0x0000` 仅反映 `B16_L18_P/N` 错误端点，不能证明管理线或 PHY 异常。未写 PHY、未复位、未写 Flash；该验收已作废。 |
| 2026-09-08 | M88E1111 MDIO 静态复测（用户报告） | U82.A2、U82.B2 均为高，U82.OE≈2.4 V；与 R374/R385 的 `VCC2V5` 域和 U82 静态使能一致。该静态测量与正确 MDIO 路径 A14 相容；不能与此前错误端点 E12 的 ILA 作直接比较。 |
| 2026-09-08 | M88E1111 无示波器 MDIO 动态自检 | 该 ILA 自检同样运行在错误的 E12 端点；其高阻释放采样结果仅记录 `B16_L18_N` 状态，对 M88E1111 MDIO 无结论。重新约束为 A14 后须重新执行。 |
| 2026-09-08 | M88E1111 正确端点运行态验证 | XDC 更正为 `MDC=B14`、`MDIO=A14` 后重构建、JTAG 易失下载并只读 ILA。开漏释放、PHY ID、reg27 mode、BMCR/ANAR/R9 与 BMSR 双读均通过；芯片实际处于 `HWCFG_MODE=0100`、自协商已启用且采集时链路/协商完成。完整原始证据和哈希见本工作包 `out/hardware/B14_A14_RUNTIME_ILA_DECODE.md`。 |
