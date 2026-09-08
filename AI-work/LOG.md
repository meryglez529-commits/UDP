# 协作日志

本日志按时间追加记录硬件环境建立及后续工作包的计划、执行、验收状态。状态含义：`READY_FOR_USER_ACCEPTANCE` 表示证据已具备，仍等待用户接受；它不表示已提交或已推送。

| 日期 | 工作项 | 阶段 | 记录 | 状态 |
|---|---|---|---|---|
| 2026-09-07 | Mode 4：硬件环境初始化 | 计划 | 按批准后的 Mode 4，仅建立 `AI-work/README.md`、`AI-work/LOG.md`、`AI-work/HARDWARE_ENVIRONMENT.md`；从输入原理图整理可复用硬件事实与 FPGA 一一映射。明确不创建 Vivado 工程、RTL、XDC、IP、bitstream，不进行 JTAG/MDIO/网络主动操作。 | APPROVED_BY_USER |
| 2026-09-07 | Mode 4：硬件环境初始化 | 执行 | 已建立三份基础记录；校验输入资料 SHA-256；从核心板原理图抽取并记录 401 个 FPGA 约束相关网络映射；将用户确认的 SGMII lane 3 跨板路径写入总环境。 | COMPLETED |
| 2026-09-07 | Mode 4：硬件环境初始化 | 验收 | 基础文件齐全；401 条映射已与核心板 PDF 抽取结果按数量、顺序核验一致；未产生 Vivado/RTL/XDC/IP/板级状态变化。用户已明确验收通过，允许提交并推送该初始化结果。 | ACCEPTED_BY_USER |
| 2026-09-07 | LED 下载验证 | 计划 | 已建立 `led-download-check-2026-09-07` 工作包；闭合 `LED1→J7.A36→HT3.A36→B150L230P→M17` 路径并同步总环境。等待用户确认计划中的工程创建、构建、被动 JTAG 枚举与易失下载操作。 | READY_FOR_USER_CONFIRMATION |
| 2026-09-07 | LED 下载验证 | 执行 | 用户已批准计划；只读 JTAG 枚举通过，目标为一个 Digilent 链路中的唯一 `xc7k325t`。因 Bank 15 VCCO/IOSTANDARD 未能从现有资料安全确认，按计划停止在生成 bitstream 之前。 | BLOCKED_ON_VCCO_CONFIRMATION |
| 2026-09-07 | LED 下载验证 | 执行调整 | 在用户改为“先完成硬件确认”前，Tcl 已创建最小工程并完成一次构建；未调用 JTAG 下载。该工程与 bitstream 仅保留为可审计遗留，不能作为本工作包验收依据；后续回到硬件确认阶段。 | HARDWARE_REVIEW_REQUIRED |
| 2026-09-07 | LED 下载验证 | 执行：构建与 bitstream | 用户完成硬件确认后，已将 Configuration Bank 0 的 `CFGBVS=VCCO` / `CONFIG_VOLTAGE=3.3` 纳入 XDC，重新以 Vivado 2021.1 构建。`impl_1=write_bitstream Complete!`，DRC 0 违规，bitstream 已生成；未调用任何下载、Flash、PHY 或网络命令。 | BUILD_PASS |
| 2026-09-07 | LED 下载验证 | 验收：构建 | 已记录 bitstream 身份、DRC 与静态无时钟设计的时序适用边界。用户明确规定本轮不下载，故工作包等待后续的明确下载授权和 LED1 目视验收；未提交或推送。 | BUILD_PASS_AWAITING_DOWNLOAD_AUTHORIZATION |
| 2026-09-07 | Mode 4：流程修订 | 计划与执行 | 用户指出硬件环境的端到端映射、工作包范围和 Tcl 工程策略存在问题；已修订 Mode 4 为“Bank 电源 + 单信号映射 + 功能路径”的取证流程，并明确禁止用 PDF 扁平文本、同页共现或其他工程 XDC 替代连接证据。 | COMPLETED |
| 2026-09-07 | Mode 4：硬件环境重建 | 执行 | 已视觉复核核心板第 2/4/5/6/10 页及 MCON 第 1/4/9 页；首版 401 条扁平映射废止，建立重建状态、Bank 表、已核对的配置/JTAG/QSPI/SGMII/连接器路径与待确认项。 | HARDWARE_ENVIRONMENT_REWORK_IN_PROGRESS |
| 2026-09-07 | LED 下载验证 | 验收修订 | 旧 `LED1→M17/B150L230P` 端到端结论无法由现有连接器资料证实，已撤销。本工作包的工程、bitstream 与构建记录保留审计，但禁止下载；待闭合 LED1 路径后重新计划。 | NOT_ACCEPTABLE_HARDWARE_MAPPING_SUPERSEDED |
| 2026-09-07 | LED 易失下载与板卡指示灯验证 v2 | 计划 | 按修订后的 Mode 4 和 S/B/H/D 流程建立新工作包。计划先创建 `fpga/udp/udp.xpr` 工程基座，再以可追溯证据闭合 LED1 路径；在此之前不写 LED XDC、不构建、不下载。待用户确认计划。 | WAITING_FOR_USER_CONFIRMATION |
| 2026-09-07 | LED 易失下载与板卡指示灯验证 v2 | 硬件事实更新 | 用户确认 LED1 端到端路径为 `J7.A36 → HT3.B36 → B150L20P → FPGA A18`；Bank 15 为 3.3 V、`LVCMOS33`，高电平点亮。已解除 LED XDC 的硬件事实阻塞；工作包仍等待计划执行确认。 | HARDWARE_READY_WAITING_FOR_PLAN_CONFIRMATION |
| 2026-09-07 | LED 易失下载与板卡指示灯验证 v2 | 计划确认 | 用户将本工作包终点限定为 bitstream 构建完成；明确不进行下载。授权创建工程基座、LED RTL/XDC 和 B 构建；H 流程不执行。 | APPROVED_FOR_EXECUTION |
| 2026-09-07 | LED 易失下载与板卡指示灯验证 v2 | 工程边界更新 | 用户通过 Vivado GUI 创建 `fpga/led/led.xpr`，并指定直接在此工程开发。已确认器件为 `xc7k325tffg676-2`、Vivado 为 2021.1；不创建或使用其他工程。 | IN_PROGRESS |
| 2026-09-07 | LED 易失下载与板卡指示灯验证 v2 | 执行与验收 | 在 `led.xpr` 中登记静态高电平 LED RTL 与 A18/Bank15 `LVCMOS33` XDC；B 构建通过，`impl_1=write_bitstream Complete!`、DRC 0 违规，bitstream SHA-256 已记录。按用户范围未执行下载；验收结论为 PASS，等待用户接受后提交/推送。 | PASS_AWAITING_USER_ACCEPTANCE |
| 2026-09-08 | LED 静态逻辑仿真与 ILA 调试 | 计划 | 用户请求 S 仿真和 ILA。已建立独立工作包；ILA 前先闭合 AA3/Bank34 `sys_clk_i` 100 MHz 时钟事实，随后才允许 ILA IP、debug bit/LTX、一次易失下载和立即触发采集。待用户确认计划。 | WAITING_FOR_USER_CONFIRMATION |
| 2026-09-08 | LED 静态逻辑仿真与 ILA 调试 | 计划确认与硬件事实 | 用户要求执行，并以原理图截图确认 `IC2（100 MHz）→sys_clk_i→AA3`，其中 AA3 为 `IO_L12P_T1_MRCC_34`；Bank 34 为 1.5 V、`LVCMOS15`。工作包进入执行；尚未下载或打开 Hardware Manager。 | APPROVED_FOR_EXECUTION |
