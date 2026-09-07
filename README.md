# DB500 UDP FPGA Bring-up

本仓库用于建立 DB500 扫描控制平台的可复现 FPGA bring-up 流程。首个交付目标是安全的 UDP 通信 Demo：设备发现、只读状态查询，以及可验证的 UDP 回包链路。

仓库分为两个职责根目录：

- fpga/：存放可构建的 FPGA RTL、约束、IP 配置、仿真与 Tcl。
- AI-work/：存放每个阶段的计划、执行记录、验收证据和交接资料，是项目的审计记录。

原始原理图和通信协议文件保留在仓库根目录。通信协议 Word 文档当前被其他程序占用，已登记为输入资料，待释放文件锁后再纳入 Git。

当前板卡状态见 AI-work/bringup/db500-k7/udp-bringup-20260907/STATUS.md。
