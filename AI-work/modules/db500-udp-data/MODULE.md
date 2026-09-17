# DB500 UDP DATA 通信设计

状态：`DATA_DESIGN_BASELINE_REVIEWED_RTL_PENDING`

## 1. 文档定位

本文描述 DB500 用户通信层中的 DATA 设计单元。它向业务侧提供双向、透明、保留报文边界的
UDP payload 通道，在现有 `udp_top/udp_transport_fixed_host` 中扩展实现。

DATA 的一包就是业务已经组好的一个 UDP payload。图像、RTM、ADC 或 DDR 提供的数据均作为
字节内容传递；已有的 12-Byte 业务头也是 payload 的一部分，DATA 不解释其字段。

本文定义业务接口、报文缓存、提交与释放、错误恢复以及接入现有 UDP 的要求。模块间关系见
[用户通信架构](../db500-udp-application/MODULE.md)，共享网络逻辑见
[UDP 设计](../udp/MODULE.md)，既有固定槽实现见
[payload ring 设计](../udp-payload-ring/MODULE.md)。

独立设计文档不要求增加同名 `db500_udp_data.v`。本文中的功能划分和逻辑接口用于指导实现，
尚未登记为 RTL 模块或端口；实施状态统一见第 12 节。

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
| 主机 | 沿用固定唯一主机配置，不引入运行时端口协商 |
| DATA 本地/主机 UDP 端口 | 默认 32001 / 32001，可综合期配置；须与 CONTROL 32000 区分 |
| DATA_RX_REQUIRE_UDP_CHECKSUM | 默认 1，RX 要求非零且正确的 UDP checksum |
| DATA_TX_UDP_CHECKSUM_ENABLE | 默认 1，TX 生成 UDP checksum；与 RX 配置独立 |
| IP MTU | 设计值 9000 Byte，实际 FPGA 与链路能力待验证 |
| MAX_DATA_PAYLOAD | 8972 Byte，即 9000−20−8；合法范围 1～8972，零长和超限拒绝 |
| 数据面 | 8 bit、125 MHz，每次握手 1 Byte；其他业务时钟域由边界适配器处理 |
| DATA RX / TX 字节容量 | 每方向 32768 Byte，分别参数化 |
| DATA RX / TX 描述符容量 | 每方向 16 条，包含活动读包及至多 1 条候选预留 |
| Ethernet RX / TX FIFO | 每方向 16 KiB 设计目标，扩容和跨域正确性需独立验证 |

超大业务报文由外部按公布的上限组包，UDP 层不自动拆包。8972 是本版设计范围，不表示原工程
所有运行模式均已覆盖，也不表示当前 FPGA 已支持 Jumbo。

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
只读核对，未修改网卡设置或发送测试包：

| 项目 | 查询结果 |
|---|---|
| 接口 | 以太网 2，ifIndex=4，ASIX USB to Gigabit Ethernet Family Adapter |
| 驱动高级属性 | JumboPacket，DisplayValue=9KB，RegistryValue=2（选项编码，不是字节数） |
| IPv4 IP MTU | NlMtu=9000 Byte |
| 查询时链路 | Disconnected |

主机 MTU 满足原工程默认包要求。9000 来自实际接口查询，不是从截图“9KB”推测；它仅支持
本版长度预算，不能代替 FPGA、PHY 和完整链路的 Jumbo 验收。

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

### 5.3 校验范围与方向配置

- 固定主机 MAC、IPv4、UDP 端点匹配，网络格式满足第 3.1 节。
- IPv4/UDP 声明长度与实际报文一致，payload 不超上限。
- IPv4 checksum 和底层 MAC 帧检查通过；默认要求 UDP checksum 非零且正确。
- UDP checksum 包括伪首部、UDP 头及 payload；Ethernet padding 不进入 payload 校验。
- 奇数字节只在校验运算中补零，不向 payload RAM 写入补零字节。
- TX checksum 运算必须包含末字节；计算结果为零时线上编码为 0xFFFF。

RX 要求与 TX 生成采用第 3.1 节两个独立的综合期参数，当前均为 1，不关闭 TX 校验和生成。
RX_REQUIRE=0 时仅允许接收零 UDP checksum；收到非零值仍必须校验，不能接收已知错误的 checksum。
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

## 9. 复位边界

| 事件 | DATA 行为 | 公共逻辑与外部业务 |
|---|---|---|
| CONTROL watchdog 软复位 | 保持 DATA 候选包、队列、指针、预取及状态 | 不复位共享 parser/engine/Ethernet FIFO |
| 基础链路/通信复位 | 清理候选、已提交描述符、计数、结果和预取 valid | 公共传输建立空边界；生产者/消费者看到同一复位边界 |
| TX 显式取消 | 只处理第 7 节规定的未提交包或错误排空 | 不影响其他已提交包、RX 或公共引擎 |

