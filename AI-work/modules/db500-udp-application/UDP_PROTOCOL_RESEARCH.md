# UDP 工业通信方案调研与 DB500 协议设计启示

状态：`RESEARCH_FOR_REVIEW`

调研日期：2026-09-15

## 1. 文档定位

本文调研在 UDP/IP 之上构建的成熟工业、车载、机器视觉和实时通信方案，目的是为 DB500
用户协议提供设计依据。本文不是协议定稿，不替代同目录下的 `MODULE.md`，也不表示 DB500
要兼容或完整实现其中任何一个标准。

当前 DB500 业务仍按三类模型讨论：

| 业务类 | 核心目标 |
|---|---|
| `CONTROL` | 查询、设置或改变设备状态，明确请求是否被正确处理 |
| `OBJECT` | 有限大小的数据对象最终完整、正确地到达 |
| `STREAM` | 连续数据及时到达，并能识别顺序、位置和缺失 |

本次重点研究 `CONTROL` 的准确性与实时性矛盾，同时观察成熟方案如何将控制、对象和实时流分面，
为后续端口、队列和报文格式设计提供依据。

## 2. 当前工程条件

调研结论必须适配当前工程，而不能脱离实现条件：

- 固定上位机与 FPGA 的点对点/小型局域网通信，不需要互联网规模的服务发现和路由迁移。
- 1 Gb/s Ethernet，标准 MTU，当前 UDP 最大载荷为 1472 byte。
- FPGA 数据面工作在 125 MHz 字节接口；现有 RX 4 槽、TX 2 槽同步 BRAM 报文环。
- 当前链路已验证高吞吐，但 Windows 主机发送路径出现过外部报文倒序，因此应用层不能假定 UDP
  严格有序。
- FPGA 资源和状态机复杂度必须有明确收益，不能照搬面向通用计算机的完整中间件。
- 图像流与控制指令的数据量、失败代价和时效要求明显不同，不应强行使用同一种确认策略。

## 3. 先给出调研结论

成熟方案并没有形成一个统一的“可靠 UDP”答案。它们真正一致的地方，是先按语义拆开问题，
再为每种语义选择机制：

1. **事务型请求**使用请求标识、响应关联、超时和重复抑制。
2. **周期状态或实时 I/O**持续发布最新状态，使用序号判断新旧和丢失，不等待逐包确认。
3. **可靠数据传输**允许连续发送，通过历史缓存、缺失位图或范围请求选择性补传。
4. **长时动作**将请求已接收、动作执行中和动作完成分开表达，不让一个 RTT 阻塞整个控制通道。
5. **依赖关系**通过状态版本、配置代次、原子集合或显式前置条件表达，而不是默认所有请求
   stop-and-wait。
6. **资源始终有界**：在途事务数、去重记录、历史缓存、重试次数和超时均有上限。

对 DB500 最值得借鉴的不是某一个完整标准，而是以下组合：

- 借鉴 GigE Vision 和 EtherNet/IP 的**控制面与实时数据面分离**。
- 借鉴 SOME/IP 和 CoAP 的**请求类型、请求标识与响应关联**。
- 借鉴 EtherNet/IP、CoAP Observe 和 OPC UA PubSub 的**最新状态收敛**。
- 借鉴 DDSI-RTPS 的**连续发送、序号、有限历史和选择性缺失修复**。
- 借鉴 OPC UA PubSub Action 的**长动作状态机与重复请求处理**，但为 V1 大幅简化。

## 4. 评价维度

对每种方案主要考察以下问题：

| 维度 | 关注点 |
|---|---|
| 业务分面 | 控制、状态、实时流和大对象是否使用不同通道或模型 |
| 请求关联 | 如何把响应与请求对应，是否支持多个请求在途 |
| 顺序与新旧 | 如何识别倒序、重复、过期和丢包 |
| 可靠性 | 是逐包确认、累计确认、选择性重传、周期刷新还是不补传 |
| 副作用 | 重发时如何避免一次性动作被执行两次 |
| 长任务 | 回复是表示收到、开始、完成，还是另有任务状态 |
| 实时性 | 是否必须等待 RTT，是否产生队头阻塞 |
| 流控 | 发送者如何知道接收者和网络的承载能力 |
| FPGA 代价 | 所需缓存、查表、定时器、状态机和协议解析复杂度 |
| 合规与许可 | 是否能直接实现标准，还是只适合借鉴思想 |

## 5. GigE Vision：与 DB500 业务最接近的行业参照

### 5.1 核心结构

GigE Vision 是机器视觉行业标准，面向相机、图像设备与主机之间的控制和高速图像传输。
A3 公布的标准结构包含：

- `GVCP`：运行于 UDP/IPv4 之上的控制协议，用于设备控制、配置和流通道设置。
- `GVSP`：图像与其他流数据的传输协议。
- 设备发现机制。
- 基于 GenICam 的 XML 设备描述。

