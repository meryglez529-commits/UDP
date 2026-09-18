# DB500 UDP DATA 通信设计

状态：`DATA_RTL_IMPLEMENTED_BUILT_AND_BOARD_VERIFIED`

## 1. 文档定位

本文描述 DB500 用户通信层中的 DATA 设计单元。它向业务侧提供双向、透明、保留报文边界的
UDP payload 通道，在现有 `udp_top` 中以 `udp_transport_dual_host` 扩展实现。

DATA 的一包就是业务已经组好的一个 UDP payload。图像、RTM、ADC 或 DDR 提供的数据均作为
字节内容传递；已有的 12-Byte 业务头也是 payload 的一部分，DATA 不解释其字段。

本文定义业务接口、报文缓存、提交与释放、错误恢复以及接入现有 UDP 的要求。模块间关系见
[用户通信架构](../db500-udp-application/MODULE.md)，共享网络逻辑见
[UDP 设计](../udp/MODULE.md)，既有固定槽实现见
[payload ring 设计](../udp-payload-ring/MODULE.md)。

独立设计文档不要求增加同名 `db500_udp_data.v`。实现采用 DATA RX/TX ring、共享双端口
parser/engine 和 `udp_top` 业务端口；实施与验收证据统一见第 12 节和 `DEVELOPMENT.md`。

## 2. 职责边界

### 2.1 DATA 交付给业务侧

- TX 接受业务给出的包长和 payload，提供逐字节反压，收齐并检查后提交发送队列。
- RX 只交付通过网络检查的完整 payload，保持长度、包边界和字节顺序。
- 错误包不对接收业务或网络发送引擎可见；缓存不足有明确的反压或整包丢弃行为。
- TX 返回本地输入结果，业务可区分提交成功、非法长度、错误包尾和提交前取消。

UDP 不保证报文不丢失、不重复、不乱序，也不保证在给定时限内送达。DATA 队列保持本地提交
顺序，不对网络已经造成的丢失、重复或乱序作修复。

### 2.2 共享 UDP 与 Ethernet 层负责

| 所属层 | 职责 |
|---|---|
| 共享 RX parser | 固定端点匹配、端口分类、IPv4/UDP 长度和 checksum 检查、最终 commit/abort 判定 |
| 共享帧仲裁器与 TX engine | 选择完整 ARP/CONTROL/DATA 帧，锁存发送参数，完成网络封装 |
| Ethernet 层 | TEMAC、FCS、完整帧缓存、MAC 时钟域适配及链路错误状态 |

DATA payload FIFO 保存业务报文，Ethernet FIFO 保存完整 Ethernet 帧。两层各有用途，不在
DATA 接口外再增加一份重复的 payload 缓存。

### 2.3 DATA 明确不承担

- 图像/RTM 分包、多个业务源仲裁、业务头生成或解析。
- 业务序号、对象身份、图像重组、存储地址和对象完成判定。
- DDR/ADC 状态、数据是否可重读、历史保存和补传策略。
- ACK、重传、去重、重排、端到端送达确认或额外应用层 CRC。
- CONTROL 寄存器协议及产品寄存器适配。

## 3. DATA 报文规则与设计参数

### 3.1 基本规则

每个 DATA UDP 数据报承载一包业务 payload，DATA 不增加公共业务头。业务多字节字段的字节序
由外部业务协议定义，DATA 按输入字节顺序原样传递。

| 项目 | 首版契约 |
|---|---|
| 网络格式 | 无 VLAN、IPv4 固定 20-Byte 头、UDP；不支持 IPv4 options 或分片/重组 |
| 链路工作范围 | 仅 1 Gb/s、全双工；CONTROL/DATA 共用这一通信就绪条件，不支持 10/100 Mb/s 降级运行 |
| 主机 | 沿用固定唯一主机配置，不引入运行时端口协商 |
| DATA 本地/主机 UDP 端口 | 默认 32001 / 32001，可综合期配置；须与 CONTROL 32000 区分 |
| DATA_RX_REQUIRE_UDP_CHECKSUM | 默认 1，RX 要求非零且正确的 UDP checksum |
| DATA_TX_UDP_CHECKSUM_ENABLE | 默认 1，TX 生成 UDP checksum；与 RX 配置独立 |
| IP MTU | 9000 Byte，FPGA 与直连 ASIX 1G 链路已按 8972-Byte UDP payload 上板验证 |
| MAX_DATA_PAYLOAD | 8972 Byte，即 9000−20−8；合法范围 1～8972，零长和超限拒绝 |
| 数据面 | 8 bit、125 MHz，每次握手 1 Byte；其他业务时钟域由边界适配器处理 |
| DATA RX / TX 字节容量 | 每方向 32768 Byte，分别参数化 |
| DATA RX / TX 描述符容量 | 每方向 16 条，包含活动读包及至多 1 条候选预留 |
| Ethernet RX / TX FIFO | 每方向 16 KiB，已完成实现、时序和最大 Jumbo 实板验证 |

8972 是 1G 工作范围内的通道存储与解析上限；只有链路满足第 10.6 节的 1G 全双工条件才开放通信。

超大业务报文由外部按公布的上限组包，UDP 层不自动拆包。8972 是本版设计范围，不表示原工程
所有运行模式均已覆盖；当前 FPGA 已验证本版 9000-Byte IP MTU，不外推到更大包长。

### 3.2 原工程默认包长与兼容范围

按无 VLAN、IPv4 无 options 计算：

| 层级 | 原工程默认值 | 本版最大值 |
|---|---:|---:|
| 业务数据区 | 8160 Byte | 由外部业务头长度决定 |
| UDP payload | 8172 Byte（含 12-Byte 业务头） | 8972 Byte |
| UDP 数据报 | 8180 Byte | 8980 Byte |
| IP 包 | 8200 Byte | 9000 Byte |
| Ethernet 帧，不含 FCS | 8214 Byte | 9014 Byte |
| Ethernet 帧，含 FCS | 8218 Byte | 9018 Byte |

表中帧长不含前导码和帧间隙。8200 是原工程默认包要求的最低 IP MTU，不是网卡设置值。
默认完整帧已经超过 8192 Byte，因此 Ethernet 整帧 FIFO 不能只扩到 8 KiB。

原工程依据：

