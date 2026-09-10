# LED 静态逻辑仿真与 ILA 调试 - 执行记录

状态：`EXECUTED_AWAITING_ACCEPTANCE`

## 1. 执行边界

用户于 2026-09-08 批准本工作包的 S、B 和 H 流程：允许一次易失 JTAG 配置及一次立即触发 ILA 采集；未执行 Flash 写入、PHY/MDIO 操作或网络流量。未提交、未推送。

执行前已将用户的原理图截图结论同步至 `D:\MyFPGAProject\UDP\AI-work\HARDWARE_ENVIRONMENT.md`：`IC2（100 MHz）→sys_clk_i→AA3`，AA3 为 Bank 34 的 `IO_L12P_T1_MRCC_34`，约束为 `LVCMOS15` 与 10.000 ns。此前从 PDF 文本抽取产生的 AA2 / AA3 推断已撤销。

## 2. S — 项目仿真

- 使用工程 `D:\MyFPGAProject\UDP\fpga\led\led.xpr` 的 `sim_1`，仿真 top 为 `led_static_tb`，有限运行 40 ns；
- 自检 testbench `D:\MyFPGAProject\UDP\fpga\led\led.srcs\sim_1\new\led_static_tb.v` 报告 `SIM_PASS`：`led1` 为高，且 4 个 100 MHz 时钟上升沿均被检查；
- 结果记录：[SIMULATION_RESULT.txt](out/sim/led-static-20260908-r1/SIMULATION_RESULT.txt)；原生波形为 `D:\MyFPGAProject\UDP\fpga\led\led.sim\sim_1\behav\xsim\led_static_tb_behav.wdb` 与同名 `.wcfg`。

## 3. B — ILA 调试镜像构建

- 创建并接入 1-bit、1024 深度的 `ila_led`，RTL 实例名 `u_ila_led`，仅采集 `led1`；
- 同一工程的 `synth_1` 与 `impl_1` 完成，产生匹配的 bit/LTX：
  - `D:\MyFPGAProject\UDP\fpga\led\led.runs\impl_1\led_static.bit`
  - `D:\MyFPGAProject\UDP\fpga\led\led.runs\impl_1\led_static.ltx`
- LTX 身份为 `u_ila_led / probe0 / led1_OBUF`，UUID `E4E189F151DA57AFA5511E4699FF034A`；
- 构建结果为 `BUILD_PASS`，无阻断 DRC；4 条非阻断 Warning（`PDCN-1569` ×3、`RTSTAT-10` ×1）均来自 Vivado 自动插入的 `dbg_hub` / ILA 调试网络，完整记录见 [BUILD_RESULT.txt](out/build/led-ila-debug-20260908-r6/BUILD_RESULT.txt)。

## 4. H — JTAG 下载与 ILA 采集

1. 预检项目硬件工作区：`ILA_OUTPUT_READY`，`D:\MyFPGAProject\UDP\fpga\led\led.hw\hw_1` 未被占用。
2. 只读重新枚举 JTAG：目标为 `localhost:3121/xilinx_tcf/Digilent/E3077BAA4210`，设备为 `xc7k325t_0`（part `xc7k325t`）。枚举脚本与日志在 [out/ila/led-static-immediate-20260908](out/ila/led-static-immediate-20260908/)。
3. 使用上述匹配 bit/LTX 对 `xc7k325t_0` 执行 **一次** `program`（易失 JTAG）策略。执行器按精确 `CELL_NAME=u_ila_led` 匹配 ILA，复位所有比较条件为 don't-care 后立即触发；未增加重试或第二次采集。
4. 采集结果为 `ILA_CAPTURE_PASS`：状态 `FULL`，采样数 `1024/1024`，原生文件为 `D:\MyFPGAProject\UDP\fpga\led\led.hw\backup\led-static-immediate-20260908.ila`（7460 bytes）。
5. 对该已导出 `.ila` 做了离线只读检查：其内的 `waveform.csv` 与 `waveform.dmp` 均显示探针 `led1_OBUF` 的 1024 个样本全部为 `1`。未重新配置 FPGA、未再次触发 ILA，也未把原生采集复制进 `AI-work`。

硬件执行器的机读结果见 [ILA_CAPTURE_RESULT.txt](out/ila/led-static-immediate-20260908/ILA_CAPTURE_RESULT.txt)。
