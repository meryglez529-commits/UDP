# UDP 固定上位机传输模块

状态：`CONTROL_DATA_JUMBO_HARDWARE_PASS`

设计进展（2026-09-17）：DATA 双通道与 Jumbo 扩展已完成 RTL、实现和实板验收。
标准 MTU 单端口模块仍保留作回归；当前 `udp_top` 使用双端口 transport。通信仅在协商为
1G 全双工时开放，10/100M 不进入数据面就绪状态。

## 1. 目标、验收语义与边界

本设计为 DB500 板提供一个面向**唯一固定上位机**的千兆以太网 UDP 传输层。它接收、校验、
完整保存来自该主机的 UDP 载荷，并通过通用消息接口将完整报文交给未来的业务逻辑；反方向，
它将业务逻辑给出的完整载荷封装成 UDP/IP/Ethernet 帧并发送给同一主机。

首版不解释 UDP 载荷中的任何字节，不包含 DB500 命令、寄存器、帧头、版本号或应答语义。这些
属于未来独立的业务模块，不能反向影响本模块的协议解析和缓冲策略。

### 1.1 “稳定可靠”的准确含义

UDP/IP 没有确认、重传、顺序或端到端送达保证，因此本模块不能承诺网络意义上的可靠传输。首版
的可靠性承诺限于 FPGA 本地：

- 只向业务侧交付通过链路、IPv4、UDP 和固定端点检查的**完整**数据报，绝不交付半帧。
- IPv4 UDP 数据报必须携带非零且正确的 UDP checksum；checksum 为零的报文即使在 IPv4
  标准中允许，也按本项目的固定上位机策略整帧丢弃。
- 在已分配的缓冲空间内，载荷字节序和长度原样保存；不会因业务侧暂时未读取而覆盖未消费报文。
- 缓冲满、格式错误、地址不匹配、长度错误和校验失败均整帧丢弃，且分别计数；不静默丢失。
- 发送侧只在收到完整的业务报文后才发送 Ethernet 帧；业务输入中断或长度不匹配不会产生半帧。

如果将来业务需要请求确认、序列号、重传或幂等性，应由业务协议层实现，而非修改 UDP 传输层。

### 1.2 明确不包含的功能

- DHCP、DNS、TCP、IPv6、VLAN、IP 分片/重组、IGMP、广播 UDP、多上位机和运行时地址学习。
- 从 UDP 载荷提取任何命令、校验、寄存器地址或响应格式。
- 报文跨 FPGA 复位的持久保存。
- 利用 MDIO 主动复位或重配 PHY；若确有需要，先扩展 M88E1111 模块设计。

## 2. 已确认的系统输入

| 项目 | 当前设计输入 |
|---|---|
| FPGA | Kintex-7 `xc7k325tffg676-2`，Vivado 2021.1 |
| PHY | M88E1111；`HWCFG_MODE=0100`（SGMII without clock），铜口自协商 `ANEG=1110` |
| SGMII 串行通道 | MGT116 lane 3；FPGA TX `A3/A4`，RX `B5/B6`；器件资源为 `GTXE2_CHANNEL_X0Y7` |
| GTX 参考时钟 | `D5/D6` (`MGTREFCLK0_P/N`)；U65 AD9517 OUT0 经 SN65LVDS100 输出的 125 MHz，已外部验收；位于 `GTXE2_COMMON_X0Y1` 所在 common tile |
| 管理时钟 | `AA3` 100 MHz；`udp_top` 统一 `IBUF+BUFG` 后送入 AD9517 控制器和 `ethernet_link_top`，后者的 `No_buffer` Clocking Wizard 生成带全局缓冲的 200 MHz independent clock，不作为 GTX REFCLK |
| 以太网 IP | 两个独立 AMD/Xilinx 官方 IP：`gig_ethernet_pcs_pma` 和 `tri_mode_ethernet_mac`；不采用 AXI Ethernet Subsystem |
| 链路速率 | 仅开放 1G 全双工，10/100 Mb/s 不开放通信；保留 M88E1111 铜口与 SGMII 自动协商 |
| 固定数据面时钟 | PCS/PMA 的 125 MHz `userclk2` 送给 TEMAC `gtx_clk`，并作为 Ethernet FIFO 用户侧与 UDP 传输层时钟；TEMAC MAC client 低速时钟由 IP 内部管理 |
| 以太网 MTU | CONTROL 最大 payload1472；DATA 已实现并实板验证 MTU9000/payload8972，覆盖原工程默认8172；继续不支持 IPv4 分片/重组 |

两个 Ethernet IP 的 Vivado 2021.1 能力、官方 example design、接口与集成注意事项见
[`ETHERNET_IP_RESEARCH.md`](ETHERNET_IP_RESEARCH.md)。该调研记录不替代本文件中的最终设计；
IP 参数确认后，批准的配置应收敛回本文件。

AD9517 配置、校准和锁定语义由 [`../ad9517/MODULE.md`](../ad9517/MODULE.md) 独立维护。
`ad9517_clock_manager` 已导出 `clock_ready_o`、`pll_locked_o`、`init_error_o` 和
`error_code_o`，并由 `udp_top` 直接例化复用；组合顶层没有复制 AD9517 初始化逻辑。

## 3. 固定端点配置

唯一上位机不表示在 RTL 内硬编码猜测的地址。首版假定 FPGA 与上位机位于同一个二层网段，
不经过网关。以下值在首次 RTL/IP 集成前由用户提供，并作为 `udp_top` 的综合期参数集中定义；
运行时不修改，也不从 ARP 动态学习。

| 参数 | 含义 | 当前值 |
|---|---|---|
| `LOCAL_MAC` | FPGA MAC 地址 | `48'h02_DB_50_00_00_01`（本地管理的单播地址） |
| `LOCAL_IPV4` | FPGA IPv4 地址 | `192.168.1.20` / `32'hC0A8_0114` |
| `HOST_MAC` | 唯一上位机 MAC 地址 | `9C-69-D3-1A-4C-6D` / `48'h9C69_D31A_4C6D` |
| `HOST_IPV4` | 唯一上位机 IPv4 地址 | `192.168.1.10` / `32'hC0A8_010A` |
| `LOCAL_UDP_PORT` | FPGA 接收 UDP 端口 | `32000` / `16'h7D00` |
| `HOST_UDP_PORT` | 上位机接收 UDP 端口 | `32000` / `16'h7D00` |