- [command_monitor_new.v:255](D:/DB600/DB500_BEAM_optimize_V6.37.1_ion_beam/fpga_prj/AXI_DDR.srcs/sources_1/new/command_monitor_new.v:255)：业务区默认 8160；第 540～541 行允许通过寄存器 0x0076 修改。
- [lan_tx.v:123](D:/DB600/DB500_BEAM_optimize_V6.37.1_ion_beam/fpga_prj/AXI_DDR.srcs/sources_1/imports/user/lan_tx.v:123)：IP 长度为 payload+28，UDP 长度为 payload+8。
- [SGMII_TEMAC_config_vector_sm.v:184](D:/DB600/DB500_BEAM_optimize_V6.37.1_ion_beam/fpga_prj/AXI_DDR.srcs/sources_1/imports/imports/SGMII_TEMAC_config_vector_sm.v:184)：原工程 RX/TX Jumbo 已开启。

用户说明隔行模式可能重新计算包长。上述默认值不构成全模式上限，寄存器可编码范围也不等于
合法网络包长。

### 3.3 主机配置依据

2026-09-17 通过 Get-NetAdapter、Get-NetAdapterAdvancedProperty 和 Get-NetIPInterface
核对，并使用同一接口完成实板测试：

| 项目 | 查询结果 |
|---|---|
| 接口 | 以太网 2，ifIndex=4，ASIX USB to Gigabit Ethernet Family Adapter |
| 驱动高级属性 | JumboPacket，DisplayValue=9KB，RegistryValue=2（选项编码，不是字节数） |
| IPv4 IP MTU | NlMtu=9000 Byte |
| 查询时链路 | Up，1 Gbps；实际用于 DATA/Jumbo 板测 |

主机 MTU 满足原工程默认包要求。9000 来自实际接口查询，不是从截图“9KB”推测；它仅支持
本版长度预算，并已与 FPGA、PHY 和直连链路共同完成 Jumbo 验收。

## 4. 业务发送接口与完成语义

### 4.1 逻辑接口

| 接口 | 方向 | 契约 |
|---|---|---|
| `data_tx_req_valid/ready`、`data_tx_len` | 请求业务→DATA，ready 反向 | 请求握手登记本包长度；合法请求同时取得整包资源 |
| `data_tx_valid/ready/data/last` | 数据业务→DATA，ready 反向 | 每次握手消费 1 Byte；last 标记本包最后字节 |
| `data_tx_status_valid/ready/status` | 结果 DATA→业务，ready 反向 | 返回一条本地输入结果，保持至消费 |
| `data_tx_cancel_valid/ready` | 取消业务→DATA，ready 反向 | 取消未提交包，或结束错误排空；规则见第 7 节 |

所有握手发生在 125 MHz 时钟边沿。正常反压期间，源声明 valid 后须保持 valid 和对应负载，
直到握手；显式取消及通道复位的例外边界见第 7、9 节。
数据宽度为 8 bit，长度宽度 LEN_W=max(1,ceil(log2(MAX_DATA_PAYLOAD+1)))，默认 14 bit；
status 固定 3 bit，0～3 按第 7 节定义，4～7 预留。握手控制均为 1 bit。DATA 的复位由基础
通信复位提供，不能接现有包含 CONTROL watchdog 的 comm_resetn；对业务同步导出该复位和 link-up。

### 4.2 正常发送顺序

1. 业务声明请求及长度 L；DATA 按第 6 节同时检查字节空间和描述符空间。
2. 请求握手后进入收包。首字节最早在下一周期接受，不与请求同周期接受。
3. 业务逐字节交付，只有 valid 与 ready 同时为 1 才推进源 FIFO；第 L 字节必须携带 last。
4. 最后字节接收且长度/last 检查通过后，DATA 发布描述符及 checksum 中间和，返回 COMMITTED。
5. 业务消费结果后，接入控制才接受下一条请求；已提交包可同时继续被网络发送引擎消费。

请求许可不保证后续 ready 始终为 1。每次只收集一包，结果使用一个寄存器，不建立多请求结果
队列；业务结果反压不暂停已提交包的发送。

### 4.3 请求、提交与释放

| 事件 | 准确含义 | 存储状态 |
|---|---|---|
| 请求接受 | 当前包已登记；合法包取得收包许可 | 预留整包空间，尚不可发送 |
| 包提交 | 整包收齐并通过输入检查，通信层取得所有权 | 可等待网络发送，仍占 TX 缓存 |
| payload 消费完毕 | TX engine 将当前包完整复制到 Ethernet FIFO | 内部释放 DATA TX 空间 |

业务成功结果只对应包提交。若使用 `tx_packet_committed` 或沿用 `tx_data_done` 名称，其语义
均为此事件，不表示 TEMAC 已发送或 PC 已收到。

现有 `sent_event_o` 在帧尾进入 Ethernet FIFO 时产生，可继续用于内部释放和 tx_sent 统计，
不得改成更早的业务提交事件。提交后不提供逐包撤销或第二条网络失败结果，不增加逐帧 token、
MAC 完成回传和结果排序队列；后续链路故障通过链路状态与错误/丢弃计数反映。
新 DATA FIFO 以自身读口末字节握手产生唯一 release；对应 sent_event 只观察同一发送完成边界，
不能再给 FIFO 发送第二次释放。现有 CONTROL 槽环的 release 适配由共享集成层处理。

## 5. 业务接收接口与网络检查

### 5.1 逻辑接口

| 接口 | 方向 | 契约 |
|---|---|---|
| `data_rx_valid/data/last/len` | DATA→业务 | 输出已提交包；长度在整包期间稳定，last 只标记末字节 |
| `data_rx_ready` | 业务→DATA | 每次握手接受 1 Byte；末字节接受后释放该包 |

反压期间 valid、data、last 和 len 保持稳定。包长已知不表示首字节已经从同步 BRAM 返回，
只有读结果有效时才能声明数据 valid。

### 5.2 收包准入与提交

共享 parser 在 UDP 端口和长度齐备、payload 尚未开始前，锁定目标通道、长度 L 和预留结果。
不能继续沿用在 Ethernet 帧首锁存唯一 slot_available 的单通道做法。

准入失败时锁存本包丢弃，排空到 Ethernet last；即使中途资源释放，也不重新准入该包。
准入成功时只将 L 个 payload 字节写入候选区域，在帧尾全部检查通过后一次 commit，否则 abort。
候选内容在最终检查前始终不可见。

Ethernet RX FIFO 可以依次保存 CONTROL、DATA 和 ARP 帧，各帧保持自己的 Ethernet 头和帧尾标记。
共享 parser 顺序读帧，在网络头阶段分类；不要求 FIFO 预先知道通道，也不在同一帧内交错两路 payload。
FIFO 的帧尾是随数据保存并输出的 last 标记，不是在业务内容中搜索特殊结束字节。

### 5.3 校验范围与方向配置

