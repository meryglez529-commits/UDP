# 协作日志

本日志按时间追加记录硬件环境建立及后续工作包的计划、执行、验收状态。状态含义：`READY_FOR_USER_ACCEPTANCE` 表示证据已具备，仍等待用户接受；它不表示已提交或已推送。

| 日期 | 工作项 | 阶段 | 记录 | 状态 |
|---|---|---|---|---|
| 2026-09-07 | Mode 4：硬件环境初始化 | 计划 | 按批准后的 Mode 4，仅建立 `AI-work/README.md`、`AI-work/LOG.md`、`AI-work/HARDWARE_ENVIRONMENT.md`；从输入原理图整理可复用硬件事实与 FPGA 一一映射。明确不创建 Vivado 工程、RTL、XDC、IP、bitstream，不进行 JTAG/MDIO/网络主动操作。 | APPROVED_BY_USER |
| 2026-09-07 | Mode 4：硬件环境初始化 | 执行 | 已建立三份基础记录；校验输入资料 SHA-256；从核心板原理图抽取并记录 401 个 FPGA 约束相关网络映射；将用户确认的 SGMII lane 3 跨板路径写入总环境。 | COMPLETED |
| 2026-09-07 | Mode 4：硬件环境初始化 | 验收 | 基础文件齐全；401 条映射已与核心板 PDF 抽取结果按数量、顺序核验一致；未产生 Vivado/RTL/XDC/IP/板级状态变化。用户已明确验收通过，允许提交并推送该初始化结果。 | ACCEPTED_BY_USER |