接收 UDP 仅接受 `dst_mac=LOCAL_MAC`、`dst_ip=LOCAL_IPV4`、`dst_port=LOCAL_UDP_PORT` 且
`src_mac=HOST_MAC`、`src_ip=HOST_IPV4` 的单播帧。ARP 只回答上位机发往 `LOCAL_IPV4` 的请求；
发送 UDP 与 ARP 应答均使用已配置的 `HOST_MAC`，不发送 ARP 请求，也不维护 ARP 表。

## 4. 模块结构与时钟域

```text
AA3 100 MHz ──> udp_top IBUF+BUFG
                         ├──> AD9517 控制 ── clock_ready_o ──┐
                         └──> Clocking Wizard (No_buffer)   │
                                      └── 200 MHz + locked ─┤
                                                            ▼
已验收 AD9517 OUT0 125 MHz ──> GTX REFCLK ──> gig_ethernet_pcs_pma
                                                        ▲        │ GMII
M88E1111 <──────────────────── SGMII ────────────────────┘        ▼
                                                 tri_mode_ethernet_mac
                                                   ▲          │
                                                   └─ speed ──> link_speed_ctrl
                                                              │ MAC client AXI4-Stream
                                                              ▼
                                                   RX/TX Ethernet FIFO
                                                              │ AXI4-Stream, 125 MHz
                                                              ▼
                                                udp_transport_dual_host
                                                 ├─ 共享 ARP / IPv4 / UDP parser
                                                 ├─ CONTROL RX4/TX2 槽环
                                                 ├─ DATA RX/TX 32 KiB 字节环
                                                 └─ 共享帧级仲裁 / 统计
                                                              │
                                                              ├── 当前 RTL 边界
                                                              ▼
                                               未来业务模块（载荷透明）
```

`gig_ethernet_pcs_pma` 与 `tri_mode_ethernet_mac` 之间采用标准 GMII、`sgmii_clk_en` 和 speed
反馈连接；链路控制器根据 PCS/PMA 的 SGMII auto-negotiation 状态更新 TEMAC RX/TX speed，
再把 TEMAC 的速度指示反馈给 PCS/PMA。TEMAC MAC client 接口先经过官方结构的 RX/TX Ethernet
FIFO，再以固定 125 MHz、8-bit AXI4-Stream 接到 `udp_transport_dual_host`。该 FIFO 负责吸收
TEMAC RX 无 `tready`、过滤坏帧并隔离 tri-speed MAC client 时钟；它不替代 UDP 完整消息槽位。

所有 ARP/IP/UDP 解析、缓冲 RAM 访问和业务消息接口均位于 125 MHz `userclk2` 域。100 MHz 域
只产生和监测初始化条件；`clock_ready_o`、MMCM lock、PCS/PMA reset-done 和 PCS link 状态进入
数据面前必须同步。状态跨回 100 MHz LED/ILA 域时使用专用同步器或计数器快照，绝不直接跨域
读取多位工作指针。

### 4.1 单端口回归模块 `udp_transport_fixed_host`

`udp_transport_fixed_host` 保留为单端口回归模块；当前 `udp_top` 的双端口实现见第 7.4 节。
该回归模块内部按数据所有权拆成五个均运行于 125 MHz 数据面的子模块：

```text
Ethernet RX AXIS -> fixed_host_rx_parser -> udp_rx_payload_ring -> 业务 RX 消息
                         │                        │
                         ├─ ARP reply request    └─ reserve/write/commit 边界
                         └─ RX event/drop reason ───────────────┐
                                                               v
业务 TX 消息 -> udp_tx_payload_ring -> fixed_host_tx_engine -> Ethernet TX AXIS
                         │                    ▲        │
                         └─ 完整载荷/校验和 ──┘        └─ TX event
                                                               │
                                   udp_transport_stats <────────┘
```

- `fixed_host_rx_parser` 独占 Ethernet/ARP/IPv4/UDP 字段解析、IPv4/UDP checksum 累加与固定端点
  判定。它在载荷到达时向 RX FIFO 输出候选写入，只在帧尾全部检查通过时发出 `commit + length`；
  失败帧只产生分类 drop 事件，候选内容始终不可见。
- `udp_rx_payload_ring` 独占四槽同步 BRAM、槽长度、读写指针、槽数量和业务 RX 握手。解析器仅查询
  当前槽是否可用并使用当前候选槽，无法直接修改已提交消息；同周期业务释放允许新帧预留槽位。
- `udp_tx_payload_ring` 独占双槽同步 BRAM 和业务 TX 握手，检查 descriptor、长度和 `last`，并在
  收集载荷时生成 one’s-complement payload sum。只有完整消息才向发送引擎发布，且可在发送槽 N
  时并行填充槽 N+1。
- `fixed_host_tx_engine` 在 ARP 应答和完整 UDP 消息之间仲裁，生成 Ethernet/IPv4/UDP 头、IPv4
  checksum、最终 UDP checksum 和 IP Identification，并在 AXI 反压期间保持输出稳定。
- `udp_transport_stats` 只接收各功能模块的单周期事件，集中维护饱和计数器和
  `last_drop_reason`，不参与数据通路控制。

解析器与 RX FIFO 之间的 `rx_commit_udp` 是接收可靠性边界：帧内容可以提前写入当前未提交槽，
但只有 `rx_commit_udp` 才推进写指针并增加可见消息数。checksum 保持在其数据流所属模块内，不再
拆出额外有状态流水模块，以免为逐字节数据增加无收益的跨模块反压。

### 4.2 已实施的载荷缓存重构

