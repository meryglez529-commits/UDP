# LED 易失下载与板卡指示灯验证 - 验收

状态：`PASS_AWAITING_USER_ACCEPTANCE`

## 验收范围

本工作包的获批终点是生成可追溯的 LED bitstream；不包括 JTAG 下载或 LED 实物目视验证。

| 验收项 | 标准 | 结果 |
|---|---|---|
| 硬件路径 | `LED1 → J7.A36 → HT3.B36 → B150L20P → FPGA A18`；Bank 15 3.3 V，`LVCMOS33`，高电平点亮 | 通过；已记录为用户确认的硬件事实。 |
| 工程归属 | 使用用户创建的 `fpga/led/led.xpr`，文件位于标准 `led.srcs` fileset 目录 | 通过；未创建或使用其他工程。 |
| 工程登记 | 显式源清单、项目校验脚本、构建脚本；不以 GUI 手工加文件替代可复现登记 | 通过；顶层为 `led_static`。 |
| B 构建 | `synth_1`、`impl_1` 完成并生成 bitstream | 通过；`synth_design Complete!`、`write_bitstream Complete!`。 |
| DRC | 无阻断违规，且没有 `UCIO-1`、`NSTD-1` | 通过；实现后 DRC 为 0 违规。 |
| bitstream 身份 | 可定位到 `impl_1`，非空且记录哈希 | 通过；11,443,719 字节，SHA-256 `B70D5D6852800FC78AB80A30B8092DC037140688129E47BBEBF2ED0E6DF908CD`。 |
| 时序结论边界 | 不虚报静态组合逻辑的 WNS/TNS | 通过；无时钟、寄存器或时序端点，`check_timing` 各项为 0。 |
| 板级操作 | 不下载、不写 Flash/PHY、不发网络流量 | 通过；H 未执行。 |

## 交付物

- 工程：`D:\MyFPGAProject\UDP\fpga\led\led.xpr`
- bitstream：`D:\MyFPGAProject\UDP\fpga\led\led.runs\impl_1\led_static.bit`
- 构建结果：`AI-work/history/legacy-2026-09-08/work-packages/led-download-check-v2-2026-09-07/out/build/led-static-20260907/BUILD_RESULT.txt`
- 原生报告：`fpga/led/led.runs/impl_1/reports/`

验收结论：`PASS`。等待用户确认后，才提交或推送。
