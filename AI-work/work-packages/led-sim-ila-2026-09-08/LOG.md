# LED 静态逻辑仿真与 ILA 调试 - 日志

| 日期 | 阶段 | 事件 | 结果 |
|---|---|---|---|
| 2026-09-08 | 计划 | 用户批准 S、B、H；范围为仿真、调试镜像、一次易失下载和一次立即采集。 | `APPROVED_FOR_EXECUTION` |
| 2026-09-08 | 硬件事实 | 用户截图确认 `sys_clk_i → AA3 → IO_L12P_T1_MRCC_34`；Bank 34 供电 1.5 V。 | 环境文件与 XDC 使用 `AA3/LVCMOS15/10 ns` |
| 2026-09-08 | S | `led_static_tb` 在 `sim_1` 中运行 40 ns。 | `SIM_PASS` |
| 2026-09-08 | B | 生成 `u_ila_led` 调试镜像及匹配 LTX。 | `BUILD_PASS` |
| 2026-09-08 | H | JTAG 枚举并一次易失下载；对 `u_ila_led` 立即触发、采样深度 1024。 | `ILA_CAPTURE_PASS`，1024/1024 样本全部为高 |
| 2026-09-08 | 验收 | 写入执行与验收记录。 | `READY_FOR_USER_ACCEPTANCE` |