业务层接入前，RX/TX payload 缓存已按独立设计单元
[`../udp-payload-ring/MODULE.md`](../udp-payload-ring/MODULE.md) 完成重构。所选结构是固定大小报文
槽环：RX 默认 4 槽，TX 默认 2 槽；深度 2 的 TX 槽环同时承担乒乓缓存。payload 主存储改为同步
Block RAM，并通过预取/保持逻辑维持现有业务消息握手。TEMAC RX/TX Ethernet FIFO、FCS 校验/
生成和三速时钟边界不合并到该设计单元。

新模块已完成单元/协议仿真、完整展开、构建和板级回显回归，并成为当前 RTL 与 bitstream 基线。

## 5. 启动、复位与链路状态

1. FPGA 配置后，AD9517 控制器在 100 MHz 域完成配置并给出 `clock_ready_o`。
2. `udp_top` 在 AA3 边界统一例化一组 `IBUF+BUFG`，缓冲后的 100 MHz 同时驱动 AD9517
   控制器和 `ethernet_link_top`。其 Clocking Wizard 配置为 `No_buffer` 输入，产生已 BUFG 缓冲的
   200 MHz `independent_clock_bufg` 并输出 `locked`，不会对 AA3 重复例化输入缓冲。
3. 在 `clock_ready_o` 与 Clocking Wizard `locked` 都成立前，保持 PCS/PMA、TEMAC 和 UDP
   传输层复位。200 MHz 与 AD9517 125 MHz 不要求相位相关。
4. PCS/PMA 报告 CPLL/GT reset-done 后，等待 SGMII 同步和 auto-negotiation 完成；从
   `status_vector[11:10]` 锁存 M88E1111 上报的铜口速率，并要求 full duplex。
5. 链路/速率控制器同时更新 TEMAC RX/TX Configuration Vector；TEMAC 速度指示反馈给 PCS/PMA，
   PCS/PMA 的 `sgmii_clk_en` 送回 TEMAC。待 MAC/FIFO 复位释放且 PCS 与铜口 link 都有效后，才
   置 `link_ready` 并允许 UDP 接收和发送。
6. 任一时钟或链路前置条件丢失时，停止接收/发送并清空所有未提交的组帧状态；已经完成并进入
   RX FIFO 的槽位可由业务侧继续读出。链路恢复后重新从空闲状态开始，不输出跨中断的半帧。

## 6. 接收路径

接收解析器只处理 Ethernet II → ARP 或 IPv4 → UDP。TEMAC 完成 MAC 帧接收与 FCS 检查；本模块
继续检查 EtherType、目的/源 MAC、IPv4 版本/IHL/总长度/头校验和、非分片标志、协议号、目的/源
IPv4、UDP 长度和目的/源端口。UDP checksum 必须非零；模块验证它覆盖的 IPv4 伪首部、UDP 头
和数据报，零 checksum 与校验失败均丢弃。首版只接受 `Version=4` 且 `IHL=5`
的 20-byte IPv4 首部；携带 IP Options 的报文整帧丢弃。

接收到一个合格 UDP 头时，仅当有可用 RX 槽位才开始写入。首版固定
`MAX_UDP_PAYLOAD=1472`，即标准 1500-byte Ethernet MTU 下的 IPv4/UDP 最大载荷；较短的
控制报文仍按其实际长度传输。槽位数固定为 `RX_SLOT_COUNT=4`。只有在整帧 checksum、长度检查和
写入均完成后，候选槽位才被提交给业务侧；无槽位或任一检查失败则吞掉该帧剩余字节并增加对应
错误计数。

因此 RX FIFO 是 4 个独立的 `MAX_UDP_PAYLOAD` 消息槽位，而不是可能暴露半帧的字节流 FIFO。
接收时只缓存 UDP 载荷，不缓存 Ethernet/IP/UDP 头；业务侧消费一个槽位期间，其他已完成槽位
保持不可覆盖。

## 7. 业务侧通用接口

业务侧接口不是 DB500 协议接口，所有 payload 字节按网络顺序原样传递。

### 7.1 接收消息接口

| 信号 | 方向 | 约定 |
|---|---|---|
| `rx_msg_valid` | 输出 | 一个完整已验证 UDP 数据报可读时为 1，直到最后一个字节被接受 |
| `rx_msg_ready` | 输入 | 业务侧允许接收当前字节；低时输出数据和元数据保持稳定 |
| `rx_msg_data[7:0]` | 输出 | UDP 载荷字节，顺序不变 |
| `rx_msg_last` | 输出 | 当前字节为该数据报最后一个字节时为 1 |
| `rx_msg_len[LEN_W-1:0]` | 输出 | 当前数据报的总载荷长度；`LEN_W=$clog2(MAX_UDP_PAYLOAD+1)`，在整个报文期间稳定 |

`rx_msg_valid && rx_msg_ready` 才传递一个字节。最后字节传递后才释放该槽位；空 UDP 载荷不作为
首版合法业务报文接收，以免引入无数据的握手特殊情况。

### 7.2 发送消息接口

| 信号 | 方向 | 约定 |
|---|---|---|
| `tx_msg_valid` / `tx_msg_ready` | 输入/输出 | 握手接受一条待发送消息的 `tx_msg_len`；仅在 TX 槽环存在空槽且链路可发送时 ready |
| `tx_msg_len[LEN_W-1:0]` | 输入 | 本条 UDP 载荷长度，范围 1..`MAX_UDP_PAYLOAD`，在 descriptor 握手时锁存 |
| `tx_msg_data_valid` / `tx_msg_data_ready` | 输入/输出 | descriptor 成功后传送恰好 `tx_msg_len` 个字节 |
| `tx_msg_data[7:0]` | 输入 | 待发送 UDP 载荷字节，顺序不变 |
| `tx_msg_data_last` | 输入 | 必须与第 `tx_msg_len` 个字节同时为 1 |
| `tx_msg_error` | 输出 | 业务侧早结束、晚结束或长度越界时置位一个周期；该消息不发送 |