- 固定主机 MAC、IPv4、UDP 端点匹配，网络格式满足第 3.1 节。
- IPv4/UDP 声明长度与实际报文一致，payload 不超上限。
- IPv4 checksum 和底层 MAC 帧检查通过；默认要求 UDP checksum 非零且正确。
- UDP checksum 包括伪首部、UDP 头及 payload；Ethernet padding 不进入 payload 校验。
- 奇数字节只在校验运算中补零，不向 payload RAM 写入补零字节。
- TX checksum 运算必须包含末字节；计算结果为零时线上编码为 0xFFFF。

RX 要求与 TX 生成采用第 3.1 节两个独立的综合期参数，当前均为 1，不关闭 TX 校验和生成。
RX_REQUIRE=0 时额外允许接收零 UDP checksum；收到非零值仍必须校验，不能接收已知错误的 checksum。
TX_ENABLE=0 时 IPv4 UDP checksum 字段填 0x0000，表示未生成；这与开启时计算结果为零而发送
0xFFFF 不同。两项均不关闭 IPv4 头校验、Ethernet FCS、长度/last 检查或整包提交机制。
TX_ENABLE=0 的路径不需要 payload checksum 中间和，但本版默认启用，保留现有累加与描述符设计。

这是网络完整性检查，不判断 payload 的业务内容。超长帧计数必须饱和或停止，错误保持到帧尾，
不能因计数回绕重新命中合法长度。

### 5.4 缓存不足

业务停顿使已提交包等待，不能无限反压物理入网。DATA RX 空间或描述符不足时整包丢弃并计数，
继续解析后续帧。独立 DATA 队列不占 CONTROL 专用缓存，但共享 Ethernet FIFO 溢出仍可能丢弃
任一端口的帧；公共 RX 必须能按最大设计线速排空。

## 6. 报文 FIFO 与存储所有权

### 6.1 字节环与描述符

RX、TX 分别使用独立同步双口 BRAM 字节环和描述符 FIFO，按实际包长分配。每方向至多一个
候选写包，可与一个已提交包的读取并行，不沿用既有 RX4/TX2 固定槽容量。

描述符包含 start、length；TX 另存 payload checksum 中间和。正在读取的头描述符仍算占用，
直到整个包消费完毕才弹出。一包可以跨 RAM 尾部，物理地址按容量环回，不留对齐空洞、不添加
线上分片。

### 6.2 整包预留与原子更新

设 B 为字节容量、D 为描述符容量、U 为已提交包加候选包的完整占用、Q 为已提交描述符数，
R 为候选预留标志。合法长度 L 的准入条件为：

```text
通道可运行 && R == 0 && B - U >= L && Q + R < D
```

首版使用时钟边沿前的空闲量，不借用同周期 release 的资源；满转空允许多等待一个周期。

| 操作 | 字节占用 U | 描述符状态 | 指针与可见性 |
|---|---|---|---|
| reserve | 加 L | R=1 | 锁存候选起点和长度，尚不可读 |
| write | 不变 | 不变 | 仅推进候选写游标，写入不得超出预留范围 |
| commit | 不变 | Q 加 1，R=0 | 最后数据写入并检查通过后发布描述符，推进提交尾 |
| abort | 减 L | R=0 | 提交尾不变，不修改读头和已有描述符 |
| release | 减头包长度 | Q 减 1 | 完整头包消费后推进读头 |

同周期事件统一计算 next-state，不允许多个分支各自覆盖占用计数：

```text
U_next = U + reserve_len - abort_len - release_len
Q_next = Q + commit - release

0 <= U <= B
0 <= Q + R <= D
U = sum(committed lengths) + reserved_length
```

commit+release、abort+release、reserve+release 均须满足上述关系。同一候选 commit 与 abort
互斥，取消/复位优先。回滚后的旧字节可以留在 RAM，没有有效描述符就不可见，不清空整块 BRAM。

### 6.3 同步 BRAM 读口

读口区分“已发起读地址”和“下游已接受字节”，用带 valid 的预取/保持寄存器吸收同步读延迟。
预取不得跨过当前包尾；长包无反压时需持续提供每周期 1 Byte，不能逐字节等待两周期。

TX/RX 都只在末字节被实际消费后 release，不能在发出末地址时提前释放。新描述符可见后必须
等待有效读结果；正确性不能依赖组合 RAM 或未定义的同地址读写行为。复位清除预取 valid，
旧 BRAM 返回值不得成为新包首字节。

### 6.4 容量与位宽

32 KiB 可存 3 个 8972-Byte 最大包及部分余量，不能存 4 个最大包；小包可能先耗尽 16 条描述符。
两方向 payload 主存储合计 64 KiB，不含描述符、CONTROL 或 Ethernet FIFO，最终 BRAM 数量由综合确认。

默认长度/帧长用 14 bit，物理字节地址用 15 bit，占用 0～32768 用 16 bit，描述符占用 0～16
用 5 bit。实现分别由参数推导，不能共用地址位宽作占用计数或写死默认宽度。

首版字节容量和描述符深度限定为 2 的幂；每方向容量至少为 MAX_DATA_PAYLOAD，描述符深度至少
为 2。非法配置在 elaboration 报错，避免合法最大包永远无法取得整包空间。
还需检查 1<=MAX_DATA_PAYLOAD<=IP_MTU-28，首版 IP_MTU 不超过 9000。外部收到的 IPv4/UDP
长度字段保留 16 bit，先按完整宽度检查上下限及加法溢出，再转换为内部 LEN_W；不得先截断再判定。
同周期占用增减使用足够宽的中间值，不能因 Verilog 表达式位宽或无符号下溢破坏第 6.2 节不变量。

容量预算需依据最坏累计到达量与可服务量之差，并包含未提交预留。当前没有量化突发/停顿上界，
32 KiB/16 条是首版基线，不附加零丢包保证。持续输入快于输出且源不能暂停时，外部须定义源 FIFO
溢出策略或限制输入速率。

## 7. 输入错误、取消与恢复

### 7.1 本地结果编码

| 编码 | 名称 | 含义 |
|---:|---|---|
| 0 | COMMITTED | 完整包通过检查并提交 TX 队列 |
| 1 | BAD_LENGTH | 请求长度为零或超上限，未接受 payload |
| 2 | BAD_LAST | 包尾与请求长度不一致，候选包回滚 |
| 3 | CANCELLED | 业务在提交前主动取消，候选包回滚 |

其他编码预留。正常完成或输入失败各产生一条结果；结果稳定保持到消费。基础复位会终止未消费
结果，其可见边界见第 9 节。

