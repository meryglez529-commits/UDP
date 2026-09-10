# LED 易失下载与板卡指示灯验证 - 计划

状态：`APPROVED_FOR_EXECUTION`

## 1. 目标

建立项目的标准 Vivado 工程基座，并为一颗已经端到端确认的板载 LED 生成可追溯的 bitstream，以验证：

1. Vivado 工程能够为本板卡生成有效 bitstream；
2. 已确认的 LED FPGA 管脚、Bank 电压、IOSTANDARD 和有效电平能够形成无阻断 DRC 的约束；
3. 最终 bitstream 能够从项目的 `impl_1` 运行结果中识别和复核。

本工作包只交付 bitstream，不执行 JTAG 下载或任何板级主动操作。不会写 Flash，不会操作 PHY/MDIO，不会发送网络报文，也不会创建 ILA/VIO/IP。

## 2. 当前硬件依据与前置条件

可直接引用的事实：

| 事实 | 依据 | 状态 |
|---|---|---|
| FPGA 器件 | `XC7K325T-2FFG676I`，Vivado 2021.1 | 已确认 |
| JTAG 配置资源 | Configuration Bank 0 为 3.3 V；`CFGBVS=VCCO`、`CONFIG_VOLTAGE=3.3` | 已确认（可用于开发） |
| JTAG 历史枚举 | 曾枚举到唯一 `xc7k325t_0`，目标为 `localhost:3121/xilinx_tcf/Digilent/E3077BAA4210` | 仅历史只读证据；执行前重新枚举 |
| MCON LED 路径 | `LED1 → J7.A36 → HT3.B36 → B150L20P → FPGA A18`；A18 位于 Bank 15 | 原理图页 + 用户确认，已确认（可用于开发） |
| LED 电气属性 | Bank 15 为用户确认 3.3 V；Q1 为低端 N-MOS，控制端高电平时 LED 点亮 | `LVCMOS33`、输出高电平点亮，已确认（可用于开发） |

LED 路径已由用户确认并同步至 `HARDWARE_ENVIRONMENT.md`：`LED1 → J7.A36 → HT3.B36 → B150L20P → FPGA A18`。`B13_L18_N → U20 → HT1.A36 → MCON J5.B36` 保留为另一条独立、非 LED 路径，不用于本工作包。LED XDC 可使用 A18、Bank 15 的 `LVCMOS33` 和高电平点亮逻辑；不再要求装配资料或连续性测量作为本工作包前置条件。

## 3. 执行范围

### 3.1 建立工程基座（Mode 4）

用户已通过 Vivado GUI 创建本工作包的唯一工程：

```text
fpga/led/led.xpr
```

工程已核对为器件 `xc7k325tffg676-2`、Vivado 2021.1，且具备 GUI 创建的 `sources_1`、`constrs_1`、`sim_1`、`synth_1` 与 `impl_1`。本工作包直接在此工程增加：

```text
fpga/led/scripts/create_project.tcl   # 打开、校验并显式登记文件
fpga/led/scripts/sources.tcl          # 受版本控制的显式源清单
fpga/led/scripts/build.tcl            # 打开既有 .xpr 并执行获批构建
```

脚本不创建或覆盖 `.xpr`，不使用 `create_project -force`，不添加占位 RTL/XDC/IP，也不启动 Hardware Manager。

### 3.2 LED 硬件路径记录

LED1 的端到端路径、Bank 电压、IOSTANDARD 和有效电平已经在 `HARDWARE_ENVIRONMENT.md` 中以用户确认证据闭合。本工作包不再为该路径重复取证；如果执行中发现它与实际板级观测不符，立即停止，保留观测并重新打开硬件环境记录。

### 3.3 实现 LED 静态点亮逻辑

仅在 LED 路径确认后，新增并登记：

```text
fpga/led/led.srcs/sources_1/new/led_static.v
fpga/led/led.srcs/constrs_1/new/led_static.xdc
```

逻辑为单输出常量，使用已确认的“点亮”电平；不引入未确认的时钟，也不伪造时序约束。XDC 只包含确认后的 `PACKAGE_PIN`、`IOSTANDARD` 和 Configuration Bank 0 配置属性。

### 3.4 构建（B）

通过 `fpga/led/scripts/build.tcl` 打开既有 `led.xpr`，执行 `synth_1` 和 `impl_1` 至 `write_bitstream`。构建记录写入：

```text
AI-work/history/legacy-2026-09-08/work-packages/led-download-check-v2-2026-09-07/out/build/<build-id>/
```

原生 runs、报告和 bitstream 留在 `fpga/led/led.runs/`。通过条件为：实现完成、bitstream 存在、DRC 无阻断违规、无未解决的 `UCIO-1`/`NSTD-1`、并记录时序报告。静态无时钟逻辑没有可评估的用户时钟时，报告该限制而不虚报 WNS/TNS。

### 3.5 板级操作

本工作包不选择 H 流程，不枚举 JTAG、不下载 bitstream、不观察 LED。bitstream 仅作为后续经批准的板级下载工作包的输入候选；构建通过不等于已证明下载链路或 LED 实物行为。

## 4. 验证选择

| 流程 | 是否执行 | 决策问题 | 通过条件 | 停止条件 |
|---|---|---|---|---|
| S - 仿真 | 不执行 | 静态常量输出不需要额外功能仿真证据 | 不适用 | 需求改为闪烁、时序或复杂逻辑时重审 |
| B - 构建 | 执行 | 已确认的工程、RTL、XDC 能否生成有效镜像 | 本计划 3.4 的构建条件全部满足 | 硬件事实未闭合、工程/运行被占用、实现或 DRC 失败 |
| H - 下载 | 不执行 | 本工作包不进行板级操作 | 不适用 | 后续请求下载或硬件观测时创建/更新相应计划 |
| D - 诊断 | 按需 | 解释已有工具日志或报告 | 获得限定结论 | 需修改工程或重新运行工具时转相应流程 |

## 5. 明确授权边界

本计划已获用户确认，授权以下操作：创建工程基座及其 Tcl；新增一个 RTL 文件和一个 XDC 文件；执行一次 B 构建并生成 bitstream。

不授权：JTAG 下载、Flash 擦写或配置、PHY/MDIO 操作、网络流量、ILA/VIO、改写其他板级配置。

## 6. 验收产物

- `EXECUTION.md`：实际文件、命令、构建与下载过程、偏差和停止原因；
- `ACCEPTANCE.md`：硬件路径、工程基座和 B 构建的验收结论；
- `HARDWARE_ENVIRONMENT.md`：若 LED 路径取得新证据，保留来源和变更记录；
- `LOG.md`：本工作包的计划、执行、验收状态。