当前已验收发送侧使用默认双槽的可参数化 `MAX_UDP_PAYLOAD` 报文环。只有长度与 `last` 一致的
完整消息才被封装；IP
Identification 对每个已发送 UDP 数据报递增，IPv4 头校验和与非零 UDP 校验和均由硬件生成。
若 one’s-complement 运算结果恰为 `16'h0000`，按 UDP 规则在线上发送 `16'hFFFF`，避免与“未使用
checksum”的零值混淆。发送 IPv4 首部固定 `TTL=64`、`Protocol=17`、`IHL=5`、
`DF=1`、`MF=0`、分片偏移为零，不产生 IP Options。

### 7.3 首个用户通信消费者

CONTROL 先行阶段没有改变本模块的消息契约：端口 32000、唯一一组 RX/TX 完整消息接口、
RX 4 槽和 TX 2 槽均保持不变。`udp_control_test_top` 已把这一组接口全部连接到
`db500_udp_control`，现有 `udp_echo_test_top` 继续作为独立回归基线。

CONTROL 接入已经在 `udp_top` 分离基础复位和软通信复位：
`comm_base_resetn_o = link_user_resetn && link_ready_o`，
`comm_resetn_o = comm_base_resetn_o && comm_soft_resetn_i`。CONTROL watchdog 的软复位只清空 UDP
transport、CONTROL 和外部寄存器适配器事务状态，不接管 Ethernet client FIFO。500 ms 静默
跨代已完成板级验证；主机网卡软件禁用/启用不再作为恢复机制。

当前 RTL 已按目的 UDP 端口加入 DATA 独立逻辑通道和完整报文级 TX 仲裁；该扩展不使 UDP 层解释 CONTROL 字段，也不改变已经冻结的
CONTROL 报文和寄存器接口。详细规划见
[`../db500-udp-control/MODULE.md`](../db500-udp-control/MODULE.md) 和
[`../db500-udp-application/MODULE.md`](../db500-udp-application/MODULE.md)。

### 7.4 DATA 双通道与 Jumbo 实现

DATA 只承接业务组好的 payload；原工程图像模块输出的 12-Byte 业务头也是透明内容。
图像/RTM 仲裁、图像分包、业务序号、重组和补传不进入本层。DATA 在文档上独立，实现以本层扩展为主，
不强制增加 `db500_udp_data.v`；接口、请求/结果管理与具体接入方案见
[DATA MODULE.md](../db500-udp-data/MODULE.md) 第 3～9 节；业务提交完成与缓存释放边界见本层第 7.5 节，
通道集成、仲裁和复位隔离见用户通信架构 MODULE.md。

本设计单元的具体实现：

- `udp_top/udp_transport_dual_host`：暴露 CONTROL/DATA 独立消息接口和配置，继续共享网络引擎；
  CONTROL 保持端口 32000，DATA 本地/主机端口设计默认均为 32001，可综合期配置，不复制整套协议栈。
  DATA 使用 RX/TX 各 32 KiB 字节环和各 16 条描述符；CONTROL 保留 RX4/TX2、最大 payload1472 槽环。
- `fixed_host_rx_parser_dual`：在 UDP 头阶段按配置端口锁定目标通道，在该通道预留整包字节及描述符，帧尾只向
  正确通道 commit/abort；DATA 资源不足时排空该帧，不阻塞后续 CONTROL。按通道统计丢弃。
  当前在帧首锁存唯一 slot_available 的行为必须调整到端口/长度已取得、payload 尚未开始时。
  parser 按通道检查容量上限；CONTROL 的 16-Byte 格式检查仍由 decoder 完成，原有异常统计和活动事件保持。
- 发送仲裁与 `fixed_host_tx_engine_dual`：只选择完整报文，锁定端口、长度、checksum 与来源直到帧尾；
  CONTROL 有界优先，竞争时连续额度首版 RTL 默认 4 帧，随后让出一次给 ARP/DATA 轮询；无竞争时不留空额度。
  完整选择算法见 DATA MODULE.md 第 10.3 节，最终额度经并发验证确定。
  建议将现有 engine 内 ARP/UDP 选择收敛到独立小型帧仲裁器，由一次 descriptor 握手启动 engine，
  避免外部双通道仲裁与内部 ARP 优先级各自拥有一套调度状态。
  ARP pending 由仲裁侧保存；启动锁存通道端口/长度/checksum 配置，payload 改用带 valid/ready 的
  同步 BRAM 字节流，不能直接沿用当前无 valid 的地址读口。契约见 DATA MODULE.md 第 8.5～8.6 节。
- DATA 交付完成：完整包通过长度/last 检查并提交 TX 队列即成功；不继承原 TEMAC 完成定义。
  不增加逐帧来源/token 跟踪与业务 MAC 完成回传。当前 sent_event/packet_release 仍用于后续
  帧复制进 Ethernet FIFO 时的内部释放和统计，不等同于更早的业务包提交。
- DATA checksum 配置：RX_REQUIRE_UDP_CHECKSUM 与 TX_UDP_CHECKSUM_ENABLE 为独立综合期参数，
  在 DATA 配置中均默认 1；不改变 CONTROL 当前强制校验规则。参数语义见 DATA MODULE.md 第 5.3 节。
- 出口排队：后到 CONTROL 正常排在已选中/已进入 Ethernet FIFO 的帧后面；优先级仅作用于当前待选帧。
  首版由 FIFO 容量及 ready/valid 反压约束积压，不额外设在途帧额度，不等 MAC 发完上一帧再仲裁。
  正常排队下的 CONTROL 延迟需结合 1G Jumbo 并发吞吐验证。
- CONTROL 软复位：不能继续清空整个公共 transport；仅取消 CONTROL 事务和未发送队列。
  已选中的 CONTROL 帧需保留有效数据直到安全收尾，已排入公共出口的旧帧正常排空；DATA 和公共
  parser/engine/FIFO 保持运行，DATA 活动不刷新 CONTROL watchdog。
  按 DATA MODULE.md 第 9 节的 RUN/DRAIN_CTRL/CLEAR_HOLD 协调清理；RX 对当前帧保留 CONTROL
  禁止提交标记，TX 等旧引用解除再清空。CONTROL 核心的复位释放同时等待 32 周期请求结束和清理完成。