### 7.2 异常处理规则

| 情况 | 处理 | 恢复条件 |
|---|---|---|
| L=0 或 L>8972 | 接受请求并返回 BAD_LENGTH，不分配空间、不接受 payload | 业务消费状态并放弃该非法请求 |
| 合法请求但资源不足 | req_ready=0，请求 valid/长度保持 | 资源释放；或通道复位结束等待 |
| 第 L 字节前出现 last | abort，返回 BAD_LAST，该 last 已建立边界 | 消费状态 |
| 第 L 字节 last=0 | abort，返回 BAD_LAST，进入 DRAIN | 后续 last 握手或显式 cancel，且状态已消费 |
| COLLECT 中 cancel | 取消优先于 payload，abort，返回 CANCELLED | 消费状态 |
| DRAIN 中 cancel | 结束排空，不产生第二条结果 | 旧包残余被放弃，错误状态已消费 |

空闲且能够接收请求结果时，非法长度请求的 ready 不依赖缓存空闲量，不能因满缓存一直挂起。
源必须观察 status，不得在 BAD_LENGTH 后继续等 payload ready 或发送该包字节。

DRAIN 只握手并丢弃字节，不写 RAM、不累加无界长度、不接新请求，防止残余字节混入下一包。
cancel 仅在 COLLECT/DRAIN 可握手，cancel_valid 使同周期 payload_ready=0；取消握手定义源已
放弃当前包，允许撤回旧 payload valid。IDLE/STATUS 不接受 cancel，也不能取消已提交包。

不设置普通停顿超时。源永久停顿或不补 last 且不取消时，只停住 DATA TX 输入，不得占住共享
发送引擎或阻止已提交包、CONTROL 和 RX 工作。

## 8. 模块架构、状态机与可观测性

### 8.1 总体结构

```text
业务组包/源仲裁 -> TX 接入控制 -> DATA TX 字节环 + 描述符 --┐
CONTROL 核心 -----------------> CONTROL TX 队列 ----------┼-> 共享帧仲裁/TX engine
ARP -----------------------------------------------------┘       |
                                                        Ethernet TX FIFO -> MAC

MAC -> Ethernet RX FIFO -> 共享 RX parser
                              |-> CONTROL RX 队列 -> CONTROL 核心
                              └-> DATA RX 字节环 + 描述符 -> 业务接收接口
```

以上为功能划分，具体辅助 RTL 是否单列由状态所有权决定。公共网络封装、仲裁和存储不得在多个
模块重复实现；DATA 逻辑接口使用现有 125 MHz 域，不额外引入内部 CDC。

### 8.2 状态唯一所有权

| 状态 | 唯一所有者 |
|---|---|
| TX 接入状态、输入索引、取消及本地结果寄存器 | TX 接入控制 |
| 每方向候选预留、字节占用、读头/提交尾、描述符及预取状态 | 对应 DATA 报文 FIFO |
| payload 存储及 TX checksum 中间和 | DATA 报文 FIFO 的写入路径 |
| RX 网络字段、通道选择和最终检查结果 | 共享 RX parser |
| 当前发送帧选择、端口、长度和网络头 | 共享仲裁器/TX engine |
| Ethernet 帧存储、MAC 域状态、FCS 和链路错误 | Ethernet 层 |
| 事件计数与占用峰值 | 诊断逻辑，仅观察事件和状态 |

接入控制/parser 向 FIFO 发出 reserve、write、commit、abort；读口消费完成产生 release。
FIFO 统一更新自己的指针和计数，不由调用方同时保存另一套可写占用状态。

### 8.3 TX 接入状态机

| 状态 | 行为 | 离开条件 |
|---|---|---|
| IDLE | 等待请求；合法请求同时预留资源，非法长度生成结果 | 合法请求→COLLECT；非法请求→STATUS |
| COLLECT | 接收 payload，检查计数/last，允许取消 | 成功、提前 last 或取消→STATUS；末字节缺 last→DRAIN |
| DRAIN | 排空错误包；结果可独立被消费；不接受新请求 | 包边界恢复后，结果待消费→STATUS；结果已消费→IDLE |
| STATUS | 保持结果，不收新请求或 payload | 结果握手后→IDLE |

结果 valid 独立于 DRAIN 状态保持。DRAIN 的“边界恢复”和“错误结果消费”必须都完成才能开始
下一包；两者同周期发生也只完成一次恢复。复位统一回 IDLE，清空结果 valid。

### 8.4 最小诊断集合

| 类别 | 观测项 |
|---|---|
| RX | 提交、字节空间不足、描述符不足、校验/格式丢弃 |
| TX | 提交、非法长度、错误 last、取消、向 Ethernet FIFO 复制完成 |
| 缓存 | 各方向字节/描述符占用与峰值 |
| 公共链路 | reset/link-up、Ethernet overflow、错误/丢弃状态 |

资源不足同时满足时先归因字节、后归因描述符；一包只计一次主要丢弃原因，不按排空字节重复计数。
链路丢弃不产生第二条 TX 输入结果。DATA 提交计数与既有 tx_sent 统计分别保留，不混用语义。

### 8.5 FIFO 与发送引擎的内部契约

下表描述逻辑事务，信号最终命名可随 RTL 划分调整；每类事务只有一个产生者和一个存储所有者。

| 内部接口 | 契约 |
|---|---|
| reserve_valid/ready、reserve_len | 合法长度握手时一次预留整包及描述符；写入最早从下一周期开始 |
| write_valid、write_data | 已预留候选的单字节写事件；FIFO 此时必须能每周期接受一字节，不因描述符或剩余空间再次反压 |
| commit / abort | 单周期互斥事件，仅作用于当前候选；允许末字节 write 与 commit 同周期，abort 优先 |
| TX packet_valid、packet_len、packet_sum、packet_take | 描述符视图保持到一次 take；take 只锁定读包，不弹出描述符、不释放字节 |
| TX payload_valid/ready/data/last | take 后输出锁定包的字节流；末字节握手产生唯一 release，下一包须重新 take |
| RX 输出流 | 按第 5.1 节直接消费已提交头包，无业务侧额外 descriptor 握手 |

TX 接入控制在合法请求握手时产生 reserve，payload 握手时产生 write。RX parser 在 UDP 头阶段
完成一次准入；若失败立即锁存整帧丢弃，不保持 reserve_valid 等待资源。固定头格式下 UDP 长度
在 Ethernet 字节偏移 39 收齐，payload 从偏移 42 开始；预留必须在首个 payload 接受前完成，
若实现流水需要更多时间，应在头部边界短暂反压或使用明确的保持寄存器，不能漏掉首字节。