这意味着它从架构上就没有要求“控制指令”和“图像数据”共享同一种传输语义。A3 的公开资料
明确列出 GVCP 与 GVSP 是不同组成部分；GVSP 图像帧通常由 leader、若干 payload 和 trailer
组成，由主机按位置放入接收缓冲区。[A3：GigE Vision 标准组成](https://www.automate.org/vision/vision-standards/gige-vision-license-product-registration)
[A3：GVSP over UDP 的图像帧组织](https://www.automate.org/news/learn-why-udp-represents-the-optimized-gige-vision-approach-over-rdma-and-tcp)

### 5.2 解决思路

GigE Vision 的关键不是把 UDP 伪装成 TCP，而是让不同流量承担不同责任：

- 控制通道传递低带宽配置和动作请求。
- 图像流通道追求持续吞吐，每个数据包在帧中有明确位置。
- 发送端和接收端都围绕图像帧缓冲工作，丢失处理不阻塞所有控制事务。
- 设备描述与传输协议分开，主机可理解设备功能，但数据面保持紧凑。

### 5.3 对 DB500 的启示

1. `CONTROL` 与 `STREAM` 至少要形成独立逻辑通道；是否使用独立 UDP 端口可以后定，但不能
   共用一个会互相形成队头阻塞的单队列。
2. 图像流必须携带任务、帧、分包位置等标识，不能只靠 UDP 到达顺序恢复图像。
3. 控制回复延迟或重试不应暂停图像流；图像流拥塞也不应淹没停止、状态查询等控制消息。
4. 端口分离只是分类手段。真正的隔离还需要 FPGA 内独立接收队列、发送队列或至少有明确仲裁。
5. DB500 可以学习其分面架构，但不应未经许可复制 GigE Vision 的规范字段或宣称兼容。

### 5.4 不直接采用的原因

- 完整 GigE Vision 带有设备发现、GenICam 描述、相机功能模型和兼容性要求，超出 DB500
  当前目标。
- A3 明确要求用于商业合规产品开发时取得许可和完成产品登记，因此本文只把它作为架构参照。
  [A3：GigE Vision 许可说明](https://www.automate.org/vision/vision-standards/gige-vision-license-product-registration)
- 2026 年发布的 GigE Vision 3.0 新增 RoCEv2/GVRSP，目标是更高速率和低 CPU 占用；当前
  1 Gb/s FPGA/TEMAC 路径没有必要为此引入 RDMA NIC 和相应复杂度。
  [A3：GigE Vision 3.0 概览](https://www.automate.org/vision/vision-standards/vision-standards-gige-vision)

## 6. EtherNet/IP：显式事务与周期实时 I/O 分离

### 6.1 核心结构

EtherNet/IP 同时支持两类通信：

- **Explicit Messaging**：面向客户端/服务器事务，通常用于配置、诊断和建立连接，使用 TCP/IP。
- **Implicit I/O Messaging**：面向时间敏感的实时 I/O，使用 UDP/IP，可周期发送或采用生产者/
  消费者模型。

ODVA 的官方技术概览明确指出，实时 I/O 使用 UDP 以降低协议开销，并依靠连接机制检测交付
问题；配置和诊断则交给可靠的显式消息。[ODVA：EtherNet/IP Technology Overview](https://www.odva.org/publication_download/ethernet-ip-technology-overview/)

### 6.2 周期状态而非逐条握手

EtherNet/IP 的实时 I/O 不把每个值变化都当成必须完成一次 request/response 的事务：

- 周期模式按 Requested Packet Interval 生产数据，即使值没有变化也可以持续发送。
- Change-of-State 模式在值变化时发送，但仍周期性发送 heartbeat，避免接收端无法区分“没有
  新变化”和“发送端已经失联”。
- 报文序号用于检测丢包和倒序。
- 接收超时用于把通信中断转换成明确设备状态。

这些行为在 ODVA 的性能测试方法中有明确说明。[ODVA：EtherNet/IP Performance Test Methodology](https://jp.odva.org/wp-content/uploads/2020/05/PUB00081R1_Performance_Methodology_v1.0.pdf)

### 6.3 对 DB500 的启示

EtherNet/IP 给出的最重要答案是：**实时控制不一定等价于高速发送很多离散命令。**

若某类控制表达的是持续有效的目标状态，例如：

- 期望运行模式为 `RUN/PAUSE/STOP`；
- 期望束闸为 `OPEN/CLOSED`；
- 期望某组实时设定值为某一快照；

那么上位机可以周期或“变化立即发送 + 低频刷新”发布最新期望状态，FPGA 发布实际状态和
已应用版本。偶发丢包由后续状态刷新自然修复，不需要每次都等待 RTT。

这种模型把准确性从“每一包都收到 ACK”改成“设备实际状态最终与期望状态一致，而且主机能
观察到所应用的版本”。对于幂等 SET 和目标状态型 COMMAND，这比 stop-and-wait 更贴近工业
控制。

### 6.4 不能直接照搬的部分

- EtherNet/IP 的完整 CIP 对象模型、连接管理、设备配置和合规测试很重。
- 其可靠显式消息主要使用 TCP，而 DB500 当前底层只实现了固定端点 UDP。
- 因此 DB500 适合借鉴“事务面 + 周期 I/O 面”的划分，不适合为此完整实现 CIP/TCP 栈。

## 7. DDSI-RTPS：连续发送与选择性修复可以共存

### 7.1 核心结构

DDSI-RTPS 是数据分发服务的实时发布/订阅互操作协议，可在 UDP/IP 上运行。它区分 best-effort
和 reliable 通信，并围绕 Writer、Reader、序号和 HistoryCache 组织可靠传输。

可靠 Writer 不需要发送一条数据后停下来等确认。其典型机制是：

1. Writer 连续发送带序号的数据，并在有限 HistoryCache 中保留一段历史。
2. Writer 发送 `HEARTBEAT`，公布当前仍可提供的首尾序号。
3. Reader 根据已收到序号判断缺口，通过 `ACKNACK` 报告已确认范围和仍缺失的序号集合。
4. Writer 只修复被请求的数据；确认和修复可以合并，不要求数据与 ACK 一一对应。

OMG 规范明确说明 ACKNACK 可同时表达正确认与负确认，HEARTBEAT 用于公布可用序号范围并触发
缺失请求；响应还可以延迟或合并以避免消息风暴。[OMG：DDSI-RTPS 2.5](https://www.omg.org/spec/DDSI-RTPS/2.5/PDF)

### 7.2 Coherent Set

RTPS 还提供 coherent set：一组更新只有在完整收到后才向应用可见。它说明“多项更新要共同
生效”是独立于单包确认的业务语义，可以通过集合身份和结束标记表达，而不是靠每项参数之间
插入 RTT。[OMG：DDSI-RTPS 2.5，Coherent Sets](https://www.omg.org/spec/DDSI-RTPS/2.5/PDF)

### 7.3 对 DB500 的启示

- `STREAM` 或 `OBJECT` 可以连续发送，缺失修复不必退化成逐片 stop-and-wait。
- 固定大小的序号窗口加位图足以表达有限范围的缺失，不需要维护任意大乱序表。
- 发送缓存必须与可修复窗口严格对应；已经移出缓存的序号要明确报告不可修复。
- 多个参数需要共同生效时，可以使用“配置集合/配置代次 + 提交”表达，而不是把所有 SET
  都做成串行依赖。
- ACK/NACK 可以累计和合并，反馈频率无需等于数据包频率。

### 7.4 不直接采用的原因

完整 DDS/RTPS 包含参与者发现、GUID、Topic、QoS、Reader/Writer 状态、历史缓存和多播等大量
机制。它适合软件中间件和多节点系统，但对当前固定单主机 FPGA 明显过重。DB500 只应借鉴
序号、有限历史、心跳和选择性缺失修复的算法骨架。

## 8. AUTOSAR SOME/IP：业务语义清楚，但 UDP 本身不保证可靠

### 8.1 核心结构

SOME/IP 是车载以太网的服务化通信协议。服务可包含：

- `Method`：远程调用。
- `Event`：周期或变化时由提供者发送。
- `Field`：可以组合 getter、setter 和 notifier。

其公共头包含 Service/Method ID、长度、Client/Session ID、协议版本、接口版本、消息类型和
返回码。消息类型明确区分：

- `REQUEST`：要求响应。
- `REQUEST_NO_RETURN`：fire-and-forget。
- `NOTIFICATION`：通知，不要求响应。
- `RESPONSE`：成功响应。
- `ERROR`：错误响应。

[AUTOSAR：SOME/IP Protocol Specification R23-11](https://www.autosar.org/fileadmin/standards/R23-11/FO/AUTOSAR_FO_PRS_SOMEIPProtocol.pdf)

### 8.2 可靠性边界

SOME/IP 的语义分类很成熟，但它没有宣称 UDP request/response 自动成为“恰好一次”。AUTOSAR
规范把 UDP binding 定义为 `maybe` 可靠性：客户端等待一次响应超时，进一步的错误处理留给
应用；TCP binding 才提供其定义下的 exactly-once 传输语义。
[AUTOSAR：SOME/IP Protocol Specification R19-11，Communication Errors](https://www.autosar.org/fileadmin/standards/R19-11/FO/AUTOSAR_PRS_SOMEIPProtocol.pdf)

### 8.3 对 DB500 的启示

- 公共头应包含业务定位、请求关联、版本和结果码，但这些字段不能替代可靠性算法。
- `REQUEST`、`NO_RETURN`、`NOTIFICATION` 是传输交互类型；`QUERY/SET/COMMAND` 是业务动作
  类型，两者不是同一个分类维度。
- 周期状态可以采用 Event/Field notifier 思路，查询和设置则保持 request/response。
- 固定主机系统不需要完整服务发现；服务和方法标识可简化为业务类与操作码。

### 8.4 风险提示

如果 DB500 只复制 SOME/IP 的请求 ID 和响应格式，却没有超时重发、去重或状态收敛机制，
仍然只是“格式更规范的裸 UDP”，并没有解决指令是否真正生效的问题。

## 9. CoAP：确认模式、幂等语义和延迟响应的最小范例

### 9.1 核心结构

CoAP 是 IETF 为受限设备设计的 UDP 应用协议，使用短二进制头，并把消息传输与请求/响应关联
分开：

- `CON`：Confirmable，需要 ACK 或 RST。
- `NON`：Non-confirmable，不要求 ACK，但仍有 Message ID 用于重复检测。
- Message ID 关联 ACK/RST 并支持去重。
- Token 将响应与应用请求对应，因此多个请求可以被区分。
- GET 是安全且幂等的；PUT/DELETE 要求幂等；POST 通常不是幂等。

[IETF RFC 7252：CoAP](https://www.rfc-editor.org/rfc/rfc7252.html)

### 9.2 即时回复与延迟回复

CoAP 支持两种响应方式：

- 结果很快可得时，把业务响应直接放在 ACK 中，称为 piggybacked response。
- 结果不能马上得到时，先发空 ACK 停止请求重传，之后再以独立消息返回结果，称为 separate
  response。

这证明“确认已收到”和“业务结果已产生”可以分开，但分开后会增加双向状态、定时器和报文数。
对 FPGA 来说，只有当业务处理确实可能长于请求重传超时时才值得引入。

### 9.3 重复处理

RFC 7252 要求接收者对同一 Message ID 的重复 Confirmable 请求再次确认，但通常只处理一次。
对于天然幂等的 GET/PUT，规范允许用重复执行换取较少的缓存状态。

这个思想与 DB500 很契合：

- `QUERY` 可以安全重试。
- 表达明确目标值的 `SET` 应设计为幂等，可以重放。
- 一次性 `COMMAND` 不能靠“可能幂等”，必须有操作 ID 和去重记录。

### 9.4 为什么不能直接采用默认 CoAP 发送节奏

标准 CoAP 面向互联网与受限网络，默认 `NSTART=1`，即同一服务器通常只允许一个未完成的交互；
默认 ACK timeout 为秒级。这相当保守，不适合 DB500 亚毫秒 RTT 的专用千兆网控制路径。规范允许
针对受控环境修改参数，但增大并发和显著降低超时时必须同时保证拥塞安全并测量 RTT。

因此 CoAP 对 DB500 的主要价值是语义模型和去重规则，不是默认定时参数。

### 9.5 Observe 扩展

CoAP Observe 为状态通知定义递增序号；接收端即使遇到乱序，也应保留更新的表示。通知可按业务
选择 Confirmable 或 Non-confirmable，高频变化时还允许跳过中间状态，但必须让接收端最终看到
稳定后的最新状态。[IETF RFC 7641：CoAP Observe](https://www.rfc-editor.org/rfc/rfc7641.html)

这正是“状态收敛”而非“每次变化都可靠交付”的成熟表达。

## 10. OPC UA PubSub/UADP：状态新旧与长动作握手

### 10.1 序号和状态发布

OPC UA PubSub 的 UADP 映射是面向 UDP 等数据报传输的二进制发布/订阅方案。其 SequenceNumber
按模数递增，规范定义了回绕条件下判断新旧的方法；旧包或重复包应被忽略，长时间失联后再清除
旧序号上下文。
[OPC Foundation：SequenceNumber in headers](https://reference.opcfoundation.org/specs/OPC-10000-14/7.2.3)

这说明序号的用途首先是“判断新旧、定位缺失”，而不是自动等价于可靠交付。

### 10.2 UDP 上的 Action 状态机

当前 OPC UA PubSub 还定义了 Action Request/Response。Action 使用 `RequestId` 关联请求和响应，
并用三个核心状态描述长动作：

- `Idle`：等待请求。
- `Executing`：正在执行。
- `Done`：执行结束，结果可用。

在 UDP 等不可靠传输上，请求方会在发布周期到期且未看到相应状态时重发请求；响应方执行中
周期返回 Executing，完成后周期返回 Done，直到请求方回到 Idle 或超时。这是一种通过重复状态
报文让两端最终收敛的握手，而不是一次 ACK 后无限等待。
[OPC Foundation：Action execution sequence](https://reference.opcfoundation.org/specs/OPC-10000-14/6.2.11.2.2)
[OPC Foundation：Action request message](https://reference.opcfoundation.org/specs/OPC-10000-14/7.2.4.5.9)
[OPC Foundation：Action response message](https://reference.opcfoundation.org/specs/OPC-10000-14/7.2.4.5.10)

### 10.3 对 DB500 的启示

- 长任务不是靠延长普通 RESPONSE 超时解决，而应有可观察的执行状态。
- 重复请求必须用稳定的请求身份识别，不能重新创建动作。
- 执行中状态可以周期刷新，从而兼顾丢包恢复和主机可见性。
- 如果 V1 明确规定同类长任务最多一个，DB500 不一定需要通用任务表；可以让状态查询返回
  `last_start_request_id + task_state + result`。

### 10.4 需要克制的部分

OPC UA 完整信息模型、发现、安全和 PubSub 配置对当前 FPGA 过重。其 UDP Action 握手本身也比
当前 `COMMAND 启动 + QUERY 状态` 复杂。DB500 应先判断主动周期状态是否真的比上位机轮询更有
价值，再决定是否引入。

## 11. QUIC：通用可靠 UDP 的反例边界

QUIC 在 UDP 上实现连接、可靠传输、拥塞控制、流控、加密和多路 stream。多个 stream 可以并行，
避免不同 stream 之间由单一字节流造成的队头阻塞。[IETF RFC 9000：QUIC](https://www.rfc-editor.org/rfc/rfc9000.html)

它能解决通用网络上的大量传输问题，但不适合当前 FPGA 数据面：

- 必须实现 TLS 1.3 相关安全握手和数据保护。
- 需要复杂的连接状态、ACK 范围、丢失检测、拥塞控制、流控和包号空间。
- 它提供可靠有序字节流，不会自动理解配置代次、一次性动作、图像帧或过期数据。
- 当前是固定局域网端点，QUIC 的路径迁移和互联网拥塞适应收益很低。

因此 QUIC 可作为“不要重复发明通用可靠传输”的参照，但不是 DB500 FPGA V1 的现实候选。

## 12. 横向比较

| 方案 | 控制方式 | 实时数据方式 | 丢失/重复处理 | 长任务表达 | FPGA 适配评价 |
|---|---|---|---|---|---|
| GigE Vision | GVCP 控制/配置 | 独立 GVSP 图像流 | 流按帧和位置组织 | 取决于设备功能模型 | 架构最相关；完整兼容和许可成本高 |
| EtherNet/IP | 显式事务 | UDP 周期/COS I/O | 序号、超时、周期 heartbeat | 上层对象/控制逻辑 | 最适合借鉴期望状态/实际状态双向模型 |
| DDSI-RTPS | 数据发布/订阅 | best-effort 或 reliable | HistoryCache、Heartbeat、ACKNACK | 状态数据或 coherent set | 可靠算法有价值；完整栈过重 |
| SOME/IP | Method/Field request-response | Event/Notifier | UDP 仅 maybe；应用处理 | 由服务方法与应用定义 | 公共头和业务语义清楚，可靠性不足 |
| CoAP | CON/NON request-response | Observe 通知 | MID 去重、重传、Token 关联 | 空 ACK + separate response | 语义精炼；默认节奏不适用 |
| OPC UA PubSub | Action request/response | UADP 周期发布 | 序号、周期重复、状态收敛 | Idle/Executing/Done | 长任务模型可借鉴；完整栈过重 |
| QUIC | 多路可靠 stream | 多路可靠 stream | 完整通用传输恢复 | 应用自定义 | 对 FPGA V1 明显过重 |

### 12.1 共同点与差异

上述方案虽然名称不同，但底层机制可以归纳为四类：

| 机制 | 解决的问题 | 不解决的问题 |
|---|---|---|
| 请求 ID + RESPONSE | 请求关联、超时判断 | 物理动作是否真的完成 |
| 序号 + 最新值优先 | 倒序、重复、状态新旧 | 每个中间状态都完整到达 |
| 历史缓存 + NACK/位图 | 有限窗口内的丢失修复 | 超出缓存后的无限补传 |
| 周期刷新 + 超时 | 状态收敛、存活判断 | 一次性副作用的重复执行 |

因此任何 DB500 报文都不应只因为“带序号”就被称为可靠，也不应只因为“有 RESPONSE”就被
认为业务已经完成。协议字段必须和明确的状态机一起定义。

### 12.2 安全与功能安全边界

可靠传输、网络安全和设备功能安全是三个不同问题：

- 序号、超时、重传和去重处理的是偶发丢包、重复与倒序。
- 身份认证、完整性保护和防重放处理的是伪造或恶意报文；UDP checksum 不能承担这一职责。
- 束闸、激光、运动等危险状态不能只依赖应用层 UDP 成功率，仍应由硬件联锁、看门狗和失联
  默认安全状态保证。

EtherNet/IP 可通过 CIP Security 为 UDP 通信使用 DTLS，CoAP 规范也定义了 DTLS 安全绑定，
QUIC 则把加密和认证内置在传输中。
[ODVA：CIP Security](https://www.odva.org/technology-standards/distinct-cip-services/cip-security/)
这些完整机制对当前 V1 可能过重，但 DB500 在冻结协议前
仍需明确部署环境、可接入主机范围和防伪造要求，不能把“固定 IP/MAC”当成认证。

### 12.3 当前 RTT 数据对窗口的约束

现有工程测试中，64-byte UDP payload 的千兆线路时间约为 `1.04 us`，而 RTT p99 曾测得
`369.3 us`，更高请求负载下曾达到 `470.1 us`。因此严格 stop-and-wait 的瓶颈来自主机协议栈
和调度 RTT，而非线速发送时间。详见当前 [MODULE.md](MODULE.md) 的 3.2 节。

若先使用保守的 `0.5 ms` 设计 RTT 估算固定在途窗口，则有：

| 目标事务率 | 最小窗口 `ceil(rate × 0.5 ms)` |
|---:|---:|
| 1,000/s | 1 |
| 5,000/s | 3 |
| 10,000/s | 5 |
| 20,000/s | 10 |
| 50,000/s | 25 |

这个表只说明窗口量级，不代表最终需求。若实际控制峰值只有几百或一两千次每秒，`W=1~2`
可能已经足够；若将大量波形点或图元动作伪装成 CONTROL 指令，则再大的窗口也只是掩盖分类错误，
这类数据应重新判断是否属于 OBJECT 或 STREAM。

## 13. 对当前 CONTROL 分类的反推

当前 `QUERY / SET / COMMAND` 三级业务语义仍然合理，但还不足以单独决定传输策略。成熟方案表明，
真正决定策略的是“这条消息表达状态，还是表达一次性事件”。

### 13.1 QUERY

QUERY 无副作用，适合请求/响应、流水化发送和安全重试：

- 每个请求带稳定 `request_id`。
- 响应回显相同 ID。
- 允许有限数量请求在途，不因前一个 QUERY 的 RTT 阻塞下一个独立 QUERY。
- 返回值是某一时刻的状态快照，可附带 `state_version` 判断数据新旧。

### 13.2 SET

SET 表达目标值，天然适合幂等设计，但可以再按使用方式选择两种策略：

1. **低频配置事务**：参数组合成一个配置集合，以 `config_generation` 提交，响应返回实际应用的
   generation。适合扫描参数、ADC 配置和校准参数。
2. **实时期望状态**：发送最新目标快照并周期刷新；FPGA 只应用更新 generation，并回报
   `applied_generation`。适合会持续变化且中间值可以被新值覆盖的设定量。

二者都不要求逐参数 stop-and-wait。

### 13.3 COMMAND

现有 COMMAND 中混有两种本质不同的内容：

| 子性质 | 示例 | 合适策略 |
|---|---|---|
| 目标状态转换 | 运行、暂停、停止、束闸安全状态 | 尽量改写为“期望状态”，使其幂等并可重复发送 |
| 一次性动作 | 复位一次、采集一次、NEXT 一个图元 | `request_id/operation_id` 去重，重复包只重放结果 |

这不是要求新增一级业务分类，而是每个 COMMAND 必须标明是否为 `target-state` 或 `one-shot`，
否则无法正确制定重试行为。

### 13.4 长任务

长任务至少需要区分：

```text
请求被拒绝
请求已接受并进入任务状态机
任务仍在运行
任务已完成或失败
```

这不一定要求四种顶层响应。V1 仍可保持简单：

```text
COMMAND start(request_id, required_config_generation)
    -> RESPONSE OK(started, request_id)

QUERY task_state
    -> RESPONSE OK(last_start_request_id, RUNNING/COMPLETED/FAILED, result)
```

这样即时 RESPONSE 的定义是“启动动作已经完成，任务状态机已经建立”，不是“整个加工结束”。
只有未来证明轮询开销或完成延迟不可接受，才引入周期状态通知。

## 14. 解决“准确性与实时性”矛盾的候选架构

### 14.1 不再把问题理解为二选一

需要同时回答两个不同问题：

1. **实时发送是否必须等待上一条回复？** 对独立请求不必等待；对状态发布更不必等待。
2. **主机如何知道业务真的生效？** 通过已应用版本、实际状态或一次性动作结果确认，而不是仅看
   UDP 包是否被接收。

### 14.2 三种最小传输模式

建议后续协议只实现三种传输模式，而不是为每条业务定制状态机：

| 模式 | 适用业务 | 核心字段 | 发送规则 |
|---|---|---|---|
| `TRANSACTION` | QUERY、低频 SET、one-shot COMMAND | session、request_id、opcode | 有限并发，逐事务响应，超时同 ID 重发 |
| `STATE_SYNC` | 高频目标状态、设备实际状态 | source、state_version、generation | 变化立即发 + 周期刷新，只接受更新版本 |
| `DATA_TRANSFER` | OBJECT/STREAM | object/stream、sequence、position | 连续发送，按业务选择不补传或选择性补传 |

业务分类仍然是 CONTROL/OBJECT/STREAM；上表是其底层可复用传输机制，两者不要混为一层。

### 14.3 参数先设置、随后启动的依赖问题

“先设好参数再开始加工”不等于网络上每个 SET 都必须 stop-and-wait。可以使用配置代次作为
前置条件：

```text
CONFIG_SET(generation = 37, 参数集合)
START(required_generation = 37, request_id = 1001)
```

上位机可以连续发送两包。FPGA 只在 `applied_generation == required_generation` 时执行 START。
若因 UDP 倒序导致 START 先到，有两种实现：

- 简单方案：返回 `PRECONDITION_NOT_MET`，主机在收到配置确认后重发同一 START。
- 复杂方案：FPGA 暂存 START，等待所需 generation 到达或超时。

V1 更适合简单方案。正常无丢包时没有逐条 RTT 间隔；异常时才付出一个重试 RTT，同时不会在
错误配置下启动。若配置与启动总是成组且需要一次生效，也可把它们放入同一批量事务。

### 14.4 一次性动作的 exactly-once 边界

UDP 重试最多能在应用层实现“至少一次送达尝试”；要让副作用只发生一次，必须由设备执行去重：

```text
identity = session_epoch + request_id
```

FPGA 对相同 identity 的行为应为：

- 内容相同：不再次执行，重放原 RESPONSE。
- 内容不同：返回 `REQUEST_ID_CONFLICT`。
- identity 已超出去重保存期：按协议定义返回 `STALE_REQUEST`，而不是盲目执行。

去重缓存深度至少覆盖允许的在途窗口和最大重试周期。由于当前 TX 只有两个完整报文槽，不应假设
可无限缓存响应；可以缓存小型结果元数据，再按需重新生成响应。

### 14.5 回复语义

建议继续保持“RESPONSE 本身就是事务确认，不另加通用 ACK”，但必须为每个 opcode 定义 OK
达到的具体生效点：

- QUERY：快照已经取得。
- 配置 SET：配置已验证并应用，返回 `applied_generation`。
- 目标状态 SET/COMMAND：期望状态已接收，若需要区分实际状态则同时返回 current/actual state。
- one-shot COMMAND：该一次性动作已执行或已建立长任务状态机。
- 长任务完成：通过 QUERY 或后续状态通知观察，不让初始 RESPONSE 等待整个任务。

只有当某个请求的验证本身就可能长到触发网络重传时，才评审 CoAP 式“先 ACK、后结果”。

## 15. 端口与队列设计启示

### 15.1 端口建议尚不冻结

从成熟方案看，将不同流量放到不同 UDP 端口有明显好处：

- 接收解析可以在较早阶段分类。
- Windows socket 缓冲、线程和优先级可以分别配置。
- FPGA 可为 CONTROL、OBJECT、STREAM 分配不同队列和溢出策略。
- 抓包、诊断和带宽统计更清楚。
- 图像流高负载时更容易保护控制通道。

但端口号本身不提供可靠性、优先级或隔离。如果最终仍进入同一 FPGA FIFO 并由同一发送队列
先来先服务，端口分开也无法避免队头阻塞。

### 15.2 候选分面

后续可以评审以下最小分面，而不是现在冻结端口号：

| 逻辑面 | 可能承载内容 | 队列要求 |
|---|---|---|
| Control Transaction | QUERY、配置提交、one-shot COMMAND、回复 | 小包、低延迟、不可被数据流饿死 |
| State Sync | 期望状态、实际状态、heartbeat | 最新值优先，可覆盖旧待发状态 |
| Object Transfer | 有限对象分片、提交、缺失修复 | 较深缓存，允许暂停和重传 |
| Real-time Stream | 图像/RTM 数据 | 高吞吐，过期数据按流模式丢弃或标缺 |

V1 是否把 State Sync 独立成端口，要由实际更新频率决定；低频时可以与 Control Transaction
共用端口和公共头，但在 FPGA 内仍应能区分调度优先级。

## 16. 不建议采用的方案

### 16.1 所有 CONTROL 全局 stop-and-wait

优点是实现直观，但每个独立请求都支付 RTT，吞吐随主机调度尾延迟下降；它还把业务依赖和
网络节奏混为一谈。可保留为调试模式或窗口 `W=1` 的降级模式，不宜作为默认能力上限。

### 16.2 所有 CONTROL 全部 fire-and-forget

无法知道设备是否收到、是否拒绝、是否应用，也无法安全处理一次性副作用，不满足加工与扫描
启动前的确定性要求。

### 16.3 每个阶段都增加一种回复类型

统一定义 RECEIVED/ACCEPTED/APPLIED/COMPLETED/FAILED 看似完整，但会让所有简单指令承担长任务
复杂度。更合理的是顶层保持简洁，由具体操作定义 RESPONSE 的生效点，长任务使用状态查询。

### 16.4 直接实现完整 DDS、OPC UA、SOME/IP 或 QUIC

这些标准解决多节点互操作、发现、安全和通用网络问题。当前固定主机 FPGA 的收益不足以覆盖
资源、验证和维护成本。借鉴机制应有明确边界，避免形成一个无法完整合规的“半套标准”。

### 16.5 只按端口区分而共享单一拥塞点

如果端口最终汇聚到同一个无优先级队列，图像流仍会阻塞控制回复。端口、缓存所有权、丢弃规则
和发送仲裁必须作为一个整体设计。

## 17. 建议的后续评审顺序

调研之后不宜立即画公共包头，应按以下顺序冻结决策：

1. 逐项标记现有 CONTROL opcode：QUERY、幂等 SET、目标状态 COMMAND、one-shot COMMAND、
   长任务启动。
2. 找出哪些 SET 必须成组生效，定义最小 `config_generation` 规则。
3. 找出哪些状态需要周期同步；若没有高频目标状态，V1 可以暂不实现独立 STATE_SYNC。
4. 给出 CONTROL 峰值请求率和最大允许在途数，确定固定窗口，而不是凭经验选 W。
5. 定义 session、request_id、去重保存期、超时和异常重启后的行为。
6. 确定端口与 FPGA 队列是否真正隔离，尤其是控制回复对 STREAM 的抢占规则。
7. 再分别为 OBJECT 和 STREAM 选择序号宽度、缺失策略和补传机制。
8. 最后冻结公共头、各类子头和 RTL 模块边界。

## 18. 当前推荐结论

就现有信息，最值得进入下一轮评审的不是“批量事务或固定窗口二选一”，而是以下混合策略：

1. CONTROL 的普通事务采用**有界流水 request/response**，独立请求无需等待上一条回复。
2. 多项相关配置采用**配置集合 + generation**；启动命令携带 required generation，显式表达
   依赖。
3. 可改写为目标状态的 COMMAND 尽量做成**幂等状态收敛**，不作为不可重复脉冲命令。
4. 真正的一次性 COMMAND 使用**session + request_id 去重**，重复请求只重放结果。
5. 长任务保持**启动即时回复 + 状态查询**；是否升级为周期状态通知由实际需求决定。
6. CONTROL、OBJECT、STREAM 采用独立逻辑面；是否使用 3 个或 4 个 UDP 端口在队列与仲裁方案
   明确后决定。

这个方案同时吸收了成熟协议的核心经验，又避免在 V1 引入通用发现、动态 QoS、无界乱序、
复杂 ACK 层和完整中间件。

## 19. 一手资料索引

以下均为标准组织或 RFC Editor 的原始资料，调研未以二手博客作为协议结论依据：

- [A3：GigE Vision Standard](https://www.automate.org/vision/vision-standards/vision-standards-gige-vision)
- [A3：GigE Vision 标准组成与许可](https://www.automate.org/vision/vision-standards/gige-vision-license-product-registration)
- [A3：GVSP over UDP 说明](https://www.automate.org/news/learn-why-udp-represents-the-optimized-gige-vision-approach-over-rdma-and-tcp)
- [ODVA：EtherNet/IP Technology Overview](https://www.odva.org/publication_download/ethernet-ip-technology-overview/)
- [ODVA：EtherNet/IP Performance Test Methodology](https://jp.odva.org/wp-content/uploads/2020/05/PUB00081R1_Performance_Methodology_v1.0.pdf)
- [ODVA：CIP Security](https://www.odva.org/technology-standards/distinct-cip-services/cip-security/)
- [OMG：DDSI-RTPS 2.5 规范页](https://www.omg.org/spec/DDSI-RTPS)
- [OMG：DDSI-RTPS 2.5 PDF](https://www.omg.org/spec/DDSI-RTPS/2.5/PDF)
- [AUTOSAR：SOME/IP Protocol Specification R23-11](https://www.autosar.org/fileadmin/standards/R23-11/FO/AUTOSAR_FO_PRS_SOMEIPProtocol.pdf)
- [AUTOSAR：SOME/IP Protocol Specification R19-11](https://www.autosar.org/fileadmin/standards/R19-11/FO/AUTOSAR_PRS_SOMEIPProtocol.pdf)
- [IETF RFC 7252：The Constrained Application Protocol](https://www.rfc-editor.org/rfc/rfc7252.html)
- [IETF RFC 7641：Observing Resources in CoAP](https://www.rfc-editor.org/rfc/rfc7641.html)
- [OPC Foundation：OPC UA Part 14 PubSub](https://reference.opcfoundation.org/specs/OPC-10000-14/)
- [OPC Foundation：Action execution sequence](https://reference.opcfoundation.org/specs/OPC-10000-14/6.2.11.2.2)
- [IETF RFC 9000：QUIC](https://www.rfc-editor.org/rfc/rfc9000.html)
