# 验收记录

状态：`PASS — B14/A14 正确端点的 MDIO 运行态验证；待用户确认验收`

## 验收对照

| 等级 | 计划要求 | 实际证据 | 结论 |
|---|---|---|---|
| S | Clause 22 读帧、`TA=Z0`、三态、BMSR 双读的行为仿真 | 既有 XSim `SIM_PASS`；本轮未改 RTL、IP 或 testbench。 | PASS（逻辑） |
| B | 工程可构建，B14/A14 约束、DRC/时序及匹配 debug 镜像有效 | IO 报告：A14 BIDIR / B14 OUTPUT，均为 `LVCMOS33`；WNS 5.180 ns、TNS 0、WHS 0.061 ns、THS 0；bitgen 成功。 | PASS |
| A. 管理可达 | 地址 0x07 读到有效 PHY ID；MDIO 有正确 release/turnaround | PHY ID=`0x0141_0CC2`；A14 释放后 100/250/400 ns 均高；preamble 高，`TA=Z0`，`ta_error=0`。 | PASS |
| B. 模式正确 | reg 27 `[3:0]=0100` | reg27=`0x8484`，低四位=`0100`。 | PASS |
| C. 自协商配置正确 | BMCR 的 AN enable=1，记录 ANAR/R9 | BMCR=`0x1140`，AN enable=1；ANAR=`0x01E1`；R9=`0x0300`。 | PASS |
| D. 铜口链路/协商完成 | BMSR 双读后 Link=1、AN complete=1 | BMSR 两次均=`0x796D`；bit2 Link=1，bit5 AN Complete=1。 | PASS（采集时刻） |

## 验收结论

原理图和 Marvell 手册得出的启动绑带结论已经得到正确端点的运行态读回确认：地址 `0x07` 有效响应，reg27=`0x8484` 的 `[3:0]=0100`，即 `HWCFG_MODE=0100`（SGMII without clock + SGMII AN to copper）；BMCR/ANAR/R9 和 BMSR 双读也证明自协商已启用且采集时刻链路已完成协商。完整证据见 `out/hardware/B14_A14_RUNTIME_ILA_DECODE.md`。

旧 E13/E12 结果已作废，不再作为 PHY 故障判断。此次未验证 SGMII 数据帧或 UDP，且没有写 PHY、复位 PHY、发包或写 Flash；后续 UDP 工作包仍需实现 FPGA GT/SGMII、MAC、协议栈和端到端报文验证。

用户接受本次结果前，不提交或推送任何工程改动。