Jumbo 改造已将 DATA 长度/索引扩为 14 bit；MAC 配置向量的
`tx_jumbo_enable/rx_jumbo_enable` 已置 1，RX/TX client FIFO 及其 RAM 地址扩为 14 bit、每方向
16 KiB。指针、空满差值、状态高位和 BRAM 地址同步修改，不只放大 UDP payload 槽。

配置以 IP MTU 为统一口径，当前固定 IPv4 头下 `MAX_DATA_PAYLOAD = IP_MTU - 28`；业务头计入
payload，不额外扣除不存在的 DATA 公共头。已明确至少兼容原工程默认 8172-byte payload，
对应 IP 总长度 8200、MAC client 帧不含 FCS 8214、含 FCS 8218 Byte。它不是全模式最大值，
本版 MTU9000/payload8972 已在 FPGA 与主机直连链路验证；主机确认 JumboPacket=9KB、IPv4 NlMtu=9000，
测试时以 1 Gbps 建链。原工程证据和主机设置维护在 DATA MODULE.md 第 3 节。
默认完整帧已超过 8192 Byte，Ethernet 整帧 FIFO 不能仅扩成 8 KiB；帧内字节索引至少 14 bit。
Ethernet RX/TX FIFO 在现有官方例程 RTL 上各扩到 16 KiB，不以重新生成例程为前置。RAM 和地址
12→14 bit，队列内帧数另行推导并保守取 12 bit；同时覆盖 CDC 地址字段、安全余量、占用刻度和
溢出恢复，不能混淆“帧内字节数”和“FIFO 内帧数”。具体约束见 DATA MODULE.md 第 10.5 节。
当前承诺范围为已验证的最大 8972-Byte UDP payload，不外推到更大 MTU。
不增加 IP 分片，超大业务包明确拒绝，业务按公布的上限自行组包。

链路工作范围固定为 1G 全双工，保留现有 IP 和自动协商流程。`ethernet_link_speed_ctrl` 的
negotiated_valid 在原有状态条件之上仅接受 `pcs_status_i[11:10] == 2'b10`，完成 MAC 配置/复位
握手后才置 link_ready。低速、半双工或掉线时保持通信未就绪，公共 FIFO 与 CONTROL/DATA 按
基础链路边界清理；自动协商继续运行。无需新增 PHY MDIO 写入或动态包长降级接口，详细规则见
DATA MODULE.md 第 10.6 节。PCS/PMA 当前 FPGA logic SGMII 接收弹性缓冲在 1G 下的长度预算可覆盖
本版 Jumbo，完整链路仍需验收；已有三速回归记录仅描述现有基线，不构成新版本低速支持要求。

### 7.5 业务交付完成与缓存释放（新通道提案）

DATA 业务完成定义为：payload 已完整收齐、长度/last 检查通过，并成功提交 TX 队列。
建议接口以 packet_committed/status 表达，不继承原工程 tx_data_done 到 TEMAC 的含义。
请求许可、包提交和缓存释放是不同事件；完成通知不能令仍待网络发送的数据提前释放。

当前 fixed_host_tx_engine.sent_event_o 在帧尾进入 Ethernet FIFO 时产生，可以继续用于
payload 存储释放和现有 tx_sent 统计；新增提交计数明确记录 commit，不默默改变旧统计语义。

不再为业务完成建立逐帧 token/来源记录、MAC 完成 CDC 或多请求结果排序队列。
每条通道的收包状态在提交或输入失败时产生本地状态，可在状态未消费时反压下一条请求。
已提交包后续因链路故障被丢弃，通过链路状态和错误/丢弃计数报告，不撤回已成立的本地交付完成。
对端收到与否由外部协议处理。

Ethernet FIFO overflow 等状态仍应可观测，FIFO 自身跨域空满控制保持正确；首版不额外增加
用于调度额度的 MAC 消费计数或逐包完成跟踪。对端可靠交付与本地队列提交不是同一承诺。

## 8. 可观测性与错误处理

以下计数器在 125 MHz 域饱和计数，通过同步快照供 ILA/软件读取：`rx_frames_seen`、
`rx_udp_accepted`、`rx_drop_endpoint`、`rx_drop_ipv4`、`rx_drop_udp`、`rx_drop_checksum`、
`rx_drop_oversize`、`rx_drop_fifo_full`、`tx_accepted`、`tx_sent` 和 `tx_input_error`。

此外输出 `link_up`、`rx_fifo_level`、`tx_busy` 和最近一次接收丢弃原因。计数器是本模块“稳定
可靠”承诺的一部分：任何不能交付的帧必须可定位原因，不能仅以 LED 或隐含状态表示。

## 9. 验证与实施入口

完整的吞吐、包率、突发、丢包和时延测试定义见
[`PERFORMANCE_TEST_PLAN.md`](PERFORMANCE_TEST_PLAN.md)。当前单包回显通过只代表功能基线，
不等同于持续线速性能已经验收。

PCS/PMA + TEMAC 链路层不依赖网络地址，可以先行实施。生产用 IP、链路 RTL 和后续 UDP RTL、
testbench、XDC 必须登记到 `D:\MyFPGAProject\UDP\fpga\led\led.xpr` 和
`fpga/led/scripts/sources.tcl`。生产设计不直接例化两个官方 example top；只提取已经核对过的
support/FIFO 结构，并在共享工程内重新生成生产 XCI。

仿真首先覆盖：ARP 应答；固定端点收发；最小、典型和 `MAX_UDP_PAYLOAD` 载荷；4 槽位背压；FIFO
满；零/错误 UDP checksum、错误 IPv4/UDP 长度、非主机源、IP 分片，以及 TX 长度/`last` 不匹配。
随后才依次执行
PCS/PMA+TEMAC 的构建时序检查和真实上位机链路测试。

