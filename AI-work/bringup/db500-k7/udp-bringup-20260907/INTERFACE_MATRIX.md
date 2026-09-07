# 接口矩阵

| 接口 | 目的 | 必需 | 契约状态 | 最小 Demo | 验收证据 | 当前状态 |
|---|---|---:|---|---|---|---|
| JTAG 与配置 | 建立安全、可重复的 FPGA 镜像下载能力 | 是 | 部分确认 | configuration-safe | JTAG 目标身份、生成的 bitstream、安全板级行为 | PLANNED |
| 板级时钟与复位 | 提供确定性的逻辑启动条件 | 是 | 部分确认；MGT116 时钟对和 PHY RESETN 物理网络已见，频率与时序 BLOCKED | clock-reset | 审核后的 XDC、时序报告和复位观测 | PLANNED |
| SGMII PHY 链路 | 通过 GTX 将 M88E1111 接入以太网 MAC | 是 | BLOCKED：PHY 端 P/N 已见，但未找到 MGT116 lane、GT 端极性、参考频率、strap/MDIO 地址 | sgmii-link | 链路状态、MDIO 读回、SGMII/PCS 锁定 | PLANNED |
| ARP、IPv4、UDP | 提供可互通的数据报传输 | 是 | 部分确认：ARP 扩展发现、UDP 32000 和寄存器帧格式已确认；MAC/IP、UDP 校验策略 BLOCKED | udp-smoke | 主机 ARP 解析和经校验的 UDP 请求或回包抓包 | PLANNED |
| DB500 协议子集 | 安全验证自定义命令帧 | 是 | 部分确认：读写指令编号和大端字段已确认；安全可读寄存器集尚未单独批准 | db500-protocol | 设备信息和只读寄存器响应符合规范 | PLANNED |
| DDR3 | 未来缓存和采集数据通路 | 首版不需要 | 部分确认 | NOT_SELECTED | 明确排除在 UDP Smoke 范围外 | NOT_APPLICABLE |
| ADC/DAC AFE | 未来扫描和采集功能 | 首版不需要 | 部分确认 | NOT_SELECTED | 明确排除在 UDP Smoke 范围外 | NOT_APPLICABLE |

每项必需接口均已分配 Demo。首版未选择的接口既未被隐式验证，也不得被产品逻辑使用。
