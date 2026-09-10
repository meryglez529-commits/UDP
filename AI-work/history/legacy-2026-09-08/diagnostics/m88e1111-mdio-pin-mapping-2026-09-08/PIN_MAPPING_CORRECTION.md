# M88E1111 MDC/MDIO FPGA 引脚映射更正

日期：2026-09-08
状态：`CONFIRMED — 仅原理图视觉核对；尚未修改 XDC/RTL 或下载板卡`

## 结论

M88E1111 的管理接口应使用 FPGA Bank 16 的以下球位：

| 功能 | MCON / U82 侧 | MCON J6 | CORE HT2 | FPGA 球位 | 应用约束 |
|---|---|---|---|---|---|
| MDC | U82.B1 经 R388，`PHY_MDC_L → B16_L21_P` | B54，`B16_L21_P` | A53，`B16_L21_P` | **B14** | `mdc` |
| MDIO | U82.B2 经 R389，`PHY_MDIO_L → B16_L21_N` | B55，`B16_L21_N` | A54，`B16_L21_N` | **A14** | `mdio`，开漏/三态 |

Bank 16 为已确认的 3.3 V 域，两个单端管理 IO 应使用 `LVCMOS33`。

## 视觉证据

1. MCON 原理图 `D:\MyFPGAProject\UDP\sem-sgsc2450-mcon_v1_3_2021-9-2(1).pdf` 第 4 页：
   - U82.B1/R388 接 `B16_L21_P`，U82.B2/R389 接 `B16_L21_N`；
   - J6 左侧 B54/B55 分别标注 `B16_L21_P/N`。
2. CORE 原理图 `D:\MyFPGAProject\UDP\MK7XCORE676 20190614.pdf` 第 10 页：
   - HT2.A53 的 `B16_L21_P` 连至 FPGA **B14**；
   - HT2.A54 的 `B16_L21_N` 连至 FPGA **A14**。

MCON J6 是 `FX8-120S-SV92`，CORE HT2 是 `FX8-120P-SV92`。两块板相对插接时，符号中的 A/B 行视图相反；不得把 J6 的 `B54/B55` 机械地对应为 HT2 的 `B54/B55`。端到端映射以两页共同出现的网络名 `B16_L21_P/N` 为准。

## 撤销的旧映射与运行态测试影响

| 已撤销项 | 原映射 | 为什么错误 |
|---|---|---|
| MDC | E13 / `B16_L18_P` | CORE HT2.B54 是 `B16_L18_P`，不是 MCON 的 `B16_L21_P`。 |
| MDIO | E12 / `B16_L18_N` | CORE HT2.B55 是 `B16_L18_N`，不是 MCON 的 `B16_L21_N`。 |
| INT | B15 / `B16_L23_P` | U82.B3 使用 `B16_L24_P`；其 CORE 对端为 HT2.A55 / FPGA A13。该信号未在首轮驱动。 |

因此，先前以 E13/E12 实施的 ILA 自检只覆盖 `B16_L18_P/N` 这对非 PHY 管理网络。其“拉低后不回高”的结果与一个未接到 U82/R374 的端点一致，**不能**作为 M88E1111、U82、R389 或 PHY_MDIO_L 的故障证据；相应运行态验收已作废。

## 后续边界

尚未把 XDC 改为 B14/A14，尚未重新构建或下载。下一项工作必须以本记录为硬件事实来源，更新唯一工程 `D:\MyFPGAProject\UDP\fpga\led\led.xpr` 的 MDC/MDIO 约束后，重新进行仿真、构建与只读 ILA 验证。