新提交描述符最早在提交边沿后的周期可见，不允许同周期越过队列直接读取尚未完成的 BRAM 写入。
commit 判定必须计入本周期末字节及最终 checksum；RX 帧尾后的 finalize 周期使用已更新的完整字段。
write 数量必须恰好为预留长度才可 commit，内部违约由断言检查；没有 reserve 的帧不发送 abort。

共享仲裁器交给 engine 的启动 descriptor 包含帧类型、UDP 源/目的端口、长度、payload_sum 和
TX checksum 使能。参数在启动握手时锁存，包头生成和 checksum 都使用这组端口，不能残留当前
engine 中固定为 CONTROL 端口的计算。固定主机 MAC/IP 继续来自公共配置。DATA 长度和 sum
来自 FIFO，端口/使能来自通道配置；不在 DATA 描述符 RAM 重复保存固定配置。

engine 输出 Ethernet/IP/UDP 头时不消费 payload。进入 payload 阶段后，输出 valid 随选中 FIFO
的 payload_valid，payload_ready 随 Ethernet TX ready；仅握手时推进字节索引。同步 BRAM 暂无
有效读结果时必须暂停，不能沿用现有地址读口“data 总是可用”的假设。首版共用 engine 采用这一
字节流契约，CONTROL 旧槽读口由适配器转换，不能直接把无 valid 的读数据接入 DATA 路径。

### 8.6 ARP 待发状态

现有 engine 内的 arp_reply_pending 随仲裁职责移到公共仲裁侧，只有一个所有者。固定主机配置下
重复 ARP 回复请求可合并为一个 pending 位；UDP 帧发送期间出现的请求必须保留。

```text
arp_pending_next = arp_reply_request || (arp_pending && !arp_start_fire)
```

新请求与旧 ARP 启动同周期时保留新 pending。已启动 ARP 在 engine 内独立收尾；pending 仅在
基础复位时清零，CONTROL 软复位不影响它。三路公平性针对待发帧，不承诺每个重复 ARP 请求各发一帧。

## 9. 复位边界

### 9.1 复位域

| 事件 | DATA 行为 | 公共逻辑与外部业务 |
|---|---|---|
| CONTROL watchdog 软复位 | 保持 DATA 候选包、队列、指针、预取及状态 | 不复位共享 parser/engine/Ethernet FIFO |
| 基础链路/通信复位 | 清理候选、已提交描述符、计数、结果和预取 valid | 公共传输建立空边界；生产者/消费者看到同一复位边界 |
| TX 显式取消 | 只处理第 7 节规定的未提交包或错误排空 | 不影响其他已提交包、RX 或公共引擎 |

基础复位期间不发生 DATA 业务握手。基础复位后生产者须重新请求，不能续传旧半包；消费者不得把复位前后的
字节拼成一包。reset/link-up 必须对业务可见，通信复位不决定外部 ADC/DDR 的采集和存储状态。

DATA 活动不刷新 CONTROL 500 ms 静默计时。watchdog 仍只由基础复位清零，输出原有 32 周期
软复位请求；实际 CONTROL 恢复还须等待通道清理完成，不能把这段固定脉冲直接连接整个 transport。

### 9.2 CONTROL 清理状态机

125 MHz 域增加 CONTROL 恢复协调状态，公共 parser、arbiter、engine 和 DATA 始终使用基础复位。
CONTROL 核心、寄存器适配器事务状态使用协调后的 CONTROL reset；产品寄存器值保持原边界。

| 状态 | 动作与退出条件 |
|---|---|
| RUN | CONTROL 正常收发；软复位请求到来即屏蔽新的 CONTROL 输入、RX 交付和仲裁选择，进入 DRAIN_CTRL |
| DRAIN_CTRL | CONTROL 核心保持复位，RX 队列清空；保留已经被仲裁器或 engine 引用的 CONTROL TX 包，继续复制到 Ethernet FIFO；无旧 TX 引用后进入 CLEAR_HOLD |
| CLEAR_HOLD | 至少一个时钟边沿清空 CONTROL TX 队列、候选包和读口预取；清理完成且 watchdog 软复位请求已释放后回 RUN |

恢复信号由协调状态保持，不因 watchdog 的 32 周期脉冲结束提前释放。旧 TX 引用包括
“descriptor 已声明 valid 但尚未握手”和“engine 正在输出本帧”两种情况；前者保持 descriptor
并完成原握手，后者保持 payload 读口，不受 CONTROL 核心复位影响。请求生效周期不再创建新的
CONTROL 引用。未被引用的旧排队包和半包可随 TX 队列最终清理一起丢弃。

安全收尾以帧尾复制进 Ethernet FIFO、引用解除为边界，不等 TEMAC 发完；已进入该 FIFO 的帧正常
排空。DATA/ARP 继续按共享仲裁规则运行；若已有 CONTROL 帧占着 engine，则只等待该帧正常收尾。
任何阶段遇到基础链路复位均按全局空边界处理，不继续等待旧引用。

### 9.3 RX 正在解析的帧

parser 为当前帧保留一个“禁止提交 CONTROL”标记：软复位请求撞上该帧，或该帧在 CONTROL
恢复期间开始解析时置位，持续到该帧 finalize 完成。端口尚未解析出来时也先记录，随后仅对
分类为 CONTROL 的帧生效；DATA 与 ARP 不受此标记影响。

CONTROL RX 队列清空时，同时撤销 parser 对其候选槽的预留所有权，屏蔽后续 write/commit/abort；
parser 仍消费该帧到 Ethernet last，不把剩余字节当成下一帧。恢复结束不重新准入这个旧帧。
软复位与帧尾/commit 同周期时，CONTROL 清理优先；DATA 的有效 commit 仍正常执行。

这里清理的是 CONTROL 队列及 parser 当前帧状态，不从共享 Ethernet FIFO 中抽取或删除指定端口。
线上包没有代际字段，迟到旧包的隔离仍依赖 CONTROL 既定的直连网络、主机完全静默 500 ms 加
100 ms guard 并清理旧 socket 的恢复约束；不承诺识别任意延迟后重新到达的旧数据报。

## 10. 接入现有工程

### 10.1 改造范围