2026-09-10 已在共享 `led.xpr` 中登记生产用 `ethernet_clk_wiz_200m`、
`pcs_pma_sgmii_gtx`、`temac_sgmii_tri_speed`、`ethernet_link_top`、`ethernet_link_speed_ctrl` 和官方结构的
RX/TX Ethernet FIFO。控制器行为仿真覆盖 1000M 首次协商、掉线、100M/10M 重协商、半双工
拒绝和保留速率拒绝；Clocking Wizard 自检确认 100 MHz 输入下 `locked` 正常且输出周期为
5.000 ns。完整 Clocking Wizard+PCS/PMA+TEMAC+FIFO 顶层已通过 Vivado/XSim 编译与静态展开。该段
记录描述当时的 AD9517 验收基线；当前 active top 已在后续 CONTROL 集成中切换为
`udp_control_test_top`，UDP 回显顶层仍保留为回归入口。

2026-09-11 已新增并登记 `udp_top` 与 `udp_top.xdc`。组合顶层实际例化
`ad9517_clock_manager + ethernet_link_top`，将合格的 `clock_ready_o` 接入链路复位边界，并把
AA3 收口为单一 `IBUF+BUFG`；Clocking Wizard 改为 `No_buffer` 输入。组合 XDC 已包含 AD9517 SPI
接口的 generated-clock/datapath 约束以及 SGMII/GTREFCLK 管脚。该结构重新通过
Clocking Wizard 200 MHz 自检和包含 AD9517、PCS/PMA、GTX、TEMAC、RX/TX FIFO 的完整静态展开；
AD9517 六场景与 tri-speed 控制回归也均通过。当时组合 XDC 保持禁用、`sources_1` top 保持
`ad9517_clock_manager`；第 10 节的回显构建随后显式切换并启用了它。

固定端点地址、收发 UDP 32000 端口、标准 MTU 和 1472-byte 最大载荷已进入
`udp_transport_fixed_host` RTL。该模块已实现 ARP 应答、固定端点 Ethernet II/IPv4/UDP 收发、
IPv4 首部校验、强制非零 UDP checksum、4 个完整 RX 载荷槽位、2 个 TX 载荷槽位和分类
丢包/收发计数器。`udp_top` 已将 Ethernet FIFO AXI4-Stream 收口到该传输层，顶层现在暴露载荷
消息接口和调试状态，不再把原始 Ethernet 帧作为系统顶层端口。

Vivado/XSim 协议自检已通过：合法奇数长度载荷、1472-byte MTU 边界、固定端点拒绝、零/错误
UDP checksum、IPv4 分片拒绝、UDP 长度不一致、1473-byte 超长丢弃、4 槽位满保护、ARP 应答、
TX IPv4/UDP 校验和、TX AXI 反压稳定与业务长度/`last` 错误。包含 AD9517、PCS/PMA、GTX、TEMAC、
Ethernet FIFO 和 UDP 传输层的 `udp_top` 重新通过完整静态展开。高速业务使用的 TX 双槽、RX
四槽和同步 BRAM 已按 [`../udp-payload-ring/MODULE.md`](../udp-payload-ring/MODULE.md) 实施；
集成测试额外覆盖两槽填满、第三条消息反压和恢复后的顺序发送。

当前仍没有产品业务模块消费/生产载荷消息，因此 `udp_top` 的逻辑消息端口不是可直接约束到
板级管脚的最终产品边界。为进行真实链路验收，已增加只用于开发的回显业务外壳，状态见第 10 节。

### 9.1 当前实现入口

- [`udp_top.v`](../../../fpga/led/led.srcs/sources_1/new/udp_top.v)
- [`udp_top.xdc`](../../../fpga/led/led.srcs/constrs_1/new/udp_top.xdc)（已登记，当前回显构建启用）
- [`ethernet_link_top.v`](../../../fpga/led/led.srcs/sources_1/new/ethernet/ethernet_link_top.v)
- [`ethernet_link_speed_ctrl.v`](../../../fpga/led/led.srcs/sources_1/new/ethernet/ethernet_link_speed_ctrl.v)
- [`udp_transport_fixed_host.v`](../../../fpga/led/led.srcs/sources_1/new/ethernet/udp_transport_fixed_host.v)
- [`fixed_host_rx_parser.v`](../../../fpga/led/led.srcs/sources_1/new/ethernet/fixed_host_rx_parser.v)
- [`udp_rx_payload_ring.v`](../../../fpga/led/led.srcs/sources_1/new/ethernet/udp_rx_payload_ring.v)
- [`udp_tx_payload_ring.v`](../../../fpga/led/led.srcs/sources_1/new/ethernet/udp_tx_payload_ring.v)
- [`udp_rx_payload_ring_tb.v`](../../../fpga/led/led.srcs/sim_1/new/udp_rx_payload_ring_tb.v)
- [`udp_tx_payload_ring_tb.v`](../../../fpga/led/led.srcs/sim_1/new/udp_tx_payload_ring_tb.v)
- [`fixed_host_tx_engine.v`](../../../fpga/led/led.srcs/sources_1/new/ethernet/fixed_host_tx_engine.v)
- [`udp_transport_stats.v`](../../../fpga/led/led.srcs/sources_1/new/ethernet/udp_transport_stats.v)
- [`udp_transport_fixed_host_tb.v`](../../../fpga/led/led.srcs/sim_1/new/udp_transport_fixed_host_tb.v)
- [`udp_payload_echo.v`](../../../fpga/led/led.srcs/sources_1/new/ethernet/udp_payload_echo.v)
- [`udp_echo_test_top.v`](../../../fpga/led/led.srcs/sources_1/new/udp_echo_test_top.v)
- [`udp_control_test_top.v`](../../../fpga/led/led.srcs/sources_1/new/udp_control_test_top.v)
- [`udp_payload_echo_tb.v`](../../../fpga/led/led.srcs/sim_1/new/udp_payload_echo_tb.v)
- [`create_ethernet_ips.tcl`](../../../fpga/led/scripts/create_ethernet_ips.tcl)
- [`check_udp_top_elaboration.tcl`](../../../fpga/led/scripts/check_udp_top_elaboration.tcl)
- [`check_udp_echo_top_elaboration.tcl`](../../../fpga/led/scripts/check_udp_echo_top_elaboration.tcl)
- [`run_udp_transport_sim.tcl`](../../../fpga/led/scripts/run_udp_transport_sim.tcl)
- [`run_udp_payload_ring_sim.tcl`](../../../fpga/led/scripts/run_udp_payload_ring_sim.tcl)
- [`run_udp_echo_sim.tcl`](../../../fpga/led/scripts/run_udp_echo_sim.tcl)
- [`build_udp_echo.tcl`](../../../fpga/led/scripts/build_udp_echo.tcl)
- [`program_udp_echo.tcl`](../../../fpga/led/scripts/program_udp_echo.tcl)
- [`test_udp_echo.py`](../../../fpga/led/scripts/test_udp_echo.py)

