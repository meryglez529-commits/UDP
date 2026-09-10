# LED 下载验证 - 执行记录

状态：`SUPERSEDED_BY_HARDWARE_ENVIRONMENT_REWORK`

历史执行曾完成只读 JTAG 枚举和一次 bitstream 构建；从未调用 `program_hw_devices`，从未下载、写 Flash、写 PHY 或发送网络报文。

该构建使用的 `M17/LVCMOS33` LED 约束来自已经撤销的端到端 LED 映射。保留日志、工程和 bitstream 仅供审计，不得重新构建、下载或用于验收，直到新的、经用户确认的 LED 计划以重建后的硬件环境为依据。

只读 JTAG 枚举事实仍单独有效：2026-09-07 的日志记录一个 Digilent 目标和唯一 `xc7k325t_0`；它仅表明当时可枚举到器件，并不证明 LED 路径或下载结果。