| 接入点 | 工作 |
|---|---|
| udp_top / udp_transport_dual_host | 导出 CONTROL/DATA 独立消息接口与配置，连接各自队列 |
| fixed_host_rx_parser_dual | 按端口/长度选择队列、整包准入、按通道 commit/abort 与统计 |
| fixed_host_tx_engine_dual | 选择 ARP/CONTROL/DATA，锁存参数到帧复制结束 |
| DATA FIFO | 按第 6 节实现字节环、描述符、同步 BRAM 读口及所有权 |
| 长度/地址路径 | 替换相关固定 11-bit 长度和索引，按 payload 与整帧分别推导位宽 |
| Ethernet client FIFO / MAC | RX/TX FIFO 已从 4 KiB 扩到 16 KiB；MAC 已启用 Jumbo |
| ethernet_link_speed_ctrl | 通信就绪条件限定为已协商完成的 1G 全双工；其他速率不开放公共 FIFO 与 CONTROL/DATA |
| CONTROL 复位连接 | 从当前单通道 transport 复位中拆出通道边界，按第 9 节隔离 |

Ethernet client FIFO 是项目引入的可修改 RTL。实现已同步扩展地址、跨域指针、空满差值、状态
高位与 BRAM 地址宽度；MAC Jumbo 收发使能为 1。所有修改均在现有 `fpga/led/led.xpr` 内实施。

### 10.2 CONTROL 缓存边界

DATA 接入保留现有 CONTROL RX4/TX2 payload 槽环及最大 payload1472，不把 CONTROL 缓存缩为
16 Byte，也不把其容量自动扩为 Jumbo。DATA 独立使用第 6 节的可变包长字节环。

共享 parser 负责网络长度一致性和目标通道容量上限；CONTROL 是否恰好 16 Byte 仍由 CONTROL
decoder 判断。新 parser 整体具备 DATA8972 的解析能力，但端口32000 按 CONTROL1472 上限准入，
端口32001 按 DATA8972 上限准入。先以完整网络字段检查，再写对应队列，不能把整体解析上限当作
每路存储都能容纳的长度。

因此网络检查合格且在现有容量内的异常长度 CONTROL 包，仍走原槽环及 decoder 排空/统计路径；
watchdog 继续使用 CONTROL 的 rx_seen_event 或回复 load_fire，DATA 和 ARP 不提供活动事件。
W=4 是 CONTROL 事务窗口，与保留的 RX4 队列属于不同状态所有权。

### 10.3 TX 帧仲裁规则

采用带连续服务上限的 CONTROL 优先仲裁；ARP 与 DATA 在让出的机会中轮询。
CTRL_BURST_MAX=4 作为首版 RTL 默认，可综合期配置为正整数；它是调度参数，与 CONTROL 的 W=4 事务窗口无关，
最终数值通过并发吞吐和 CONTROL RTT 验证。此处定义选择算法，不是无限严格优先级。

仲裁单位为一帧，仅完整已提交的 CONTROL/DATA 包和完整待发 ARP 才具有资格。未收齐 DATA
不占公共引擎。基础链路可用且引擎能接受一个新 descriptor 时，按以下规则选择：

| 待发状态 | 选择规则 |
|---|---|
| CONTROL 待发，ARP/DATA 均无待发 | 发 CONTROL，不受连续额度限制 |
| CONTROL 与 ARP 或 DATA 同时待发，连续计数未到上限 | 发 CONTROL，实际启动握手后连续计数加 1 |
| CONTROL 与 ARP 或 DATA 同时待发，连续计数已到上限 | 让出一次给 ARP/DATA，启动握手后连续计数清零 |
| CONTROL 无待发 | 在 ARP/DATA 中选择，启动握手后连续计数清零 |
| 均无待发 | 空闲，不制造空包或等待不存在的请求 |

ARP/DATA 都待发时轮询；只有一路待发时直接选择该路。基础复位后轮询首选 ARP，每次非 CONTROL
帧启动握手后把下次首选移到另一路。两路均无待发时 CONTROL 连续计数清零，避免空载时期的
历史发送影响下一次竞争。选中但尚未握手时保持 descriptor 不变，不重复扣额度或推进轮询指针。
连续计数按作出选择时的竞争状态记录，在启动握手时更新；有未握手选择期间不因其他通道瞬时
变空而另行清零。源队列在 descriptor 已声明 valid 时即保留所引用的包，直至启动后发送完成，
或基础复位；CONTROL 软复位不能提前复用这一引用。

三路持续待发且额度为 4 时，服务序列为：

```text
CONTROL × 4 → ARP → CONTROL × 4 → DATA → 重复
```

只有 DATA 待发时连续发送 DATA，不等待 CONTROL/ARP，不为它们保留空闲周期。计数衡量帧数，
不是字节数或时间；一帧 DATA 可以是 Jumbo，一帧 CONTROL 很短，不代表固定带宽比例。

从 descriptor 启动握手到帧尾写入 Ethernet FIFO，选择和发送参数保持不变；中途反压只暂停当前帧，
不切换来源。帧复制完成后才重新仲裁，不等待逐包 TEMAC 完成。只保留一个公共仲裁器，
不在 engine 内再叠加独立的 ARP 优先级。持续可发送且出口持续取得进展时，各路都有服务机会。
Ethernet 的 tready 只表示当前字节可接受，不表示整帧剩余空间；不据此虚构整帧准入额度。
descriptor 启动后允许头部或 payload 等待 FIFO ready，输出 valid 不等待 ready 才声明。

### 10.4 共享出口与延迟

优先级只作用于当前仲裁时已经待发且尚未被选中的报文。CONTROL 未待发时继续选择 DATA；
后来到达的 CONTROL 排在已选中或已进入 Ethernet FIFO 的帧后面，属于正常发送顺序，不撤销
此前的选择，也不要求等待 MAC 发完上一帧再仲裁。

首版由 Ethernet FIFO 的有限容量和正常 ready/valid 反压约束积压，不额外设置出口在途帧额度，
不为调度增加 MAC 完成回传或消费计数。FIFO 本身所需的跨域空满控制继续保留。

按约 9 KB 帧估算，一帧在 1G 线路占用约 72 μs，尚不含其他排队和主机调度。CONTROL 的
2/4/8 ms 主机重试策略需在 1G Jumbo 并发场景回归，不以单帧线路时间代替端到端 RTT。
仲裁算法按第 10.3 节执行；连续服务上限的最终取值和实际排队下的 CONTROL 响应时间仍需集成验收。
若实测不满足明确的延迟目标，再评估针对性的调整，不把额外出口额度作为首版前置设计。

### 10.5 官方 Ethernet FIFO 扩容

采用在现有工程中扩展已引入的官方例程 RTL 的路线。当前 RX/TX client FIFO 与 RAM 源文件和
原生成例程一致，例程默认容量为 4096 Byte，源注释明确支持扩展地址以增加容量；重新生成相同
配置的例程不会自动得到 16 KiB FIFO。修改保持在现有 `.xpr`，不以重建官方例程为前置步骤。

