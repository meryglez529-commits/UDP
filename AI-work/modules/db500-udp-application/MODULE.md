# DB500 UDP 用户通信架构

状态：`CONTROL_DATA_TEST_BANK_AND_JUMBO_VERIFIED`

## 1. 定位与当前阶段

本文件维护 CONTROL 与 DATA 的职责、业务接口和共享 UDP 传输层的集成设计。
2026-09-17 已明确：DATA 是透明的双向 UDP payload 通道，业务侧负责组织和解释 payload；
DATA 不承担图像分包、块身份、缺失检测、重传策略或有限对象提交协议。

当前 CONTROL V1、静默 watchdog、测试寄存器 bank、DATA 通道、差异化缓存、双端口隔离和
Jumbo Frames 均已完成 RTL、仿真、构建及板级验证。产品寄存器和实际 ADC/DDR/图像源接入暂缓。
本文件维护模块之间的集成设计；DATA 内部实现与证据归属独立模块文档。
本阶段链路工作范围已确定为仅 1G 全双工，CONTROL/DATA 共用这一就绪条件，10/100M 不开放通信。

- CONTROL 协议与实现：[CONTROL MODULE.md](../db500-udp-control/MODULE.md)
- DATA 接口与设计：[DATA MODULE.md](../db500-udp-data/MODULE.md)
- UDP 传输层与改造范围：[UDP MODULE.md](../udp/MODULE.md)
- 报文缓存设计：[payload ring MODULE.md](../udp-payload-ring/MODULE.md)
- 早期协议调研：[UDP_PROTOCOL_RESEARCH.md](UDP_PROTOCOL_RESEARCH.md)，仅作历史调研，
  其中块传输、重传和其他 CONTROL 候选方案不构成当前接口要求。

原工程只用来澄清边界和必要行为，不直接照搬模块划分、公共 FIFO 或业务耦合。
`db500_udp_application` 是架构归属名称，不表示已有同名 RTL。
DATA 单独维护设计文档，实现上在现有 UDP 工程内增加通路；是否需要同名 `db500_udp_data.v`
由接口适配与状态管理职责决定，不因独立文档而强制增加 RTL 外壳。

## 2. 所有权边界

| 所属层 | 负责内容 | 不负责内容 |
|---|---|---|
| 业务与数据源适配器 | 图像/RTM 组包、业务头、图像与文件身份、数据保存、补传、多个业务源之间的包级仲裁 | UDP/IP/Ethernet 封装与网络端口分类 |
| CONTROL 核心 | 固定 16-Byte QUERY/SET、W=4、去重/重放、寄存器访问握手 | 图像、DATA payload、公共发送仲裁 |
| DATA 通路 | 透明 payload 的包级接入与交付、反压、请求与本地结果管理 | 额外应用头、图像重组、判断 DDR 是否可重读、端到端可靠交付 |
| 共享 UDP 传输层 | 端口分类、独立通道队列、校验、网络封装、帧级仲裁及结果路由 | 解释 CONTROL 或 DATA payload 内容 |
| Ethernet 层 | TEMAC/PCS-PMA、FCS、MAC client FIFO、MAC 时钟域边界及 1G 链路准入 | 业务协议 |

DATA 所说的一包始终指一次 UDP payload，不是一帧图像或一个文件。业务头也是 payload 的一部分。
上下行采用相同边界：发送侧原样承接业务报文，接收侧原样交付通过网络校验的完整报文。
下行业务头、存储地址和对象完成由接收业务模块解释；通信层不因收到完整 UDP 包而激活业务。

```text
图像/RTM 组包 → 业务源 MUX → DATA 接口 → DATA TX 队列
CONTROL 核心 → CONTROL TX 队列
DATA TX 队列 / CONTROL TX 队列 / ARP → 共享仲裁与封装 → Ethernet TX FIFO → TEMAC

TEMAC → Ethernet RX FIFO → 网络校验与端口分类
                              ├→ CONTROL RX 队列 → CONTROL 核心
                              └→ DATA RX 队列 → DATA 接口 → 业务接收模块
```

ARP 属于共享网络服务，不进入 DATA payload 队列。原工程提到的 ICMP 不自动成为当前实现范围；
当前工程已实现 ARP/IPv4/UDP，若后续需要 ICMP，另行定义为网络层功能。

## 3. 已有基线与本阶段差异

“已有 UDP”特指本项目 `udp_top` 及其 transport，不是原工程 `lan_tx`。标准 MTU 单端口
`udp_transport_fixed_host` 仍作为回归模块保留；当前板级镜像使用 `udp_transport_dual_host`。

当前实现提供 `ctrl_rx/ctrl_tx` 与 `data_rx/data_tx` 两组逻辑接口。CONTROL 保持端口 32000，
DATA 的本地/主机端口默认均为 32001，可综合期配置；继续固定唯一主机，不引入运行时端口协商。
CONTROL 的线上 16-Byte 格式、W=4 及寄存器接口不因 DATA 改变。

