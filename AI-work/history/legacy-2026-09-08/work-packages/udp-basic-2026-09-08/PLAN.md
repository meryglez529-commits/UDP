# DB500 板卡最小 UDP 通信 - 方案与执行计划

状态：`READY_FOR_USER_CONFIRMATION`

## 1. 目标

在既有 Vivado 工程 `D:\MyFPGAProject\UDP\fpga\led\led.xpr` 中实现一条可验证的千兆以太网 UDP 通信链路。首版仅支持：

1. 对静态配置的设备 IPv4 地址应答标准 ARP 请求；
2. 在 UDP 32000 端口接收并发送 DB500 V1.4 的寄存器控制帧；
3. 只读版本寄存器 `0x000A`；
4. 读写心跳寄存器 `0x000D`，写入值由随后的读取请求返回；
5. 保留 LED1 常亮，作为已验证的 FPGA 配置与基础可观测性指示。

本工作包的完成定义是：目标主机从板卡收到正确 ARP 应答，并经 UDP 32000 成功读取版本、写入并读回心跳值。它不是扫描控制、ADC 采集、图像传输、远程升级或 Flash 固化的交付。

## 2. 范围与安全边界

### 纳入范围

- MGT116 lane 3 与 M88E1111 PHY 之间的 SGMII 链路；
- Xilinx 官方 SGMII/PCS-PMA 与以太网 MAC IP 的 Vivado 2021.1 配置；
- 轻量硬件 ARP、IPv4 和 UDP 收发逻辑；
- 静态 MAC、IPv4、子网掩码和版本字段参数；这些值在实施前由用户确认，不猜测默认地址；
- DB500 控制帧的 `WRITE (0x0001)`、`READ (0x0002)` 和 `READ_RESPONSE (0x0003)` 最小子集；
- 自检仿真、实现/时序/DRC、一次易失 JTAG 下载、主机定向 UDP 冒烟测试，以及仅在需要时的 ILA 采集。

### 明确不纳入范围

- 扫描、ADC/DAC、束闸、图形、RTM、图像装载、波形和远程升级协议；
- 文档中有冲突定义的 `0x000F`，以及未经实际固件证实的其他写寄存器；
- 从网络修改设备 IP、MAC 或 PHY 配置；
- Flash 擦写/固化、未定向的网络抓包、对无关主机发送流量；
- MicroBlaze、操作系统、TCP、DHCP、IPv6、IP 分片和大数据流。

## 3. 已确认的硬件与协议事实

| 项目 | 事实 | 来源 | 可用性 |
|---|---|---|---|
| Vivado 工程 | `D:\MyFPGAProject\UDP\fpga\led\led.xpr`，器件 `xc7k325tffg676-2`，Vivado 2021.1 | 既有 LED 工作包 | 本工作包唯一工程上下文 |
| FPGA 到 PHY TX | A3/A4，MGT116 lane 3 TX，接至 M88E1111 `S_IN-/S_IN+` | `HARDWARE_ENVIRONMENT.md`，SRC-001/002/005 | 已确认 |
| PHY 到 FPGA RX | B5/B6，MGT116 lane 3 RX，来自 M88E1111 `S_OUT-/S_OUT+` | `HARDWARE_ENVIRONMENT.md`，SRC-001/002/005 | 已确认 |
| GT 参考时钟管脚 | D5/D6，`MGTREFCLK0N/P_116` | `HARDWARE_ENVIRONMENT.md`，SRC-001/002 | 管脚已知，来源与频率未确认 |
| LED 保留 | A18、Bank 15、`LVCMOS33`，输出高电平点亮 | `HARDWARE_ENVIRONMENT.md` | 已确认 |
| 控制 UDP | 双向端口 32000；大端；`5555 AAAA` 帧头 | `DB500千兆网版通讯协议V1.4_20250113.docx`，2.2--2.3 | 文档级 |
| 最小控制帧 | WRITE=`0001/0006/14 B`；READ=`0002/0002/10 B`；READ_RESPONSE=`0003/0006/14 B` | 同上 | 文档级 |
| 最小寄存器 | `0x000A` 版本只读；`0x000D` 心跳读写 | 同上，附录 1 | 文档级 |
| ARP 发现 | 文档描述 ARP 发现与 `SGSC2450` 设备名 | 同上，2.1 | 文档级；首版先实现标准 ARP 应答 |

协议文档的附录 1 同时将 `0x000F` 解释为“下降沿时间”和“DAC 输出使能”，因此本计划绝不使用该地址。文档以外的寄存器意义、远程 IP 设置扩展和设备发现扩展均不作为首版依据。