| 对象 | 16 KiB 改造约束 |
|---|---|
| 存储及地址 | RAM 地址 12→14 bit；数据仍为 9 bit（8 bit 内容和 1 bit 帧尾），读写/帧首/回滚地址、地址差及切片一起修改 |
| 跨域空满 | 保留例程原有同步方案、读地址采样和安全余量；扩大实际跨域地址字段及比较位宽，不对二进制总线逐位随意增加同步器 |
| FIFO 内帧数 | 现有 RX rd_frames/TX wr_frames 为 9 bit，不能仅随 RAM 扩容后原样沿用；按例程最短 RX8/TX14 Byte 及读出流水容量推导，首版两侧保守使用 12 bit，并覆盖同时增减及计数回绕边界 |
| 状态及异常 | 空满、占用状态刻度、超长/坏帧回滚和 overflow 排空恢复均按新容量核对；导出当前未连接的 overflow 状态 |
| 工作模式 | 保持当前 FULL_DUPLEX_ONLY=1；保留例程要求的时钟频率关系及 RX 帧事件间隔，不把通用 FIFO 任意时序当作合法输入 |

“FIFO 内帧数”不同于“当前帧字节数”：前者计算排队帧数，后者计算一包长度。14 bit 是覆盖
9014 Byte 帧字节索引所需的宽度，不是要求帧队列计数一律 14 bit。12 bit 帧数是针对例程通用短帧
能力的保守配置，不表示本工程合法 UDP/ARP 流量在原 9 bit 下必然溢出。

overflow 在所属时钟域按一次溢出帧记录，跨域读取使用保持状态/计数快照，不直接采样单周期异步脉冲；
不因 overflow 清空另一条健康通道。TX 合法最大帧在正常反压下不得触发整帧过大丢弃。