Jumbo Frames 是已确认的新需求；至少兼容默认 8172-byte payload，对应 IP MTU 至少 8200。
当前主机已核对 JumboPacket=9KB、IPv4 MTU=9000；MTU9000/payload8972 已完成 FPGA 实板回环验收。

## 4. CONTROL/DATA 模块接口

CONTROL 的协议、业务寄存器接口和独立验收保持在 CONTROL MODULE.md。
DATA 已建立独立设计文档 [DATA MODULE.md](../db500-udp-data/MODULE.md)，其业务侧发送请求、
payload 握手、下行整包交付、结果顺序、取消和 Jumbo 默认兼容长度统一在该文档维护。

集成时 CONTROL 核心和外部 DATA 业务分别接到 UDP 独立逻辑通道，公共网络封装和仲裁由 UDP 负责。
DATA 交付完成以完整包通过输入检查并提交 TX 队列为边界，不等待 TEMAC；请求许可与缓存释放
另有明确语义。不为业务完成增加公共出口逐帧记录、token 或跨域完成回传。
CONTROL 与 DATA 的报文存储分别评估，各自保有唯一存储所有者，不叠加重复 payload 缓存。
完成与释放边界见 [UDP MODULE.md](../udp/MODULE.md) 第 7.5 节。

## 5. 缓存、仲裁与复位提案

### 5.1 独立队列与共享逻辑

CONTROL 与 DATA 各自拥有 RX/TX 队列及占用状态：CONTROL 保留现有 RX4/TX2、最大 payload1472
的槽环；DATA 已选择同步 BRAM 字节环+描述符 FIFO，RX/TX 各 32 KiB、各 16 条描述符。
既有 ring 的所有权原则可复用，DATA 不沿用 RX4/TX2 固定大槽。W=4 协议窗口也不等于网络 RX 队列深度。
DATA 首版参数与缓存规则见 DATA MODULE.md 第 3、6 节；CONTROL 异常长度/watchdog 注意项见第 10.2 节。

共享 parser 在 UDP 头阶段锁定逻辑通道并预留该通道的整包空间和描述符，帧尾只向该通道 commit/abort。
共享 TX 引擎按选中通道取得完整 payload、端口、长度和 checksum，选择保持到帧尾。
后续完整 DATA 包可以排队，未收齐的 DATA 包不占用公共帧发送引擎。

### 5.2 有界优先与出口排队

CONTROL 采用有连续服务上限的优先仲裁；存在其他待发帧时，首版 RTL 默认连续最多 4 帧 CONTROL，
随后让出一次给 ARP/DATA，两者轮询。无竞争时持续服务唯一待发通道，不留空额度。
具体选择、计数和握手规则见 DATA MODULE.md 第 10.3 节；额度最终值由并发验证确认，
它与 CONTROL 的 W=4 事务窗口无关。
ARP 待发位由公共仲裁侧唯一保存，请求与启动同周期时保留新请求；共享 engine 不再保存第二份
ARP 调度状态。启动 descriptor 与 payload 字节流契约见 DATA MODULE.md 第 8.5～8.6 节。

仲裁发生在完整帧之间，不打断已选中的 Jumbo 帧。Ethernet FIFO 中已经排入的 DATA 帧也不能被
后到 CONTROL 越过，这是正常排队。优先级只比较仲裁时已经待发且尚未选中的帧；CONTROL 未待发
时继续服务 DATA，帧复制进 FIFO 后即可重新仲裁，不等 MAC 发完上一帧。
首版采用 Ethernet FIFO 自身容量和 ready/valid 反压，不额外增加出口在途帧额度或 MAC 完成回传。
在 1G 下共同验证 Jumbo、正常 FIFO 积压与 CONTROL 超时；只有发现明确延迟目标未满足时再评估调整。

### 5.3 复位隔离

当前 CONTROL watchdog 清空整个单通道 transport；双通道后该连接必须拆分。CONTROL 静默不能
复位 DATA 缓存与接入状态、公共 parser/TX 状态机或 Ethernet FIFO，也不能由 DATA 活动续期。

CONTROL 恢复协调按 RUN→DRAIN_CTRL→CLEAR_HOLD 执行：先复位 CONTROL 核心并关闭新接入，
保留已经声明的 descriptor 和已选中 TX 包，待帧复制进 Ethernet FIFO 后清理 CONTROL TX 队列，
清理完成且原 32 周期软复位请求结束才恢复。CONTROL RX 队列可先清空，parser 对当前帧保留
“禁止提交 CONTROL”标记并继续走到帧尾；端口未解析时先记标记，后续若为 DATA 则正常处理。
已进入 Ethernet FIFO 的旧帧正常排空，不等待 MAC 完成。详细时序与同周期优先级见 DATA MODULE.md 第 9 节。

