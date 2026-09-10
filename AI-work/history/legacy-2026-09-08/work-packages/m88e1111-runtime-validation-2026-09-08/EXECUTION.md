# 执行记录

状态：`COMPLETED — B14/A14 正确端点运行态验证通过`

> 修订（2026-09-08）：此前记录的 E13/E12 构建和 ILA 采集不连接 M88E1111 管理接口，硬件结论已作废。本轮只改正 XDC 管脚为 B14/A14，随后重新构建、易失下载并执行同一只读探针；用户已确认该操作。

用户于 2026-09-08 确认 `PLAN.md` 后，已仅在既有工程 `D:\MyFPGAProject\UDP\fpga\led\led.xpr` 执行获批的 S / B / H。没有创建或克隆工程。

## 实际工程改动

- 新增只读 Clause 22 主机：`mdio_clause22_reader.v`；只生成 read opcode `10`，没有写操作或写数据路径。
- 新增轮询探针：`m88e1111_runtime_probe.v`。按 `2,3,27,0,4,9,1,1` 的寄存器顺序，以地址 `0x07` 读取；MDC 为 1 MHz；两轮之间 100 ms 高阻/低 MDC 空闲，便于 ILA 重新触发。
- 顶层 `led_static.v` 保留 `led1=1`，MDIO IOBUF 始终只会驱动零或高阻；物理端点由 XDC 决定。
- 本轮将 XDC 的 MDC/MDIO 约束从 E13/E12 更正为 B14/A14，保持 `LVCMOS33`；不使用 Reset 或 INT。
- 新增自检 testbench 与 MDIO 行为从机；新增 `ila_mdio`（48 bits、16,384 depth）并登记至同一工程。

相关 source、仿真和构建证据见：

- `out/sim/SUMMARY.md`
- `out/build/SUMMARY.md`

## S — 仿真

已在 `sim_1` 中运行。`SIM_PASS` 在 `512435 ns` 完成，覆盖 Clause 22 preamble、读操作码、`TA=Z0`、开漏转向、数据采样以及 BMSR latch-low 双读。原生产物保留在 `D:\MyFPGAProject\UDP\fpga\led\led.sim\sim_1\behav\xsim\`。

## B — 构建

本轮只改变 XDC 引脚，既有 RTL 行为仿真不受影响，未重跑 S。`synth_1` 和 `impl_1` 已重跑，`Bitgen Completed Successfully`；IO 报告确认 `mdio=A14/BIDIR/LVCMOS33`、`mdc=B14/OUTPUT/LVCMOS33`；路由无 failed/unrouted nets，WNS `5.180 ns`、TNS `0`、WHS `0.061 ns`、THS `0`。使用的匹配 bit/LTX、哈希及原生报告路径记录在 `out/build/SUMMARY.md`。

## H — 易失下载与 ILA

实际目标为 `localhost:3121/xilinx_tcf/Digilent/E3077BAA4210` 上的 `xc7k325t_0`。已通过 JTAG 易失下载匹配的 bit/LTX，Hardware Manager 识别 `u_ila_mdio`，没有 Flash 操作。

先采集 MDIO 开漏自检与首帧：初始释放高、主动拉低、释放后 100/250/400 ns 均回高；随后 preamble 观测为 `OE=0, mdio_in=1`。寄存器 27 帧还显示 `TA=Z0`，所有读事务 `ta_error=0`。

在 PHY 地址 `0x07` 实际读到：PHYID1=`0x0141`、PHYID2=`0x0CC2`、reg27=`0x8484`（`[3:0]=0100`）、BMCR=`0x1140`、ANAR=`0x01E1`、1000BASE-T Control=`0x0300`、BMSR 双读均为 `0x796D`。BMSR 的 Link Status 和 Auto-Negotiation Complete 均为 1。

所有新的 `.ila`、CSV、逐 sample 解码、哈希与无写入边界记录在 `out/hardware/B14_A14_RUNTIME_ILA_DECODE.md`。旧 E13/E12 采集保留在 `out/hardware/MDIO_ILA_DECODE.md`，只作为错误端点的历史记录。

## 计划偏差与停止点

参数化 ILA 脚本的首次命令行调用在打开 Hardware Manager 前因参数位置错误退出，未连接/操作板卡，也未生成采集文件；修正 Vivado 参数顺序后继续执行。其余执行与修订计划一致：未写 PHY、未复位 PHY、未发包、未写 Flash。板卡当前保留 B14/A14 的易失只读探针镜像。
