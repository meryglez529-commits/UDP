# UDP 载荷报文槽环缓存

状态：`IMPLEMENTED_HARDWARE_VERIFIED`

2026-09-17：正在按 CONTROL/DATA 不同内容重评缓存组织与 Jumbo 扩展，尚未修改已验收 RTL。
本文件现有 RX4/TX2、1472-byte 数值仍描述当前实现；扩展边界见第 11 节。

## 1. 目标与归属

本设计单元为 `udp_transport_fixed_host` 提供 RX/TX 两个报文级载荷缓存。它只管理 UDP payload、
报文长度、TX payload checksum 中间和以及槽位所有权，不解析 Ethernet、ARP、IPv4 或 UDP 头，
也不承担 TEMAC 的 FCS、无反压接收和三速时钟适配职责。

当前 RTL 已将 RX/TX 收敛为同一种可参数化的**固定大小报文槽环**：RX 默认 4 槽，TX 默认
2 槽。深度为 2 的槽环就是乒乓缓存，因此实现不单独维护一套“乒乓”控制逻辑。旧的
`udp_rx_message_fifo` 和 `udp_tx_message_buffer` 已在完整回归通过后从工程与源码中移除。

## 2. 已选择的缓存组织

### 2.1 固定槽环，而不是可变长度字节环

每个槽最多保存一个 `MAX_UDP_PAYLOAD` 报文。写指针和读指针按槽号循环，槽长度单独保存。
默认参数为：

| 参数 | RX | TX |
|---|---:|---:|
| `MAX_UDP_PAYLOAD` | 1472 byte | 1472 byte |
| `SLOT_COUNT` | 4 | 2 |
| 数据面时钟 | 125 MHz `userclk2` | 125 MHz `userclk2` |

`SLOT_COUNT` 只允许不小于 2 的 2 次幂，使环形指针自然回绕。若未来确实需要非 2 次幂深度，
应显式增加边界回绕逻辑，不能依赖指针位宽溢出。

TEMAC 例程使用共享 4096-byte 字节环，按帧实际长度占用空间，并在坏 FCS 或溢出时把写地址
回滚到帧起点。这适合无 `tready` 的 MAC 接口和长度任意的 Ethernet 帧。本项目首版图像数据
预计主要使用接近 MTU 的 UDP 分片，固定槽环不会产生有意义的空间浪费，却可避免单帧跨 RAM
尾部、字节级空闲空间计算和可变长度描述符队列。

### 2.2 从 TEMAC FIFO 复用的原则

本设计复用以下事务原则，不复制 TEMAC FIFO 的 MAC 专用状态机：

- 数据先写入当前候选区域，帧尾检查通过后才 `commit`。
- 校验失败或输入协议错误执行 `abort`，候选槽保持不可见，写指针不前进。
- 读写指针分别拥有生产和消费进度，任何一方不得覆盖未释放槽位。
- 完整报文计数只由 `commit` 和最终 `release` 改变；两者同周期发生时数量不变。
- RX 满时仍然排空当前网络帧并记录分类丢包；TX 满时通过业务接口反压，不静默丢弃。

不复用 TEMAC 的 FCS `tuser`、半双工重传、MAC 无反压接收或跨三速 MAC 时钟逻辑。上述职责
继续保留在官方结构的 TEMAC RX/TX Ethernet FIFO 中。

## 3. 总体结构

```text
Ethernet RX FIFO
       |
       v
fixed_host_rx_parser -- speculative write --> udp_rx_payload_ring
       |                                         |
       +-- commit / abort -----------------------+--> 业务 RX 消息

业务 TX 消息 --> udp_tx_payload_ring -- committed slot --> fixed_host_tx_engine
                    |                                   |
                    +-- length + payload sum -----------+--> Ethernet TX FIFO
```

两个槽环均位于固定 125 MHz 数据面，不引入新的时钟域。TEMAC FIFO 仍负责 MAC client clock 与
`userclk2` 之间的跨域，因此本设计不使用 Gray pointer 或异步 FIFO 控制。

## 4. RX 槽环

### 4.1 所有权和提交

RX 维护 `write_slot`、`read_slot` 和 `committed_count`：

1. 新 Ethernet 帧开始时，解析器查询是否存在空槽，并锁存本帧是否拥有候选槽。
2. 对合法 IPv4/UDP 候选帧，只把 UDP payload 写入 `write_slot`；协议头不进入槽 RAM。
3. 帧尾统一检查固定端点、IPv4 长度/分片/头 checksum、UDP 长度和 UDP checksum。
4. 全部通过时写入该槽长度，推进 `write_slot` 并增加 `committed_count`。
5. 任一检查失败或无空槽时不推进 `write_slot`；下一候选帧可覆盖未提交内容。
6. 业务侧接受当前报文最后一个字节后推进 `read_slot` 并减少 `committed_count`。

