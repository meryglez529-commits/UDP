# 执行记录

日期：2026-09-08
状态：`IN_PROGRESS`

用户已批准按照 `PLAN.md` 执行。尚未修改 RTL、XDC、IP 或工程设置；尚未下载、复位、写 PHY 或写 Flash。

## H1/H2 前置枚举

- 时间：2026-09-08 16:09（Vivado batch）。
- 已连接目标：`localhost:3121/xilinx_tcf/Digilent/E3077BAA4210`，设备 `xc7k325t_0`。
- 结果：`get_hw_ilas -of_objects xc7k325t_0` 未发现任何 ILA，故当前 FPGA 为非调试镜像，无法执行无下载的 H1/H2。
- 已安全退出 Hardware Manager；未采集、未下载、未修改 PHY/reset/Flash。
- 后续：按计划的现场镜像回退条款，对工程现有的匹配 debug bitstream 做一次 JTAG 易失下载后重试 H1/H2。

## 调试镜像加载与 LTX 发现

- 已 JTAG 易失下载：`D:\MyFPGAProject\UDP\fpga\led\led.runs\impl_1\led_static.bit`，SHA-256 `A880411F597135753C0546533CE4E8C3EE1E1CF5686F07C9303511FE94B7095F`。
- 匹配 LTX：`D:\MyFPGAProject\UDP\fpga\led\led.runs\impl_1\led_static.ltx`，SHA-256 `52367CE4B3669B5D471B4D1767E08867F17C555B38DADCD7D56CB27CEFAE1E97`。
- 下载后 Hardware Manager 已报告两个 ILA：`u_ila_led` 与 `u_ila_mdio`（`mdio_debug` 宽度 48）。未写 Flash、PHY 或 reset。
- 首次 H1/H2 采集会话未设置每会话性的 `PROBES.FILE`，故未发现 ILA 并安全退出。已修正采集 Tcl：在不下载 FPGA 的前提下设置上述匹配 LTX 并 `refresh_hw_device`，再采集。

## H1/H2：现有镜像的 ILA 采集

- H1 空闲态：16,384/16,384 sample 均为 `mdio_in=1`、`mdio_drive_low=0`、`MDC=0`、`reader_busy=0`、`sequence_done=1`，通过。
- H2：首个事务 preamble 的 32 个 MDC 上升沿均为释放高，且相邻上升沿间距 100 sample（1 MHz）；同一采集后续事务的 preamble 已为释放低，触发条件与原始数据见 `out/hardware/MDIO_DYNAMIC_ILA_DECODE.md`。

## 条件式 B/H3：开漏自检实现、仿真、构建与板级采集

- RTL 修改：`fpga\\led\\led.srcs\\sources_1\\new\\m88e1111_runtime_probe.v` 增加 MDC 恒低的 10 µs 高阻、10 µs 开漏低、释放后 100/250/400 ns 采样，并将五项结果置入既有 48-bit ILA 的 `[47:43]`；`led_static_tb.v` 增加对应自检断言。
- 仿真：`run_mdio_selftest_sim_20260908.log` 输出 `SIM_PASS`；见 `out/sim/SUMMARY.md`。
- 构建：`synth_1` 与 `impl_1` 至 bitstream 均完成；WNS=5.621 ns，TNS=0，Bitgen DRC 0 errors；见 `out/build/SUMMARY.md`。
- 下载：新 bit/ltx 已 JTAG 易失下载到 `xc7k325t_0`，未写 Flash。
- H3 自检：初始释放高与主动低均通过；释放后 100/250/400 ns 全部失败。
- H4：自检后的第一个 32-bit preamble 全部为 FPGA 已释放但 E12 判低，读帧无效。

完整逐 sample 解码、原生产物绝对路径和哈希见 `out/hardware/MDIO_DYNAMIC_ILA_DECODE.md`。