## 4. 实施前必须闭合的硬件事实

下列事实尚未具备，不能凭经验配置 GT IP、约束或 PHY 初始化。它们是进入实施的前置条件，而不是可由 RTL 猜测补足的参数。

| 编号 | 待确认事实 | 为什么阻塞 | 最小证据 |
|---|---|---|---|
| OQ-004a | M88E1111 为 SGMII 提供的 GT REFCLK 频率、源头、抖动要求和工作速率 | 决定 PCS/PMA/SGMII IP 的参考时钟与 QPLL/CPLL 配置 | MCON 第 8 页、PHY 数据手册和实际 strap 说明 |
| OQ-004b | PHY 的 SGMII strap/自协商配置以及上电后的预期链路模式 | 决定 FPGA 侧 SGMII 配置与 link-up 判据 | M88E1111 strap 原理图/BOM/实测 MDIO 寄存器 |
| OQ-005 | PHY 的 MDC、MDIO、RESET、INT 信号是否接至 FPGA；若接入，其引脚、Bank 电压、极性和复位时序 | 决定是否由 FPGA 执行复位/MDIO 初始化，避免错误驱动 PHY | MCON J6、AFE 跨板资料、PHY 数据手册 |
| CFG-001 | 板卡 MAC、IPv4、子网掩码、目标主机 IPv4/MAC 与连线拓扑 | 不得擅自选择或占用网络地址 | 用户确认的隔离测试网参数 |

若证据表明 PHY 已由硬件 strap 正确复位并工作在 SGMII 模式，OQ-005 可从首版 RTL 中排除；该结论仍须记录证据。若需要 FPGA 控制 PHY，则复位和 MDIO 将纳入设计、约束、仿真与验收。

## 5. 推荐架构

采用纯硬件的最小协议栈，不引入 MicroBlaze。网络协议功能与 LED 逻辑解耦，避免 100 MHz `sys_clk_i` 被误当作 GT 参考时钟。

```text
M88E1111 RJ45 PHY
        │ SGMII（MGT116 lane 3）
        ▼
Xilinx SGMII / PCS-PMA IP  ← 已核对的 GT REFCLK
        │ GMII
        ▼
Xilinx Ethernet MAC IP
        │ AXI-Stream 或等价流接口
        ▼
ethernet_rx_tx ── arp_ipv4_udp_min ── db500_control_min
                                      ├─ version 0x000A（只读常量）
                                      └─ heartbeat 0x000D（读写寄存器）
        │
        └─ 只对 ARP、IPv4/UDP:32000 的合法最小报文生成应答

led_static（保留为可回退的已验证 top）
udp_min_top（本工作包通过后成为新的工程 top，继续驱动 LED1）
```

### 接收与发送规则

- MAC 负责以太网 CRC；逻辑检查目标 MAC、EtherType、IPv4 头长/总长度/校验和、UDP 长度与目标端口。
- 仅接收发往静态设备 IPv4/MAC 的 ARP 和非分片 IPv4/UDP 报文；UDP 校验和为 0 时按 IPv4 规范接受，非 0 时首版验证。
- 对不符合长度、帧头、命令、寄存器或校验要求的报文静默丢弃，不改变心跳值，不产生回包。
- `READ 0x000A` 返回已确认的构建版本常量；`WRITE 0x000D` 仅更新心跳寄存器；`READ 0x000D` 返回该寄存器。其他访问返回空响应或错误响应的行为，在仿真前固定为一个明确实现并记录。
- 所有控制字段采用网络字节序（MSB 在前）。`Length` 必须同时符合控制协议的声明值和 UDP 实际有效载荷长度。
- 网络逻辑运行在 MAC/PCS 输出的以太网时钟域；若 LED/状态需要跨域观察，使用明确同步器，不把 AA3 的 100 MHz 时钟用于 GT。

## 6. 拟修改的工程输入

只有在本计划获确认且第 4 节事实闭合后才进行下列修改；所有文件注册到既有 `led.xpr`，不创建、克隆或迁移到另一份 Vivado 工程。