业务侧只能访问 `[read_slot]` 指向的已提交槽。解析器只能写 `[write_slot]` 指向的候选槽。
除“满且同周期释放”这一允许复用的边界外，两者不得指向同一份有效所有权。

### 4.2 满载行为

当 `committed_count == SLOT_COUNT` 且业务侧本周期没有释放槽位时，RX 报告不可预留。解析器必须
继续接受并排空 Ethernet FIFO 给出的完整帧，但不写 payload RAM；帧尾产生一次
`DROP_FIFO_FULL`。同周期业务释放最后一个字节时允许新帧预留刚释放槽位。

## 5. TX 槽环

### 5.1 生产与发送并行

TX 维护独立的 `write_slot`、`read_slot` 和 `committed_count`。业务侧可以在发送引擎读取槽 N 的
同时填充槽 N+1，从而消除旧单槽实现中“先收完整 payload，再串行读出完整帧”的空泡。

1. 有空槽时接受消息描述符并锁存长度。
2. 按字节写入 `write_slot`，同时累计 one's-complement payload sum。
3. 实际字节数、声明长度和 `last` 一致时，提交 `{length, payload_sum}`，推进 `write_slot`。
4. 长度越界、提前 `last` 或延后 `last` 时 abort 当前槽并产生一次输入错误事件。
5. 发送引擎从最旧的已提交槽生成 Ethernet/IPv4/UDP 帧。
6. 只有该帧最后一个字节被 Ethernet TX FIFO 接受后才 `release` 并推进 `read_slot`。

默认双槽允许业务写入和帧发送各占一个槽；增大为 4 槽只提高突发吸收能力，不提高单字节数据
通路的峰值速率。

### 5.2 checksum 所有权

TX 槽环只保存 payload 累加和，不生成最终 UDP checksum。`fixed_host_tx_engine` 在取得槽长度和
payload sum 后加入 IPv4 伪首部与 UDP 头字段，生成最终非零 UDP checksum；IPv4 头 checksum
仍由发送引擎根据本帧 Identification 和长度生成。FCS 始终由 TEMAC 对最终 Ethernet 帧生成。

## 6. BRAM 与接口时序

payload RAM 必须推断为同步 Block RAM，不再接受大容量 payload 被实现为 Distributed RAM。
按默认深度估算：

| 缓存 | 有效载荷容量 | 预期 BRAM 量级 |
|---|---:|---:|
| RX 4 槽 | 5888 byte | 4 × RAMB18，等价 2 个 BRAM tile |
| TX 2 槽 | 2944 byte | 2 × RAMB18，等价 1 个 BRAM tile |

精确 primitive 数量以综合报告为准。实现可选择按槽分 bank 或使用统一双口地址空间，但必须满足
同周期一个生产写和一个消费读，并确保不会对同一有效槽产生未定义的读写冲突。

BRAM 同步读带来至少一周期读延迟。RX 业务输出和 TX frame engine 输入均需增加预取寄存器或
skid buffer，遵守以下约束：

- `valid=1 && ready=0` 时，`data`、`last` 和 `length` 保持稳定。
- 地址只在当前字节握手或安全预取时推进。
- TX Ethernet 输出受反压时，不重复或跳过 payload 字节。
- RX 最后一个字节被接受前，不释放对应槽位。

## 7. 与 TEMAC FIFO 的边界

本设计不删除或合并 TEMAC Ethernet FIFO。两层提交条件保持串联：

```text
TEMAC FCS good
    -> Ethernet RX FIFO 提交完整 Ethernet 帧
    -> IPv4/UDP parser 校验并提交完整 UDP payload
    -> 业务侧可见
```

后续集成同时应把 TEMAC `rx_fifo_overflow`、`tx_fifo_overflow` 以及可获得的坏帧事件接入统计，
与 UDP 层的 endpoint、IPv4、UDP checksum、oversize 和 slot-full 丢包分开计数。

只有在实测证明额外一帧时延或 BRAM 占用不可接受时，才另行设计把 MAC `tuser`、UDP 解析、
双时钟 RAM 和描述符 CDC 合并的缓存；该方案不属于本设计单元当前范围。

## 8. 参数与接口兼容

当前 RTL 模块为：

- `udp_rx_payload_ring`：默认 4 槽 RX 提交/回滚环。
- `udp_tx_payload_ring`：默认 2 槽 TX 生产/发送环。

