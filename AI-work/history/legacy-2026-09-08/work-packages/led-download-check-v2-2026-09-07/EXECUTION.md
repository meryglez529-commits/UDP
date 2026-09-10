# LED 易失下载与板卡指示灯验证 - 执行记录

状态：`COMPLETED_AWAITING_ACCEPTANCE`

## 1. 工程边界

用户已创建 `D:\MyFPGAProject\UDP\fpga\led\led.xpr`，它是本工作包唯一使用的 Vivado 工程。

- 器件：`xc7k325tffg676-2`
- 工具：Vivado 2021.1
- 文件集：`sources_1`、`constrs_1`、`sim_1`
- 运行：`synth_1`、`impl_1`

未创建或使用其他工程；未执行 JTAG 下载、Flash/PHY 写入、网络流量、ILA 或 VIO。

## 2. 工程登记

新增并由 `scripts/create_project.tcl` 显式登记：

| 文件 | 用途 |
|---|---|
| `fpga/led/scripts/sources.tcl` | 明确列出 RTL 与 XDC；不使用目录通配。 |
| `fpga/led/scripts/create_project.tcl` | 打开、校验既有 `.xpr`，登记文件并设置顶层；不创建、覆盖或构建工程。 |
| `fpga/led/scripts/build.tcl` | 检查版本、器件、文件和运行状态后执行获批 B 构建。 |
| `fpga/led/led.srcs/sources_1/new/led_static.v` | `led1` 恒定输出逻辑 1。 |
| `fpga/led/led.srcs/constrs_1/new/led_static.xdc` | A18、`LVCMOS33`、`CFGBVS=VCCO`、`CONFIG_VOLTAGE=3.3`。 |

工程登记命令：

```text
vivado.bat -mode batch -source fpga/led/scripts/create_project.tcl
```

结果：`PROJECT_READY`；已验证 `led.xpr` 中的 `led_static.v`、`led_static.xdc` 与顶层 `led_static`。

## 3. B 构建执行

命令：

```text
vivado.bat -mode batch -source fpga/led/scripts/build.tcl \
  -tclargs AI-work/history/legacy-2026-09-08/work-packages/led-download-check-v2-2026-09-07/out/build/led-static-20260907
```

结果：

- `synth_1`：`synth_design Complete!`
- `impl_1`：`write_bitstream Complete!`
- `BUILD_RESULT.txt`：`BUILD_PASS`
- 实现后 DRC：0 违规
- 工具日志：无 `ERROR:` 或 `CRITICAL WARNING:`
- bitstream：`D:\MyFPGAProject\UDP\fpga\led\led.runs\impl_1\led_static.bit`
- bitstream 大小：11,443,719 字节
- SHA-256：`B70D5D6852800FC78AB80A30B8092DC037140688129E47BBEBF2ED0E6DF908CD`

原生构建报告位于 `fpga/led/led.runs/impl_1/reports/`；外层 Vivado 日志与 `BUILD_RESULT.txt` 位于工作包 `out/build/led-static-20260907/`。

## 4. 未执行流程与限制

- S：未执行。本设计为单一静态组合输出，计划未要求仿真。
- H：未执行。用户明确要求本工作包止于 bitstream，不下载、不观察板级 LED。
- ILA/VIO：未创建，故无 `.ltx` 文件。
- 时序：设计没有时钟、寄存器或时序端点；`timing_summary.rpt` 的 `check_timing` 各项为 0，不存在可用于 WNS/TNS 验收的时钟路径。
