# LED 静态逻辑仿真与 ILA 调试 - 验收

状态：`READY_FOR_USER_ACCEPTANCE`

## 验收结论

| 验收项 | 结果 | 证据 |
|---|---|---|
| S：LED 静态逻辑仿真 | `PASS` | 40 ns 自检仿真输出 `SIM_PASS`；`led1` 为高且 4 个时钟上升沿检查通过。 |
| B：ILA debug bit/LTX | `PASS` | `synth_1` 与 `impl_1` 完成，`BUILD_PASS`，无阻断 DRC，bit/LTX 匹配 `u_ila_led`。 |
| H：下载、采集与读回 | `PASS` | 精确 JTAG target/device 匹配；一次易失 `program` 成功；`u_ila_led` 立即采集 `FULL`，1024/1024 样本；离线读取原生 `.ila`，`led1_OBUF` 的 1024 个样本全部为 `1`。 |

## 实际交付文件

- `D:\MyFPGAProject\UDP\fpga\led\led.srcs\sources_1\new\led_static.v`：常量高 LED 输出及 `u_ila_led` 实例；
- `D:\MyFPGAProject\UDP\fpga\led\led.srcs\constrs_1\new\led_static.xdc`：LED 的 A18 约束，以及确认后的 `sys_clk_i` AA3 / `LVCMOS15` / 10 ns 约束；
- `D:\MyFPGAProject\UDP\fpga\led\led.srcs\sources_1\ip\ila_led\ila_led.xci` 与 `D:\MyFPGAProject\UDP\fpga\led\scripts\ip\create_ila_led.tcl`：RTL 实例化 ILA；
- `D:\MyFPGAProject\UDP\fpga\led\led.srcs\sim_1\new\led_static_tb.v`：自检 testbench；
- `D:\MyFPGAProject\UDP\fpga\led\scripts\sources.tcl`：上述源、约束、IP 与 testbench 的显式工程清单。

## 本次需求的已证实范围

`led_static.bit` 已能通过 JTAG 易失下载至已连接的 `xc7k325t_0`；设计使用确认的 `sys_clk_i → AA3 → IO_L12P_T1_MRCC_34` 时钟域，FPGA 内部/输出网 `led1_OBUF` 在一次完整 ILA 采集中持续为高。

这证明下载链路、已加载 FPGA 逻辑和所观测的 FPGA 输出网均正常。它不替代对 LED 发光亮度、LED 极性、供电或人工视觉观察的独立电气验收；本次没有进行 Flash 固化。

## 验收材料

- [执行记录](EXECUTION.md)
- [仿真结果](out/sim/led-static-20260908-r1/SIMULATION_RESULT.txt)
- [构建结果](out/build/led-ila-debug-20260908-r6/BUILD_RESULT.txt)
- [ILA 机读结果](out/ila/led-static-immediate-20260908/ILA_CAPTURE_RESULT.txt)
- 原生 ILA 采集：`D:\MyFPGAProject\UDP\fpga\led\led.hw\backup\led-static-immediate-20260908.ila`

待你确认验收后，才可进入提交/推送阶段。
