# SGMII 信号跨板追踪记录

## 状态

- 阶段：0.1 的补充只读追踪
- 状态：LANE_3_CONFIRMED_BY_USER
- 决策问题：M88E1111 的 SGMII 差分对是否能通过 MCON 板间连接器映射到核心板的一条 MGT116 GTX lane？
- 最小证据：MCON J6 信号接触点、核心板 HT2 的 MGT116 接触点，以及用户对实际 HT2-J6 配对关系的确认。
- 禁止操作：不改 `fpga/`，不下载、不写 MDIO、不发包。

## 已追踪的物理路径

| M88E1111 管脚 | MCON 第 9 页网络 | MCON 第 4 页 J6 接触点 | 作用 |
|---|---|---|---|
| `S_IN-`（A4） | 经 C536 后为 `SGMII_TX_N` | `B26` | PHY 的串行输入负端；由 FPGA GTX TX 负端驱动 |
| `S_IN+`（A3） | 经 C535 后为 `SGMII_TX_P` | `B27` | PHY 的串行输入正端；由 FPGA GTX TX 正端驱动 |
| `S_OUT-`（A8） | 经 C538 后为 `SGMII_RX_N` | `A26` | PHY 的串行输出负端；进入 FPGA GTX RX 负端 |
| `S_OUT+`（A7） | 经 C537 后为 `SGMII_RX_P` | `A27` | PHY 的串行输出正端；进入 FPGA GTX RX 正端 |

上述管脚、网络和 J6 接触点均由 MCON 原理图第 4、9 页的可视审阅确认。用户在 2026-09-07 提供的截图再次直接确认了 `SGMII_TX_N = B26`、`SGMII_TX_P = B27`。

## 与核心板连接器的配对关系

核心板原理图第 10 页显示 HT2（`FX8-120P-SV92`）的 MGT116 lane 3：

| HT2 接触点 | 核心板网络 |
|---|---|
| `A25/A26` | `MGT116_TX3_N/P` |
| `B25/B26` | `MGT116_RX3_N/P` |

用户确认：本实物组合板的 MCON J6 与核心板 HT2 按以下接触点关系配对。连接器两侧的行号和观察方向不能由 J5/HT1、J7/HT3 的局部同名网络规则外推；此前将该规则套用至 J6/HT2 的推断是错误的。

| MCON J6 信号 | J6 接触点 | 对应 HT2 接触点 | 核心板网络 | FPGA 方向 | 状态 |
|---|---|---|---|---|---|
| `SGMII_TX_N` | `B26` | `A25` | `MGT116_TX3_N` | FPGA GTX TX 负端 → PHY `S_IN-` | 已确认 |
| `SGMII_TX_P` | `B27` | `A26` | `MGT116_TX3_P` | FPGA GTX TX 正端 → PHY `S_IN+` | 已确认 |
| `SGMII_RX_N` | `A26` | `B25` | `MGT116_RX3_N` | PHY `S_OUT-` → FPGA GTX RX 负端 | 已确认 |
| `SGMII_RX_P` | `A27` | `B26` | `MGT116_RX3_P` | PHY `S_OUT+` → FPGA GTX RX 正端 | 已确认 |

因此，SGMII 使用 MGT116 lane 3，TX/RX 方向和 P/N 极性均保持一致。`A27`、`B27` 在 HT2 页面上的 GND 标注不构成冲突：它们不是本实物 J6 的同名接触点对应端。

## 其他 PDF 的排除结果

已对 AFE 原理图全部 12 页检索 `SGMII` 与 `MGT`。其中只有 B12/B13/B14/B15/B16 等普通 Bank 网络用于 ADC/DAC/AFE；未发现 `SGMII_*`、`MGT116_*` 或 J6/HT2 的跨板续接。因此 AFE PDF 不承担 SGMII lane 映射证据，且不影响已确认的 lane 3 路径。

## 验收结论

- 已确认：从 M88E1111 串行端到 MCON J6 的四个精确接触点。
- 已确认：核心板 HT2 的 MGT116 lane 3 接触点，以及实物组合板的 J6→HT2 配对关系。
- 已确认：完整链路为 `M88E1111 S_IN-/+ → J6 B26/B27 → HT2 A25/A26 → MGT116_TX3_N/P`，以及 `M88E1111 S_OUT-/+ → J6 A26/A27 → HT2 B25/B26 → MGT116_RX3_N/P`。
- 仍待确认：MGT116 实际参考时钟频率、PHY strap/MDIO 地址/复位时序、实物板版本及部署网络参数。上述问题未关闭前，仍不得创建 GTX XDC、PCS/PMA IP 或 RTL。
- 固化建议：后续取得 PCB 网表或 HT2-J6 pin-to-pin 装配表时，将其作为正式发布前的书面追溯证据；这不改变当前 lane 3 的用户确认结论。