复位期间不发生业务握手。复位后生产者须重新请求，不能续传旧半包；消费者不得把复位前后的
字节拼成一包。reset/link-up 必须对业务可见，通信复位不决定外部 ADC/DDR 的采集和存储状态。

DATA 活动不刷新 CONTROL 500 ms 静默计时。CONTROL 软复位时，公共引擎已选中的 CONTROL
包保留有效存储到安全收尾，旧 RX CONTROL 候选在帧尾丢弃，禁止跨代提交；不得中途清空共享
状态。已进入 Ethernet FIFO 的旧 CONTROL 帧可以排空。

## 10. 接入现有工程

### 10.1 改造范围

| 接入点 | 工作 |
|---|---|
| udp_top / udp_transport_fixed_host | 导出 CONTROL/DATA 独立消息接口与配置，连接各自队列 |
| fixed_host_rx_parser | 按端口/长度选择队列、整包准入、按通道 commit/abort 与统计 |
| 共享帧仲裁器 / fixed_host_tx_engine | 单次 descriptor 握手选择 ARP/CONTROL/DATA，锁存参数到帧复制结束 |
| DATA FIFO | 按第 6 节实现字节环、描述符、同步 BRAM 读口及所有权 |
| 长度/地址路径 | 替换相关固定 11-bit 长度和索引，按 payload 与整帧分别推导位宽 |
| Ethernet client FIFO / MAC | RX/TX FIFO 从 4 KiB 按 16 KiB 目标扩展，验证跨域、回滚和帧计数；启用 Jumbo |
| CONTROL 复位连接 | 从当前单通道 transport 复位中拆出通道边界，按第 9 节隔离 |

Ethernet client FIFO 是项目引入的可修改 RTL，但扩容不等于只修改深度。现有 MAC Jumbo 收发使能
为 0，当前链路只验证到标准 MTU。所有修改均在现有 `fpga/led/led.xpr` 内实施。

### 10.2 CONTROL 缓存边界

CONTROL 固定 16-Byte 记录优先按紧凑小记录队列设计，DATA 按可变包长和吞吐设计，两者不共用
大槽方案。W=4 是 CONTROL 事务窗口，不等于网络 RX 队列深度。

CONTROL 队列若收紧为 16 Byte，必须保留异常长度统计和已定义的端口活动/watchdog 语义。
过长/过短 CONTROL 包的活动不能因缓存缩小被悄悄忽略；必要的端口活动事件由 transport 导出，
具体接口与队列容量仍需共同收敛。

### 10.3 TX 帧仲裁规则

采用带连续服务上限的 CONTROL 优先仲裁；ARP 与 DATA 在让出的机会中轮询。首版建议
CTRL_BURST_MAX=4，可综合期配置为正整数；它是调度参数，与 CONTROL 的 W=4 事务窗口无关，
最终数值通过并发吞吐和 CONTROL RTT 验证。此处定义选择算法，不是无限严格优先级。

仲裁单位为一帧，仅完整已提交的 CONTROL/DATA 包和完整待发 ARP 才具有资格。未收齐 DATA
不占公共引擎。引擎空闲且出口允许接纳下一帧时，按以下规则选择：

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

三路持续待发且额度为 4 时，服务序列为：

```text
CONTROL × 4 → ARP → CONTROL × 4 → DATA → 重复
```

只有 DATA 待发时连续发送 DATA，不等待 CONTROL/ARP，不为它们保留空闲周期。计数衡量帧数，
不是字节数或时间；一帧 DATA 可以是 Jumbo，一帧 CONTROL 很短，不代表固定带宽比例。

从 descriptor 启动握手到帧尾写入 Ethernet FIFO，选择和发送参数保持不变；中途反压只暂停当前帧，
不切换来源。帧复制完成后才重新仲裁，不等待逐包 TEMAC 完成。只保留一个公共仲裁器，
不在 engine 内再叠加独立的 ARP 优先级。持续可发送且出口持续取得进展时，各路都有服务机会。

### 10.4 共享出口与延迟

优先级只作用于当前仲裁时已经待发且尚未被选中的报文。CONTROL 未待发时继续选择 DATA；
后来到达的 CONTROL 排在已选中或已进入 Ethernet FIFO 的帧后面，属于正常发送顺序，不撤销
此前的选择，也不要求等待 MAC 发完上一帧再仲裁。

首版由 Ethernet FIFO 的有限容量和正常 ready/valid 反压约束积压，不额外设置出口在途帧额度，
不为调度增加 MAC 完成回传或消费计数。FIFO 本身所需的跨域空满控制继续保留。