## 10. 板级 UDP 回显测试外壳

为了在不引入 DB500 业务协议的前提下验证真实链路，独立测试顶层 `udp_echo_test_top`
例化完整 `udp_top` 和载荷透明的 `udp_payload_echo`。它只把已经传输层验证、提交的完整
RX 消息原样送回 TX 消息接口：先握手长度描述符，再在 TX 数据通道可接收时逐字节释放
RX 槽位，直到 `last`。任何 TX 反压都直接传递给 RX 消息接口，不增加第二份载荷缓存。

该外壳只用于开发验证，不是产品业务逻辑。上位机向 `192.168.1.20:32000` 发送的合法非空 UDP
载荷应从 `192.168.1.20:32000` 原样返回 `192.168.1.10:32000`；ARP 请求则仍由
`udp_transport_fixed_host` 回答。

### 10.1 当前验证结果（2026-09-11）

- `udp_payload_echo_tb` 已通过描述符反压、数据反压和末字节释放测试。
- `udp_echo_test_top` 已通过包含 AD9517、Clocking Wizard、PCS/PMA、GTX、TEMAC、Ethernet FIFO、
  UDP 传输层和回显外壳的完整静态展开。
- `udp_transport_fixed_host` 已按第 4.1 节拆成五个单一所有权子模块，封装层参数和端口保持不变。
  原完整协议 testbench 在重构后重新通过；`udp_top` 和 `udp_echo_test_top` 也分别完成包含全部
  Ethernet IP 的静态展开。
- 使用公司 TEMAC 完整许可重新生成 IP output products 后，组合顶层已完成综合、布局、布线和
  bitstream。补齐官方 example design 同类的 reset synchronizer `ASYNC_REG` 属性、异步 PRE
  false-path 及 125 MHz GTREFCLK 主时钟约束后，最终 `WNS=+0.614 ns`、`WHS=+0.063 ns`、
  未布线网络为 0，且所有用户时序约束满足；阻断级 DRC 为 0。
- 路由后 DRC 没有 Error 或 Critical Warning。`REQP-1839` Warning 包含 TEMAC 官方 FIFO 的
  异步复位控制，以及新 RX BRAM 地址/使能受同一异步复位来源间接影响；复位期间缓存内容本就
  作废，但该告警保留为后续复位质量审查项，不静默豁免。
- 层次利用率报告确认 RX 槽环使用 2 个 RAMB36、TX 槽环使用 1 个 RAMB36；整个设计共使用
  5 个 RAMB36，payload 主存储不再使用大容量 Distributed RAM。
- 本次 bitstream 为
  `D:/MyFPGAProject/UDP/fpga/led/led.runs/impl_udp_echo/udp_echo_test_top.bit`，生成时间
  `2026-09-11 23:09:59`，SHA-256 为
  `29FBF09792054768623AFADFF85FAF364E528B0DDAE1AC74F7B55914223C1619`。
- `program_udp_echo.tcl` 已将上述精确镜像易失下载到唯一 JTAG 目标
  `localhost:3121/xilinx_tcf/Digilent/E3077BAA4210` 的 `xc7k325t_0`；该回显镜像不含 ILA/VIO，
  下载前清除了旧 probes 关联，下载结果为 `UDP_ECHO_PROGRAM_PASSED`。
- Windows 主机“以太网 2”（ASIX USB Gigabit，MAC `9C-69-D3-1A-4C-6D`）以 1 Gbps 建链，
  IPv4 为 `192.168.1.10/24`。运行 `test_udp_echo.py` 后，14、256、1472-byte 三个确定性载荷均由
  `192.168.1.20:32000` 原样返回，源端点和逐字节内容全部匹配，结果为
  `UDP_ECHO_HOST_TEST_PASSED`。这证明标准 MTU 最大 UDP 载荷已经穿过真实 PHY/SGMII/PCS/PMA、
  TEMAC、Ethernet FIFO 和本传输层完成一次端到端闭环。
- 本次槽环重构的可复查证据为 `logs/udp_payload_ring_final_sim_20260911_231657.log`、
  `logs/udp_transport_ring_20260911_225814.log`、`logs/udp_echo_ring_20260911_225848.log`、
  `logs/udp_top_ring_elab_20260911_225926.log`、
  `logs/udp_echo_top_ring_elab_20260911_230328.log`、
  `logs/udp_echo_ring_build_20260911_230739.log` 和
  `logs/udp_echo_ring_program_20260911_231023.log`；路由与层次资源报告位于
  `led.runs/impl_udp_echo/reports/`。

当前 `sources_1` active top 为 `udp_echo_test_top`，`udp_top.xdc` 已启用；`sim_1` 仍保持
`ad9517_clock_manager_tb`。这次切换只服务下一步板级 UDP 回显测试，不改变已验收的 AD9517
独立顶层源码和验收结论。

### 10.2 性能验证进展（2026-09-12）

- 新增 `udp_echo_pipeline_perf_tb`，在 125 MHz MAC-client 字节域对完整
  `udp_transport_fixed_host + udp_payload_echo` 闭环施加 1 Gb/s 线路节奏。RX 输入和 TX ready
  模型都计入 MAC-client AXIS 不可见的 preamble/SFD、FCS 和 IFG 共 24 byte-time。
