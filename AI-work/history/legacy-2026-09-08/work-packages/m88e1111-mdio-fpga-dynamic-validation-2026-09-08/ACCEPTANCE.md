# 验收记录

日期：2026-09-08
状态：`FAIL — MDIO 动态释放未通过；未解释 PHY 寄存器读值`

| 验收项 | 结果 | 证据 |
|---|---|---|
| H1：空闲高阻 E12 判高 | PASS | `out/hardware/MDIO_DYNAMIC_ILA_DECODE.md` 第 2 节 |
| H2：初始 preamble 释放高、1 MHz MDC | PASS（仅首帧） | 同第 3 节 |
| H3：驱动低后 400 ns 内释放回高，且 MDC 恒低 | FAIL | 同第 4 节；100/250/400 ns 全为低 |
| H4：自检后首帧 Clause 22 可判读 | FAIL | 同第 5 节；32 个 preamble 上升沿均低 |
| 行为仿真 | PASS | `out/sim/SUMMARY.md` |
| 实现、时序与 DRC | PASS | `out/build/SUMMARY.md` |

结论：FPGA IOBUF 控制已请求高阻释放，但实际 E12 输入未在需要的时间内恢复逻辑高。当前不具备可信的 M88E1111 寄存器运行态读回条件；未执行任何 PHY 写、reset 或 Flash 写。
