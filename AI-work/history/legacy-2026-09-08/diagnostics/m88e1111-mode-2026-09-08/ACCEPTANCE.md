# 诊断结论与验收

## 已证实

- `HWCFG_MODE=0100`。Table 35 将其定义为 **SGMII without clock with SGMII Auto-Negotiation to copper**。
- `ANEG=1110`。Table 35 将其定义为铜口 Auto-Negotiation、通告全部能力、preferred master。
- PHY 地址为 `0x07`，`CONFIG[6]=010` 选择 MDC/MDIO 管理接口，`INTn` 为低有效。
- `S_IN+/-`、`S_OUT+/-` 接到 FPGA MGT，`S_CLK+/-` 未接；这与 `0100` 的 SGMII without clock 模式一致。

## 结论边界

原理图绑带结论现已由正确端点的上电运行态只读 MDIO 验证：地址 `0x07` 返回有效 PHY ID，Register 27 读为 `0x8484`、其 `[3:0]=0100`；BMCR 自协商使能为 1，BMSR 双读均显示 Link=1 和 Auto-Negotiation Complete=1。证据见 `AI-work/history/legacy-2026-09-08/work-packages/m88e1111-runtime-validation-2026-09-08/out/hardware/B14_A14_RUNTIME_ILA_DECODE.md`。此前的 `HWCFG_MODE=0110` 记录已因 `CONFIG[4]` 连线错读而作废；此前 E13/E12 的 `0x0000` 采集也因错误端点而作废。

## 最小下一步

后续 UDP 工作包不需要重复 PHY 初始模式确认；可以把已确认的 M88E1111 状态作为前提，聚焦 FPGA GTX/SGMII、MAC 和协议实现。若将来需要主动改变 PHY 模式、协商参数或复位，必须另行制定并确认包含写寄存器/复位的计划。