按约 9 KB 帧估算，一帧在线路占用在 1G/100M/10M 下约为 72 μs/0.72 ms/7.2 ms，尚不含其他
排队和主机调度。CONTROL 的 2/4/8 ms 主机重试策略不能直接作为低速 Jumbo 场景的时延承诺。
仲裁算法按第 10.3 节执行；连续服务上限的最终取值和实际排队下的 CONTROL 响应时间仍需集成验收。
若实测不满足明确的延迟目标，再评估针对性的调整，不把额外出口额度作为首版前置设计。

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

### 11.2 缓存所有权与复位

| 场景 | 必须满足的结果 |
|---|---|
| 3 个最大包、精确填满字节空间、16 个小包耗尽描述符 | 资源计算正确，下一包反压或整包丢弃 |
| 跨 2/4/8 KiB、环尾回绕、部分写入后 abort | 内容正确，已有包和读头不受影响 |
| reserve/commit/abort 与 release 同周期 | 第 6.2 节所有不变量成立 |
| BRAM 预取期间反压、末地址已发出但末字节未消费 | 不提前 release，不覆盖活动包 |
| 基础复位撞上输入、预取、结果反压、发送 | 无旧字节、旧结果或旧描述符进入复位后新包 |
| CONTROL 静默 500 ms，DATA 持续收发 | DATA 不被清空、不刷新 CONTROL watchdog；旧 CONTROL 不跨代提交 |

### 11.3 集成、性能与板级验收

- 无反压长包持续每周期读写 1 Byte，检查 BRAM 映射、资源和时序。
- CONTROL/DATA/ARP 并发、DATA RX 满载和 TX 积压，检查公平性、CONTROL RTT 及 Ethernet FIFO 反压。
- CONTROL 在 DATA 已被选中或入 Ethernet FIFO 后到达时，允许正常排队；下一次仲裁按当时的待发状态选择，
  不撤销或越过既有帧，不等待 MAC 完成反馈才继续工作。
- 三路持续待发、各路单独待发及动态加入/退出，检查第 10.3 节服务顺序；descriptor 反压期间
  选择稳定、计数不推进；长帧中途不得切换来源。
- 对 1G/100M/10M 分别验证延迟预算；过载后能够恢复，不出现永久停顿、半包或串包。
- 链路中断/恢复、Ethernet FIFO overflow 可观测；已提交包不重复产生输入结果。
- 在真实链路逐包核对标准包、8172/8972 payload 与超限行为，主机配置不能代替此项验收。
- 以测试寄存器 bank 和通用 DATA 发生/检查器集成，不以产品寄存器、ADC 或 DDR 接入为前提。

## 12. 实施状态与后续顺序

### 12.1 当前证据

DATA 仍处于设计阶段，未开展其 RTL 仿真、综合或板测。当前工程保持单端口 32000、最大 payload
1472、RX4/TX2 固定槽及 CONTROL 测试寄存器实现，已有性能记录不证明 DATA/Jumbo 可用。

已有 JavaScript 抽象所有权模型检查结果如下，仅验证分配、回滚、释放及数据所有权规则：

| 配置/检查 | 覆盖与结果 |
|---|---|
| B=64、最大包17、D=4，seed=0x5A170001，100000 步 | commit/release 各23871，abort10254，跨尾4201；commit+release4833，abort+release2063，通过 |
| B=32768、最大包8972、D=16，seed=0x5A170002，30000 步 | commit/release 各574，abort4619，跨尾842；独立 owner/data 数组检查有效字节，通过 |
| 定向边界 | 3 个最大包、精确满字节、跨尾 abort、16 小包满描述符及排空；reserve24、commit/release各23、abort1、拒绝3，通过 |

这些结果不验证 ready-valid RTL 时序、错误状态机、同步 BRAM 映射、CDC、checksum 或硬件吞吐。
第 11 节仍是实施后的验收要求，不能据抽象模型宣称实现已通过。

### 12.2 后续顺序

1. 按本文接口、状态机与 FIFO 规则实现 DATA，并完成单元边界验证。
2. 收敛 CONTROL 小记录队列和仲裁连续服务上限，完成双通道、Jumbo 与复位隔离改造。
3. 在现有工程内集成测试寄存器 bank 和通用 DATA 检查器，执行第 11 节回归。
4. 检查综合资源和时序，再进行实际 Jumbo 与双通道板级验收。

## 13. 设计基线与变更规则

透明 payload、整包可见、单包输入结果、提交与释放分离、错误回滚/排空以及 CONTROL/DATA
复位隔离构成本版功能契约。第 3.1 节集中定义首版参数，第 4～9 节定义接口与实现规则。

缓存容量与默认端口可以在参数约束内调整；包长上限改变时，须同步核对长度位宽、整包准入、
Ethernet FIFO、MAC 和主机/路径 MTU。共享调度与 CONTROL 队列的未决项按第 10 节继续收敛，
不得在实现中静默改变本文已定义的业务语义。

后续修改直接修订对应章节，并同步相关架构文档、RTL、主机配置或验证向量，使当前设计只保留
一套一致的规则。