| 类别 | 拟新增/修改项 | 用途 |
|---|---|---|
| RTL | `udp_min_top.v`、`arp_ipv4_udp_min.v`、`db500_control_min.v`、必要的帧/CRC/校验辅助模块 | 最小 ARP/IPv4/UDP 与控制寄存器逻辑 |
| RTL | `led_static.v` 保持不改；新 top 继续输出 `led1=1` | 保留已验证回退设计与板卡指示 |
| IP | SGMII/PCS-PMA、Ethernet MAC；仅在硬件事实闭合后由 Vivado 2021.1 创建并登记 | SGMII、MAC 与时钟/复位接口 |
| IP（调试） | 可选 `ila_udp`，采样 link、RX/TX valid、帧类型、端口、控制命中和错误原因 | 仅在计划批准的硬件验证中使用 |
| XDC | SGMII TX/RX、GT REFCLK、复位/MDIO（如证实需要）以及各自时钟约束 | 仅使用已闭合的管脚、电平、频率和极性 |
| 仿真 | MAC 流接口或等价封装层的自检 testbench、协议报文向量 | 可重复的功能证据 |
| Tcl | 更新现有 `scripts/sources.tcl`；仅在重复/易错的 IP 创建或构建步骤需要时新增最小 Tcl | 维护单一工程输入清单 |
| 主机测试 | 定向 UDP 冒烟测试脚本与受控报文向量 | 对目标 IP/32000 执行 ARP、版本、心跳验证 |

## 7. 流程与执行顺序

### P0 硬件闭合（D）

1. 视觉核对 MCON/AFE/PHY 资料，闭合 OQ-004、OQ-005；把可用结论、精确页码和状态更新到 `HARDWARE_ENVIRONMENT.md`。
2. 由用户确认隔离测试网参数 CFG-001。
3. 若任一 GT/PHY 事实仍未知，停止在计划阶段，不创建 IP、不编写 XDC、不连接网络。

### P1 设计与仿真（S）

1. 在既有工程中创建经确认的 IP 和最小 RTL，保留 `led_static` 作为回退。
2. 使用 `sim_1` 对协议逻辑做自检：ARP 请求/应答；版本读取；心跳写读；错误帧头、错误长度、错误端口、非目标 IP、非法寄存器、UDP 截断和字节序检查。
3. 仿真原生产物留在 `D:\MyFPGAProject\UDP\fpga\led\led.sim\`；文本结论写入本工作包 `out/sim/`。

### P2 构建（B）

1. 检查 `synth_1`、`impl_1` 未运行；不抢占现有 run。
2. 使用 `led.xpr` 的 `synth_1` / `impl_1` 完成综合、实现、时序与 DRC；原生产物保留在 `D:\MyFPGAProject\UDP\fpga\led\led.runs\`。
3. 仅在所有设计输入已获批准后生成 bitstream；如使用 ILA，匹配同一次实现的 `.bit` 与 `.ltx`。

### P3 板级验证（H）

1. 在获用户确认后，向唯一已枚举的 `xc7k325t_0` 执行一次易失 JTAG 下载；不写 Flash。
2. 将主机与用户确认的隔离网络连接，只向确认的板卡 IP 和 UDP 32000 发送 ARP/测试报文。
3. 依次验证 PCS/PHY link-up、ARP、版本读取、心跳写读；失败时先用同一实现的 ILA/受限抓包定位，不发送扫描或配置类命令。

## 8. 验收标准

| 层级 | 通过条件 | 证据 |
|---|---|---|
| 硬件事实 | OQ-004、OQ-005、CFG-001 均有可追溯结论，或明确记录 OQ-005 不需要 FPGA 控制 | 更新后的硬件环境记录与来源页 |
| S 仿真 | 所有第 7 节 P1 场景自检通过；合法响应的全部字节、长度和大端字段符合固定向量 | 仿真日志、波形与 `SIM_PASS` |
| B 构建 | `impl_1` 完成；无 Error/Critical Warning DRC；相关时钟无未满足时序 | Vivado 原生报告、bitstream、匹配 LTX（如有） |
| H 链路 | PCS/PHY 进入预期 link-up 状态；无法仅由下载成功代替 | ILA 或经确认的状态观测 |
| H 协议 | 主机收到 ARP 应答；`READ 0x000A` 回复正确版本；`WRITE 0x000D=V` 后 `READ 0x000D` 回复同一 V | 定向测试记录和原始报文证据 |
| 安全边界 | 未写 Flash；未发送扫描、ADC、升级或未授权网络报文；无非目标流量进入报告 | 执行记录与抓包范围 |

## 9. 板级操作授权点

本方案尚未授权任何 RTL、XDC、IP、工程设置、综合、下载、PHY/MDIO 或网络流量变更。用户确认本计划后，授权范围仅限第 7 节所列的 P0--P3；其中 P3 的易失下载、定向 UDP 发送和可选 ILA 采集仍以本计划的成功硬件闭合为前提。Flash 写入始终不在本工作包范围内。