- 64-byte payload 连续 1000 包时，RX/TX 模型 goodput 均为 `492.399 Mbit/s`；1472-byte payload
  连续 1000 包时均为 `957.102 Mbit/s`。两轮均为 `rx_stalls=0`、`max_rx_level=1`、零 drop/error，
  接收和发送计数最终均为 2000，结果为 `UDP_ECHO_PIPELINE_PERF_PASSED`。
- 该结果证明 parser/checksum、RX 4 槽、echo、TX 2 槽和 TX engine 在周期级具备线速能力；它不
  包含真实 TEMAC FIFO、PCS/PMA、PHY、网卡和 Windows 软件栈，不能替代板级性能数据。
- 主机性能脚本 `scripts/test_udp_performance.py` 已通过静态检查、内部算法自检和本机 UDP 回显
  闭环。真实板级预检查因固定 MAC 对应的 ASIX“以太网 2”处于 `Disconnected / 0 bps` 而停止；
  当前单包回显实际超时。只读 JTAG inventory 能发现原 Digilent target，但其下没有任何 FPGA
  device，Vivado 报告 `No devices detected`，因此未执行重新下载；这些结果只表示板卡供电或外部
  连接条件不成立，不判定 FPGA 失败。
- 完整测试结果、日志身份和恢复板级测试的前置条件见
  [`PERFORMANCE_TEST_PLAN.md`](PERFORMANCE_TEST_PLAN.md) 第 11 节。

### 10.3 真实板级性能探索（2026-09-14）

- 外部条件恢复后，已核对 ASIX 1 Gbps 链路、固定 MAC/IP、唯一 JTAG target/device 和既有 echo
  bitstream SHA-256，并重新下载该无 ILA/VIO 镜像；下载前后单包回显均通过。
- COMB-01 的 20/256/1472-byte 各 1000 包全部通过，loss/duplicate/reorder/corrupt 均为 0。
- 1472-byte 尽力发送实际达到 `956.417 Mbit/s` payload（`999.300 Mbit/s` wire-equivalent）；
  受控 900 Mbit/s 点实际达到 `893.193 Mbit/s`，758,488 包全部回收且无丢包/重复/损坏，但记录
  到 122 次回包倒序。
- 倒序可在不同包长和速率下复现：64-byte 25 Mbit/s/10 秒出现 2 次；1472-byte
  420 Mbit/s/60 秒出现 5 次。低速 64-byte 20 Mbit/s/10 秒和 1472-byte 400 Mbit/s/10 秒无错，
  但不视为长期无错上限。
- pktmon 过滤抓包在对应输入窗口看到 Host→FPGA sequence 有序、FPGA→Host sequence 倒序；回包
  IPv4 Identification 又证明倒序已存在于 TX engine 分配 IP ID 之前。后续开发专用 ILA 在
  TEMAC RX client AXIS、RX message 和 TEMAC TX client AXIS 三点同时观察到相同的
  `0x5FE,0x600,0x5FF,0x601`，首次倒序在最前端 RX 边界已经出现。因此 parser、RX ring、echo、
  TX ring 和 TX engine 均保持输入顺序，工程归因为 `EXTERNAL_HOST_TX_ORDERING`，而不是 UDP RTL
  重排；外部细分优先排查 ASIX USB 网卡的 NDIS/offload/USB 发送路径。
- 1472-byte、请求 900 Mbit/s 的 60 秒持续轮实际达到 `888.974 Mbit/s`，4,529,421 包全部回收，
  loss/duplicate/corrupt 为 0；因实际 offered 未到 900 Mbit/s，该轮证明的是约 889 Mbit/s
  稳定性，不是精确 900 Mbit/s 发生能力。
- burst 1/2/4/6/8/16/64 的七个 10 秒轮次均无 loss/duplicate/corrupt；实际 offered 随 burst
  从 `769.450` 提升到 `895.872 Mbit/s`，未观察到受控突发造成半包、拼包或停滞。
- 已完成十次“尽力过载 10 秒 → 100 Mbit/s 恢复 10 秒”。过载段每轮主机可见缺失 45～47 包且
  均无内容损坏；十个恢复段各 84,919 包，loss/duplicate/reorder/corrupt 全为 0，证明重复过载
  后均能自动恢复且无累积死锁。
- COMB-04 首轮 10 分钟长稳实际 offered/received 为 `797.895/797.894 Mbit/s`，40,653,617 包
  全部回收，loss/duplicate/corrupt 为 0，记录已知外部 reorder 2634 次，判定为
  `PASS_WITH_KNOWN_REORDER_GAP`。该轮覆盖大量槽环指针回绕且未出现停流。
- 板级矩阵、原始 JSON/CSV 和抓包报告见
  [`PERFORMANCE_TEST_PLAN.md`](PERFORMANCE_TEST_PLAN.md) 第 12 节及
  [`packet-audit/20260914-udp-echo-reorder/REPORT.md`](../../reports/packet-audit/20260914-udp-echo-reorder/REPORT.md)。
- 诊断镜像实现结果为 `WNS=+0.327 ns`、`WHS=+0.056 ns`、阻断级 DRC 0；捕获结束后已经恢复
  无 ILA/VIO 的原 echo bitstream，并重新通过 14、256、1472-byte 单包回显。
- 已归因的外部 sequence 乱序作为已知缺口报告，不再阻断后续吞吐、PPS、丢包、内容完整性、
  过载恢复和长稳测试；这些测试显式采用 `PASS_WITH_KNOWN_REORDER_GAP` 结果类别。它仍不能被
  忽略为“有序”，也不能用当前 ASIX 链路完成顺序保证验收。
- 本轮继续测试共 29 轮、提交 59,293,060 包；463 个主机可见缺失全部发生在允许丢包的十次
  尽力过载段，其他轮次 loss/duplicate/corrupt 均为 0。正式 30 分钟长稳、精确 900 Mbit/s
  发生能力和独立顺序验收仍待完成；详细数据见性能计划第 12.7 节。