`udp_transport_fixed_host` 对 `udp_top` 暴露的业务消息接口保持不变。内部可调整 parser/ring 和
ring/engine 接口以容纳同步 BRAM 预取，但不得改变 payload 字节顺序、报文原子性、错误分类和
固定端点策略。

## 9. 验证门槛

### 9.1 单元仿真

RX 至少覆盖：

- 1-byte、奇数长度和 1472-byte 报文提交；
- 4 槽写满、满时丢包、同周期 `commit + release`；
- 部分写入后 abort，下一帧覆盖候选槽且旧内容不可见；
- 写指针和读指针多次回绕；
- 业务数据反压下输出稳定；
- 连续报文保持顺序且无覆盖。

TX 至少覆盖：

- 业务填充一个槽时发送引擎并行读取另一槽；
- 两槽写满后的描述符反压及释放后恢复；
- 长度/`last` 错误 abort；
- 奇数长度 payload sum、1472-byte 边界及多次指针回绕；
- Ethernet TX 反压下数据稳定且每个槽只释放一次。

### 9.2 集成验证

1. 复用现有 `udp_transport_fixed_host_tb` 全部协议场景并增加连续双包/多包无空泡测试。
2. 展开 `udp_top` 与 `udp_echo_test_top`，确认同步 RAM 时序适配无组合环。
3. 综合确认 payload 主存储落入 RAMB18/RAMB36，且大容量 Distributed RAM 被消除。
4. 完成实现、时序和 DRC，再重新生成 bitstream。
5. 上板回归 14、256、1472-byte 回显，并增加连续最大包、突发包和长时间计数一致性测试。

## 10. 已完成的实施顺序

1. 建立 `udp_rx_payload_ring`、`udp_tx_payload_ring` 及各自 testbench。
2. 在不改变 `udp_transport_fixed_host` 外部端口的前提下替换当前两个缓存子模块。
3. 调整 parser 和 frame engine 的同步 BRAM 握手，完成协议回归。
4. 依次执行完整展开、构建和硬件回显；各流程通过后再淘汰旧实现与旧镜像身份。

上述四步已于 2026-09-11 完成；详细证据见 [`DEVELOPMENT.md`](DEVELOPMENT.md)。

## 11. 双通道与 Jumbo 扩展边界（设计中）

CONTROL/DATA 接口与集成提案见
[`../db500-udp-application/MODULE.md`](../db500-udp-application/MODULE.md)，DATA 业务接口见
[`../db500-udp-data/MODULE.md`](../db500-udp-data/MODULE.md)。缓存继续保持独立
设计单元，记录当前已验证的固定槽实现。DATA 已选择独立的字节环报文 FIFO，复用所有权原则，
不要求沿用本模块的固定槽组织；新缓存契约见 DATA MODULE.md 第 6 节，不叠加重复存储。

- CONTROL 优先评估紧凑的小记录队列；DATA 首版 RX/TX 各 32 KiB 字节环、各 16 条描述符，不沿用 RX4/TX2。
- 当前 `MAX_UDP_PAYLOAD` 虽为参数，长度、偏移和 slot_length 仍固定为 11 bit，尚不是真正的
  Jumbo 参数化接口。扩展时统一推导 `LEN_W=$clog2(MAX_UDP_PAYLOAD+1)`、槽内偏移和总 BRAM
  地址宽度，并检查上下游连接和加法中间值，不能只修改深度常数。
- 保留完整包提交、错误回滚、RX 满包丢弃、TX 请求准入与 ready-valid 反压语义。
- 业务交付完成发生在包提交时，不释放 payload 存储。内容被完整复制到 Ethernet TX FIFO 后才
  内部释放；不增加逐包 TEMAC 结果跟踪。commit 与 release 同周期仍需保持所有权正确。
- CONTROL 软复位不得清空 DATA 实例。CONTROL 已被公共发送引擎引用的槽应保留到安全收尾，
  再完成对应槽的复位清理，避免网络封装中途读到被清空或复用的数据。
- 扩容后验证跨 2 KiB/4 KiB 的地址、最大长度、奇数长度、指针回绕、同时提交/释放与同步 BRAM
  反压稳定；还需验证 Ethernet client FIFO，payload ring 通过不等于整条 Jumbo 路径通过。

已确认覆盖原工程默认 8172-byte payload；首版最大 payload8972，长度需 14 bit，DATA 容量按上述基线，
CONTROL 队列及综合资源预算另行确定。默认完整 MAC client 帧长 8214 Byte，已经超过 8 KiB，Ethernet FIFO
需独立按整帧上限扩容，不能把 payload 小于 8 KiB 当作整条路径可用 8 KiB 的依据。
不将当前 BRAM 利用率直接外推为扩展后结果。
