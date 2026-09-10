# LED 静态逻辑仿真与 ILA 调试 - 计划

状态：`APPROVED_FOR_EXECUTION`

## 1. 目标

在既有 `fpga/led/led.xpr` 工程中完成两项独立证据：

1. **S - 项目仿真**：以自检 testbench 验证 `led_static` 的 LED 输出恒为逻辑高；
2. **H+B - ILA 调试**：在确认的板载时钟域中采样 `led1`，生成匹配的 debug bit/LTX，将调试镜像易失下载到 FPGA，并导出一次立即触发的 ILA 采集。

本工作包不写 Flash、不操作 PHY/MDIO、不发送网络报文，也不改变 LED 的 A18/Bank15 硬件定义。

## 2. 工程与硬件依据

| 项目 | 事实 | 状态 |
|---|---|---|
| 工程 | `D:\MyFPGAProject\UDP\fpga\led\led.xpr`，Vivado 2021.1，`xc7k325tffg676-2` | 已确认 |
| 已验证设计 | `led_static` 输出 A18，高电平点亮 LED1；已有 bitstream 构建通过 | 已确认 |
| ILA 采样时钟 | FPGA AA3，Bank 34，`IO_L12P_T1_MRCC_34`，网络 `sys_clk_i`；核心板第 3 页标注 IC2 `100MHZ` | 已确认；用户截图直接证实 `sys_clk_i → AA3 → IO_L12P_T1_MRCC_34`，Bank 34 为 1.5 V，采用 `LVCMOS15` |
| JTAG 历史枚举 | 目标 `localhost:3121/xilinx_tcf/Digilent/E3077BAA4210`、器件 `xc7k325t_0` | 仅历史证据；H 前重新枚举 |

已有 `led_static.bit` 不含 ILA。为获得 ILA 证据，本工作包会在同一 `led.xpr` 中加入 ILA IP 并重新执行 `impl_1`；这会替换当前 `impl_1` 的 bitstream、报告和生成的调试镜像。不会复制、移动或伪装原生 run 产物。

## 3. 执行范围

### 3.1 时钟事实闭合

1. 核对核心板原理图第 3 页的 `IC2 → sys_clk_i → AA3` 路径、100 MHz 标注及电平网络；
2. 将确认后的单信号映射和功能路径补入 `HARDWARE_ENVIRONMENT.md`，包括 AA3、Bank 34、IOSTANDARD、频率、来源页和状态；用户已提供 AA3 / `IO_L12P_T1_MRCC_34` 的视觉证据；
3. 若连线、频率或电平无法闭合，停止在此步骤：可以继续 S 仿真，但不得新增时钟 XDC、ILA 或下载调试镜像。

### 3.2 S - 自检仿真

新增 `fpga/led/led.srcs/sim_1/new/led_static_tb.v`：

- 实例化当前 LED DUT；
- 在有限仿真时间内检查 `led1 === 1'b1`；
- 失败时使用 `$fatal`，通过时报告 `SIM_PASS`。

通过 `sim_1` 执行 40 ns 有限时长仿真。testbench 会保留在项目 `sim_1/new`；本工作包内的 Tcl oracle 在该有限仿真结束后读取最终 `led1` 值。WDB、WCFG、XSim 日志保留在 `led.sim/sim_1/behav/xsim/`；外层日志和结果保留在本工作包 `out/sim/led-static-20260908-r1/`。

### 3.3 ILA 调试镜像（H+B）

仅在 3.1 通过后，新增或修改：

```text
fpga/led/led.srcs/sources_1/new/led_static.v
fpga/led/led.srcs/constrs_1/new/led_static.xdc
fpga/led/scripts/ip/create_ila_led.tcl
fpga/led/led.srcs/sources_1/ip/ila_led/ila_led.xci
```

具体方案：

- 将已确认的 `sys_clk_i` 作为 `led_static` 输入，并在 XDC 中登记其管脚、电平与 10.000 ns 时钟约束；
- 创建一个 RTL 实例化的 `ila_led` IP：1 个 1-bit probe、采集深度 1024、采样时钟为 `sys_clk_i`；
- ILA 只探测内部 `led1`，不增加控制寄存器、不改变 LED 输出功能；
- 通过同一 `led.xpr` 的 `synth_1`、`impl_1` 生成匹配 bit/LTX；外层构建记录写入 `out/build/led-ila-debug-20260908-r6/`，原生产物保留在 `led.runs/impl_1/`。此前 `r1` 的外层等待被工具窗口截断但底层 run 后续完成；`r2` 因该 run 仍在执行而被正确拒绝；`r3` 尝试对已完成 run 重复 launch 而被拒绝；`r4` 将调试 IP 的非阻断 DRC warning 误判失败；`r5` 将 Vivado 自动生成的 `debug_nets.ltx` 误作第二份候选，均保留日志审计。
- 调试镜像明确授权 `build.tcl` 的 `reset_authorized` 参数重置过期的 `synth_1` 与 `impl_1`；该授权仅适用于本次 ILA debug build，普通构建不会隐式 reset 或覆盖既有 run。

### 3.4 H - 受限下载与一次 ILA 采集

在 H 前：

1. 检查 `led.hw/hw_1` 的输出占用；
2. 重新只读枚举 JTAG，确认目标、设备与器件；
3. 验证同一 `impl_1` 生成的 bit/LTX，确认 ILA `CELL_NAME` 为 `u_ila_led`。

随后仅执行一次 `program` 策略的易失下载和一次默认立即触发采样：所有 probe 比较条件清除为 don't-care，等待上限 10 秒。原生捕获导出至：

```text
fpga/led/led.hw/backup/led-static-immediate-20260908.ila
```

通过条件：精确目标/器件/ILA core 匹配；项目原生 `.ila` 非空且 1024 样本缓冲区已填满。该受限 runner 导出项目原生采样，不自动把样本值复制或解码到 `AI-work`；`led1` 的逻辑高结论由 S 自检覆盖。外层命令日志、镜像身份与结论记录在 `out/ila/led-static-immediate-20260908/`。

## 4. 验证与停止条件

| 流程 | 通过条件 | 立即停止条件 |
|---|---|---|
| S | testbench 自检输出 `SIM_PASS`，且项目原生 WDB/WCFG 存在 | `SIM_FAIL`、仿真输出被占用、编译/展开失败 |
| B | 调试镜像 `impl_1` 完成，DRC 无阻断违规，bit/LTX 属于同一 run | 时钟事实未闭合、run 被占用、DRC/实现/bit/LTX 失败 |
| H | 精确设备/core 匹配，非空 `.ila` 存在，probe0 全部为高 | 目标或镜像不符、Hardware 输出被占用、core 未就绪、超时、采样异常 |

## 5. 授权边界

确认本计划即授权：testbench 与 S 仿真；时钟事实核对和环境文件更新；ILA IP、RTL、XDC、工程源清单和构建脚本修改；一次 debug bit/LTX 构建；一次易失 JTAG 下载；一次立即触发 ILA 采集。

不授权：Flash 操作、PHY/MDIO 操作、网络流量、额外 ILA 采集、试错式更换时钟/管脚，或自定义无超时触发条件。

## 6. 验收与提交

`EXECUTION.md` 记录实际命令、改动、镜像和采集身份；`ACCEPTANCE.md` 区分仿真、debug 构建和板级 ILA 证据。完成后等待用户确认验收；确认前不提交、不推送。
