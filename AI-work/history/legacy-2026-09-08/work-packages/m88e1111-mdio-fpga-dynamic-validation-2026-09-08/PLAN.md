# M88E1111 无示波器 MDIO 动态验证计划

日期：2026-09-08
状态：`APPROVED — 用户已明确要求执行`

## 目标

在不依赖示波器、且将板级静态链路视为已确认的前提下，以 FPGA ILA 验证：

1. FPGA E12 在 MDIO 空闲高阻期实际判为高；
2. 现有 Clause 22 preamble 的每一个高阻采样点实际判为高，且 MDC 周期为 1 µs；
3. 若上述证据仍矛盾，通过 MDC 恒低的 FPGA 开漏自检验证 E12 的“释放高—驱动低—释放后回高”闭环；
4. 自检通过后，再判读 M88E1111 地址 0x07 的只读 Clause 22 响应。

## 范围与边界

- 唯一工程：`D:\MyFPGAProject\UDP\fpga\led\led.xpr`。
- 初始 H 阶段复用当前已实现的 `u_ila_mdio`（48-bit，16,384 depth）。若现场 FPGA 已加载同版调试镜像，则不重新下载；若未暴露该核，则按用户此前及本次授权，以 JTAG **易失**下载工程现有、已验证的只读调试 `.bit` 和匹配 `.ltx`。两种情形均不修改 RTL、不写 PHY、不驱动 PHY reset、不写 Flash。
- 若现有 ILA 重现“空闲高、preamble 低”的矛盾，才修改本工程已登记 RTL，添加自检状态；自检期间 MDC 恒低，MDIO 仅按开漏方式驱动低或高阻，因而不构成 Clause 22 帧或 PHY 写入。
- RTL 变更后使用本工程 `synth_1` / `impl_1` 重建，并只通过 JTAG 易失下载同一次实现产生且相配的 `.bit` / `.ltx`；不写 Flash。
- 不发送 UDP/以太网包，不改变 M88E1111 寄存器。

## 已知硬件事实

| 项目 | 事实 | 依据 |
|---|---|---|
| FPGA MDIO | E12，Bank 16，`LVCMOS33`，经 CORE HT2 / MCON J6.B55 至 U82.B2 | `AI-work/history/legacy-2026-09-08/HARDWARE_ENVIRONMENT-legacy.md` |
| FPGA MDC | E13，Bank 16，`LVCMOS33`，经 MCON J6.B54 至 U82.B1 | 同上 |
| 管理侧 | U82 A2=`PHY_MDIO_L`，R374 将其以 4.7 kΩ 上拉至 `VCC2V5`；U82 OE 经 R385 上拉至 `VCC2V5` | MCON 原理图第 9 页；已有诊断 |
| 静态实测 | 用户报告 A2、B2 为高，OE≈2.4 V | 同上工作包已有诊断 |
| PHY 预期地址 | 0x07 | M88E1111 strap 追溯记录 |

## 执行步骤

### H1：不改设计的 ILA 空闲态采集

- 目标：`localhost:3121/xilinx_tcf/Digilent/E3077BAA4210`，设备 `xc7k325t_0`。
- ILA：`u_ila_mdio` / `mdio_debug[47:0]`。
- 使用 `sequence_done=1` 触发，记录 16,384 个 100 MHz sample。
- 通过条件：`reader_busy=0`、`mdc=0`、`mdio_drive_low=0` 时，`mdio_in=1`。

### H2：不改设计的 preamble 采集

- 触发：`reader_phase=PHASE_PREAMBLE`、`MDC=1`；保留足够 pre-trigger 以看到整个帧前段。
- 通过条件：32 个 preamble 上升沿均为 `mdio_drive_low=0`、`mdio_in=1`；相邻 MDC 上升沿相隔 100 个 ILA sample（1 µs）。

### B/H3：条件式开漏自检

仅当 H1/H2 结果矛盾时实施：

- 增加有限状态自检：MDC 保持 0；高阻 10 µs、开漏低 10 µs、再次高阻；在释放后 100、250、400 ns 记录 E12 输入和首次逻辑高延迟。
- 对修改执行现有 `synth_1`、`impl_1` 与 bitstream；检查 DRC error=0、时序不劣于要求。
- 易失下载新镜像，使用匹配 LTX 采集自检结果。
- 通过条件：释放期读高、驱动期读低、再次释放后最迟 400 ns 读高；MDC 在整个自检阶段保持低。

### H4：Clause 22 只读复验

- 自检通过或 H1/H2 已直接通过时，复采地址 0x07 的 PHYID1、PHYID2、reg27、BMCR、ANAR、1000BASE-T control 与 BMSR 双读。
- 接受有效 TA 和稳定、可按数据手册解释的读值；`0x0000` 或 `0xFFFF` 连同 TA/线路状态只作为无效响应证据，不解释为寄存器配置。

## 原生产物与验收

- 新 ILA 原始 `.ila` / `.csv` 留在 `D:\MyFPGAProject\UDP\fpga\led\led.hw\hw_1\`，使用不覆盖历史数据的唯一文件名。
- 若发生构建，原生产物留在 `D:\MyFPGAProject\UDP\fpga\led\led.runs\`。
- 本工作包 `EXECUTION.md`、`ACCEPTANCE.md` 与 `out/` 仅保留路径、命令、哈希、解码和结论。