基础链路复位仍影响双方。DATA 内容是否保存、业务是否继续采集由外部决定；通信侧只清理报文状态。

## 6. Jumbo 兼容基线与分工

原工程默认业务数据 8160 Byte，加 12 Byte 业务头得到 UDP payload 8172 Byte；对应 IP 包 8200 Byte、
Ethernet 帧不含 FCS 8214 Byte、含 FCS 8218 Byte。链路 IP MTU 至少支持 8200 才能承载该默认包。
这些是新设计需要兼容的默认长度，不是全模式最大值。当前主机只读查询确认 JumboPacket=9KB、
IPv4 MTU=9000，足以满足默认包的主机 MTU 条件；查询时链路未连接，整条路径尚未完成 Jumbo 验收。
原工程 `0x0076` 可修改业务包长，用户另说明隔行模式可能重算包长；本版公布 8972-byte payload 上限，
更大业务报文须由外部重新组包，不保证覆盖原工程所有运行模式。

- DATA 模块维护业务侧长度契约、兼容场景与原工程证据，见 DATA MODULE.md 第 3 节。
- UDP 模块负责共享长度/帧计数、MAC 配置、Ethernet FIFO 扩展、通道集成与真实链路验证。
- 现有 payload ring 文档维护已实现缓存与复用边界；新通道缓存按差异化方案确定容量、位宽和提交/回滚。

默认 8214-byte 帧已超过 8 KiB，不能仅把 Ethernet 整帧 FIFO 从 4 KiB 扩到 8 KiB。
本项目当前仍是标准 MTU 基线，原工程的 Jumbo 使能不代表本工程已启用或验证。
不增加 IP 分片，也不在通信层自动把超大业务包拆成多个 UDP 报文。

Ethernet FIFO 在当前官方例程 RTL 上扩为 16 KiB，包含地址、帧数计数、CDC 与溢出恢复，
无需为该扩容重生成同配置例程。链路仅开放 1G 全双工，保留自动协商，低速协商结果按通信未就绪
处理；不增加低速 Jumbo 或包长降级。具体改造与准入规则见 DATA MODULE.md 第 10.5～10.6 节。

## 7. 集成验证顺序

1. 先验证双通道包级接口、合法/错误长度、逐字节反压、独立满槽和报文边界。
2. 扩大长度与 FIFO 后覆盖标准包、跨 2 KiB/4 KiB/8 KiB 边界的包、默认 8172 payload、最终最大 Jumbo、奇数长度和超限帧；
   checksum、BRAM 地址与计数不得在边界回绕。
3. 验证业务完成只对应本地包 commit；网络端另行比对每包 payload，覆盖 CONTROL/DATA/ARP 交错、
   输入状态反压、FIFO 溢出、中途链路断开及复位，确保无错误包提交、重复通知或存储提前释放。
4. 覆盖 CONTROL 500 ms 静默时 DATA 连续传输，以及软复位撞上 RX、TX、MAC 排队和包提交。
5. 在 1G 全双工下验证 DATA 满载时 CONTROL RTT、DATA 无饿死、正常 FIFO 排队/反压和标准包兼容性；
   同时验证低速/半双工不开放通信及 1G 重新建立后的恢复，不进行低速数据传输验收。
6. 使用测试寄存器 bank 和通用 payload 发生/检查器集成，再做构建和板测；不以真实产品寄存器、
   ADC 或 DDR 已接入为前置条件。

## 8. 设计基线与实施顺序

DATA 的长度上限、默认端口、FIFO、取消方式、错误编码、CONTROL 清理状态机及共享仲裁已形成
可实施设计，见 DATA MODULE.md 第 3～10 节。Ethernet FIFO 扩容范围也已明确，进入 RTL 后验证其
指针、帧计数、CDC 和恢复正确性。仲裁连续服务上限默认 4，性能验证后可调整。
1G 全双工工作范围已确定，低速不开放通信；本轮设计待定项已闭合，可进入 DATA 与共享工程接入的
RTL 实现，见 DATA MODULE.md 第 10.6、12.2 节。该状态不代表 RTL、Jumbo 或板级验收已经通过。

实施顺序：按已确定契约实现 DATA 缓存，保留 CONTROL 队列，再完成 Jumbo 路径、双通道分类与仲裁、本地提交状态
及复位隔离，随后按第 7 节验证。接口、缓存、出口仲裁和提交路径应作为同一集成设计审阅。
DATA 独立文档不强制同名 RTL。具体接入点、验证矩阵与实施顺序见 DATA MODULE.md 第 10～12 节，
扩展现有 UDP，按需求复用或调整缓存，不重复公共网络与存储逻辑。