MAC 已启用 RX/TX Jumbo，保持既有 MAC 生成/检查 FCS 及 padding 的模式；不把 FCS 加进 UDP
payload 或 parser 的长度预算。保留 max_frame_enable=0，不将 max_frame_length=0 误解为最大长度零。
Jumbo 开启会优先于自定义最大帧长配置，8972 的业务上限仍由 TX 准入和 RX parser 检查，不能依赖
MAC Jumbo 开关替代上限检查。依据：[PG051 MAC 配置](https://docs.amd.com/r/en-US/pg051-tri-mode-eth-mac/MAC-Configuration-Registers)。

例程依据：[RX FIFO](../../../fpga/led/led.srcs/sources_1/new/ethernet/temac_sgmii_tri_speed_rx_client_fifo.v)、
[TX FIFO](../../../fpga/led/led.srcs/sources_1/new/ethernet/temac_sgmii_tri_speed_tx_client_fifo.v)、
[MAC 配置](../../../fpga/led/led.srcs/sources_1/new/ethernet/temac_sgmii_tri_speed_config_vector_sm.v)。

### 10.6 1G 全双工链路准入

本版仅使用 1 Gb/s 全双工，CONTROL、DATA 和 ARP 共用这一通信就绪条件。不设计 10/100 Mb/s
下的正常数据传输、动态包长降级或低速 Jumbo，也不以支持这些模式为验收前提。

保留当前 PHY 铜口和 SGMII 自动协商流程及现有 IP。链路控制器在原有 core ready、链路有效、
协商完成和全双工条件之外，要求 `pcs_status_i[11:10] == 2'b10`，再完成 MAC 配置/复位握手后
声明 link_ready。现有 RTL 的 `negotiated_speed != 2'b11` 仍接受三种速率，集成时必须收紧，
不能只修改文档或在 MAC 中强写 1G 而忽略真实协商结果。

若协商为 10/100 Mb/s、半双工或链路未就绪，link_ready 保持 0，CONTROL/DATA 不发生业务握手，
公共 Ethernet FIFO 和 transport 按既有基础链路复位边界保持清空。运行中离开 1G 有效状态，
同样触发基础链路清理；返回 1G 后重新建立空边界。协商电路继续运行，原始 PCS 状态保留用于
诊断，不通过关闭自动协商或复位整个 PCS 来拒绝低速。

此策略不要求新增 PHY MDIO 配置，也不保证网卡物理状态绝不显示低速；低速连接对本系统属于
通信未就绪。业务侧继续使用现有 reset/link-up 判断可用性，无需另加动态 payload 上限接口。

当前 PCS/PMA v16.2 已配置 FPGA logic RX elastic buffer；1G 下其帧长预算覆盖本版 Jumbo，
完整 PHY/MAC/网卡链路仍按第 11 节验收。弹性缓冲与 Ethernet client FIFO 分属不同层，不能相互
替代。依据：[PG047 弹性缓冲](https://docs.amd.com/r/en-US/pg047-gig-eth-pcs-pma/SGMII-FPGA-Logic-Receive-Elastic-Buffer)。

## 11. 验证矩阵

### 11.1 报文与业务接口

| 场景 | 必须满足的结果 |
|---|---|
| 标准包、8172 默认包、8972 最大包、1 Byte 及奇数长度 | 长度/内容逐字节一致，checksum 正确 |
| 零长、超限、IPv4/UDP 长度不一致、checksum 错误、端点不匹配 | 不发布错误包；TX 非法请求返回明确结果，RX 排空 |
| 任意请求、数据、结果和 RX 输出反压 | 字段保持；不丢字节、不重复握手、不提前释放 |
| 提前 last、末字节缺 last | 按第 7 节回滚；残余字节不得进入下一包 |
| cancel 与末字节同周期、DRAIN 中 cancel | 取消优先；一包最多一条结果 |
| 状态先消费/包尾先恢复/两者同周期 | 均只在完整恢复边界后接受下一请求 |
| RX_REQUIRE 与 TX_ENABLE 独立组合 | 默认 1/1 保持双向校验；TX 关闭不改变 RX 策略，RX 接受零值时仍拒绝错误非零值 |
| 16-bit 非法网络长度高位、接近 65535 的长度字段 | 完整宽度拒绝，不因内部长度截断或加法回绕成为合法包 |

### 11.2 缓存所有权与复位

| 场景 | 必须满足的结果 |
|---|---|
| 3 个最大包、精确填满字节空间、16 个小包耗尽描述符 | 资源计算正确，下一包反压或整包丢弃 |
| 跨 2/4/8 KiB、环尾回绕、部分写入后 abort | 内容正确，已有包和读头不受影响 |
| reserve/commit/abort 与 release 同周期 | 第 6.2 节所有不变量成立 |
| BRAM 预取期间反压、末地址已发出但末字节未消费 | 不提前 release，不覆盖活动包 |
| 基础复位撞上输入、预取、结果反压、发送 | 无旧字节、旧结果或旧描述符进入复位后新包 |
| CONTROL 静默 500 ms，DATA 持续收发 | DATA 不被清空、不刷新 CONTROL watchdog；旧 CONTROL 不跨代提交 |
| CONTROL 复位撞上未握手 descriptor、TX 反压或 RX 端口尚未知 | 第 9 节引用保持与逐帧丢弃正确；32 周期结束不能提前复用旧 TX 存储 |
| write+commit、commit 后立即选包、TX 头部反压 | 末字节与 checksum 完整；首字节有效前不消费，不发生重复 release |

### 11.3 集成、性能与板级验收

- 无反压长包持续每周期读写 1 Byte，检查 BRAM 映射、资源和时序。
- CONTROL/DATA/ARP 并发、DATA RX 满载和 TX 积压，检查公平性、CONTROL RTT 及 Ethernet FIFO 反压。
- CONTROL 在 DATA 已被选中或入 Ethernet FIFO 后到达时，允许正常排队；下一次仲裁按当时的待发状态选择，
  不撤销或越过既有帧，不等待 MAC 完成反馈才继续工作。
- 三路持续待发、各路单独待发及动态加入/退出，检查第 10.3 节服务顺序；descriptor 反压期间
  选择稳定、计数不推进；长帧中途不得切换来源。
- ARP 请求撞上 UDP 发送或 ARP 启动，检查 pending 不丢失；交错发送两端口时分别核对 UDP 头与 checksum。
- 在 1G 全双工下验证并发吞吐、CONTROL RTT 和过载恢复，不出现永久停顿、半包或串包。
- 覆盖协商为 10/100 Mb/s 或半双工时不开放通信，以及 1G 丢失/恢复后的空边界；不要求低速传输验收。
- Ethernet FIFO 覆盖 16 KiB 环尾、连续短帧、超长/坏帧回滚、混合 CONTROL/DATA 帧、工作时钟域 CDC 及溢出恢复。
- 链路中断/恢复、Ethernet FIFO overflow 可观测；已提交包不重复产生输入结果。
- 在真实链路逐包核对标准包、8172/8972 payload 与超限行为，主机配置不能代替此项验收。
- 以测试寄存器 bank 和通用 DATA 发生/检查器集成，不以产品寄存器、ADC 或 DDR 接入为前提。

## 12. 实施状态与后续顺序

### 12.1 当前证据

DATA 已在共享工程完成 RTL、仿真、实现和板测。当前 `udp_top` 提供 CONTROL 32000 与 DATA
32001 两组业务接口；CONTROL 保留 RX4/TX2 固定槽，DATA RX/TX 各使用 32 KiB 字节环和 16 条
描述符。板级测试镜像为 `udp_data_test_top`。

已有 JavaScript 抽象所有权模型检查结果如下，仅验证分配、回滚、释放及数据所有权规则：

| 配置/检查 | 覆盖与结果 |
|---|---|
| B=64、最大包17、D=4，seed=0x5A170001，100000 步 | commit/release 各23871，abort10254，跨尾4201；commit+release4833，abort+release2063，通过 |
| B=32768、最大包8972、D=16，seed=0x5A170002，30000 步 | commit/release 各574，abort4619，跨尾842；独立 owner/data 数组检查有效字节，通过 |
| 定向边界 | 3 个最大包、精确满字节、跨尾 abort、16 小包满描述符及排空；reserve24、commit/release各23、abort1、拒绝3，通过 |

抽象模型之外，XSim 已覆盖 DATA ring、8172-Byte RX、8972-Byte TX、坏 checksum 丢弃和 CONTROL
复位隔离；1G-only 准入仿真也已通过。实现结果为 WNS `+0.371 ns`、WHS `+0.021 ns`、阻断 DRC=0。
实板已通过 1～8972 Byte 边界、256 个连续最大包、16 轮 CONTROL/DATA 共存和 watchdog 隔离。
详细命令、日志、bitstream hash 与当前测试边界见 `DEVELOPMENT.md`。

### 12.2 RTL 实现对应关系

实现保持本文定义的所有权边界，对应关系如下：

| 集成项 | 审核结论 |
|---|---|
| RX 分流和缓存 | `fixed_host_rx_parser_dual` + CONTROL 槽环 + `udp_data_rx_ring` |
| CONTROL 安全软复位 | `udp_transport_dual_host` 的 RUN/DRAIN/CLEAR/HOLD，只清 CONTROL ring/core |
| TX 共享路径 | `fixed_host_tx_engine_dual` + 两路 TX ring，CONTROL burst 上限 4 |
| Ethernet FIFO 与 MAC | 14-bit client FIFO 地址、16 KiB RX/TX、Jumbo RX/TX enable |
| 链路速率范围 | `ethernet_link_speed_ctrl` 只接受协商结果 `2'b10`（1G） |

原单端口 `udp_transport_fixed_host` 和回显顶层仍保留作历史回归入口；当前 DATA 构建使用双端口
transport，不复制第二套 Ethernet/IP/UDP 协议栈。

### 12.3 后续顺序

1. 接入实际 ADC/DDR/图像或 RTM 业务适配器，保持 DATA payload 契约不变。
2. 量化实际业务源突发、持续线速和业务侧跨时钟反压，决定 32 KiB/16 描述符是否需要调整。
3. 增加长时间 DATA 丢包率、DATA 满载时 CONTROL RTT/吞吐和链路反复重建测试。
4. 产品寄存器接入后重复 CONTROL/DATA 共存与 watchdog 隔离回归。

## 13. 设计基线与变更规则

透明 payload、整包可见、单包输入结果、提交与释放分离、错误回滚/排空以及 CONTROL/DATA
复位隔离构成本版功能契约。第 3.1 节集中定义首版参数，第 4～9 节定义接口与实现规则。

缓存容量与默认端口可以在参数约束内调整；包长上限改变时，须同步核对长度位宽、整包准入、
Ethernet FIFO、MAC 和主机/路径 MTU。共享调度、CONTROL 安全复位、链路扩容及 1G 准入按第 9～10 节实施，
不得在实现中静默改变本文已定义的业务语义。

后续修改直接修订对应章节，并同步相关架构文档、RTL、主机配置或验证向量，使当前设计只保留
一套一致的规则。
