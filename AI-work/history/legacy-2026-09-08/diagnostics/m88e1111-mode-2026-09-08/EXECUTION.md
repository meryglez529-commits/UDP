# 执行记录

日期：2026-09-08

只读审阅原理图第 9 页及官方数据手册。未修改 Vivado 工程、RTL、XDC、IP 或板卡状态；未执行 MDIO、JTAG、下载、ILA 或网络收发。

原理图中的相关绑带为：

- `CONFIG[0]` 接 `VDDO`，编码为 `111`；`CONFIG[1]` 接 `VSS`，编码为 `000`。
- `CONFIG[2]` 接 `VDDO`，编码为 `111`；`CONFIG[3]` 接 `VSS`，编码为 `000`。
- `CONFIG[4]` 经 `R373`（0 ohm）接 `LED_LINK1000`，编码为 `100`；`CONFIG[5]` 接 `LED_LINK10`，编码为 `110`；`CONFIG[6]` 接 `LED_RX`，编码为 `010`。
- `S_CLK+/-` 未连接；`S_IN+/-`、`S_OUT+/-` 接到 FPGA 的 SGMII 差分对。

Table 34 映射得到：

- `PHY address = 0x07`，且 `SEL_TWSI=0`，即选择 MDC/MDIO 管理接口。
- `ANEG[3:0] = 1110`。
- `HWCFG_MODE[2:0] = 100`，`HWCFG_MODE[3] = CONFIG[5][0] = 0`，故 `HWCFG_MODE[3:0] = 0100`。

详细证据链、手册页码、浏览器 URL 和更正历史见 `TRACEABILITY.md`。
