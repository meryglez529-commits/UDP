# UDP 全链路性能测试方案

状态：`HARDWARE_PERFORMANCE_10MIN_PASS_WITH_KNOWN_REORDER_GAP`

## 1. 目标

本方案验证 DB500 固定上位机 UDP 通路在真实千兆链路上的持续吞吐、短包包率、突发承载、
丢包行为、时延和全双工能力。测试对象为：

```text
上位机 UDP socket
    -> 1000BASE-T 网卡/双绞线
    -> M88E1111 PHY
    -> SGMII RX
    -> PCS/PMA
    -> TEMAC RX Ethernet FIFO
    -> fixed_host_rx_parser
    -> udp_rx_payload_ring
    -> udp_payload_echo
    -> udp_tx_payload_ring
    -> fixed_host_tx_engine
    -> TEMAC TX Ethernet FIFO
    -> PCS/PMA
    -> SGMII TX
    -> M88E1111/上位机
```

本方案不只测试 SGMII 串行线速率。SGMII 在 1000M 模式下以 1.25 Gbit/s 传输 8b/10b 编码
符号，而 UDP/TEMAC 数据面是 8 bit × 125 MHz，即 1 Gbit/s 的 MAC 字节流。真正需要验证的是
这条字节流经过帧开销、整帧缓存、checksum、握手和软件栈后能交付多少有效 UDP payload，
以及接近极限时是否产生可解释的丢包、乱序或停滞。

## 2. 当前已知结论与尚未验证项

当前已经确认：

- 1 Gbit/s、full-duplex 链路能够建立。
- 14、256、1472-byte 单包 UDP 回显内容正确。
- RX 4 槽、TX 2 槽的提交、回滚、反压和同步 BRAM 行为通过仿真。
- `udp_echo_test_top` 已完成实现和板级下载。

尚未确认：

- 长时间连续流量的最大无损吞吐。
- 不同 payload 长度下的最大无损 packet rate。
- RX 4 槽、TX 2 槽与 TEMAC FIFO 组合后的真实突发承载能力。
- 满载时的 RTT 分布和抖动。
- 过载后的丢包位置、计数一致性以及无需复位的恢复能力。
- 当前 Windows/Python 流量发生器能否先于 FPGA 达到目标速率。

现有 `test_udp_echo.py` 使用“一包发送、一包等待”的 stop-and-wait 模式，只用于正确性和单次
主机可见 RTT 检查，不作为吞吐测试结果。

## 3. 指标定义

指标数量不等于独立测试数量。性能报文携带运行标识、序号、时间戳和确定性内容后，同一次连续
收发即可同时计算吞吐率、PPS、丢包、重复、乱序、内容错误和主机可见 RTT。Ring level、drop
reason 和 TEMAC FIFO overflow 主要用于异常归因，不需要在黑盒结果正常时单独运行一轮测试。

### 3.1 指标、目的与测试方法总表

| 指标 | 回答的问题 | 为什么要测 | 怎么测 | 最适合的层级 | 当前定位 |
|---|---|---|---|---|---|
| Payload 内容和长度 | 收到的数据是否与发送数据完全一致 | 检查 BRAM 地址、槽位覆盖、长度、`last`、checksum 和回显搬运是否破坏数据 | 每包生成确定性内容，按 `run_id + sequence` 重建期望值并逐字节比较 | RTL + 板级黑盒 | 强制验收 |
| UDP payload goodput | 每秒真正交付多少业务数据 | 检查解析、整帧缓存、checksum、echo 和封装流水线能否跟上千兆链路 | 独立 sender/receiver，在固定测量窗口累计有效 payload bytes | 板级黑盒 | 强制验收 |
| PPS | 每秒能处理多少个完整 UDP 数据报 | 小包带宽不高，但每包都产生一次解析、descriptor、commit、release 和状态切换，可暴露固定的逐包开销 | 与吞吐测试同时计数；使用短包观察 PPS，使用长包观察 bit/s | RTL + 板级黑盒 | 随同采集；极限值按业务需要 |
| 丢包 | 缓存或处理能力不足时有多少完整数据报未返回 | 吞吐率很高仍可能伴随不可接受的丢包；这是判断无损工作区间的关键指标 | 发送结束并 drain 后，用本轮已提交 sequence 集合与唯一接收集合求差 | 板级黑盒；内部计数负责归因 | 强制验收 |
| 重复 | 同一个数据报是否被交付两次 | 当前单通路不会有意复制报文，重复通常指向握手、读指针或槽位释放错误 | 统计同一 `run_id + sequence` 的第二次及以后接收 | 与其他黑盒测试同时完成 | 强制记录，正常值必须为 0 |
| 乱序 | 报文是否按发送顺序返回 | 当前 ring 和发送引擎均应保持顺序；乱序可能表示指针或所有权管理错误 | 记录最高已接收 sequence，识别晚于更高序号到达的包；同时保留原始接收顺序 | 与其他黑盒测试同时完成 | 强制记录，稳定直连时应为 0 |
| 内容损坏 | 报文是否被截断、拼接或覆盖 | UDP checksum 能发现传输错误，但确定性 body 还能直接暴露长度、软件截断和缓存覆盖问题 | 校验报文头、长度和由 `run_id + sequence` 生成的完整 body | 与其他黑盒测试同时完成 | 强制记录，必须为 0 |
| Burst 承载 | 短时间连续来包时缓存能吸收多少积压 | 直接检查 TEMAC FIFO、RX 4 槽和 TX 2 槽是否起到缓冲作用 | RTL 中精确控制帧间隔和业务反压；板级 `sendto()` burst 只做端到端压力与恢复检查 | 精确值用 RTL；系统表现用板级 | RTL 强制，板级简测 |
| Ring level、ready 和 drop reason | 丢包或吞吐下降具体发生在哪里 | 这些不是用户性能，而是区分 TEMAC、RX ring、echo、TX ring 和主机瓶颈的诊断证据 | 正常黑盒测试失败后读取计数器，必要时用 ILA 捕获异常窗口 | 带内部观测的性能镜像 | 条件触发 |
| RTT 和抖动 | 从主机发出到收到回显需要多久、排队是否明显变化 | 控制类业务关心响应时间；RTT 长尾也可提示主机或 FPGA 内部出现积压 | 在同一性能报文中回显发送时间戳，接收时用同一主机单调时钟计算 | 板级黑盒；纯 FPGA 延迟用 RTL/ILA | 首轮建基线，门槛待业务确定 |
| 长时间稳定性 | 大量指针回绕和长时间运行后是否仍正确 | 短测试不容易暴露环形指针、计数器、偶发反压和链路稳定性问题 | 在已确认无损的速率持续运行，继续统计同一组完整性和性能指标 | 板级黑盒 | 基础性能通过后强制 |
| 过载恢复 | 输入超过能力后能否在降速时自动恢复 | UDP 可以按设计丢完整包，但不能半帧、错位、死锁或依赖 FPGA 复位恢复 | 高速过载一段时间后降到低速，检查重新无损、内容正确和计数继续变化 | RTL + 板级黑盒 | 强制验收 |
| 耦合全双工 | RX 与 TX 同时工作时是否互相阻塞 | 回显流量会同时占用 SGMII RX/TX、两侧 TEMAC FIFO 和 UDP 收发路径 | 持续发送并接收同速回显，分别报告 Host→FPGA 和 FPGA→Host 结果 | 当前回显镜像 | 强制覆盖；不等同于独立双向流 |

这些指标按用途分为四类：

- **强制验收结果**：内容、长度、丢包、持续吞吐和过载恢复；
- **同轮顺带统计**：PPS、重复、乱序、损坏和 RTT，不需要分别生成流量；
- **异常定位证据**：ring level、ready、drop reason 和 TEMAC overflow，只在黑盒异常时启用；
- **业务相关指标**：短包极限 PPS、RTT 门槛和独立双向流量，等业务负载明确后正式定门槛。

### 3.2 有效载荷吞吐率

只统计应用实际收到的 UDP payload，不包含 Ethernet、IPv4、UDP、FCS、前导码和帧间隔：

```text
goodput_bps = received_payload_bytes × 8 / measurement_seconds
```

回显为全双工测试，必须分别报告：

- Host TX / FPGA RX goodput；
- FPGA TX / Host RX goodput。

两方向可以同时接近线速，但不得把两者相加后称为单方向吞吐。

### 3.3 包率

```text
pps = received_datagrams / measurement_seconds
```

长包主要考验 bit/s，短包主要考验每包状态机切换、descriptor、checksum 提交和软件收包能力。

### 3.4 丢包、重复、乱序和损坏

性能 payload 至少携带：

| 字段 | 长度 | 用途 |
|---|---:|---|
| magic | 4 byte | 识别性能测试报文 |
| run ID | 4 byte | 隔离不同测试轮次，避免迟到包污染下一轮结果 |
| sequence | 4 byte | 统计丢包、重复和乱序 |
| send timestamp | 8 byte | 计算同一主机时钟域内的 RTT |
| deterministic body | 剩余字节 | 验证逐字节内容 |

带完整统计头的性能报文最小为 20 byte；16-byte、14-byte 等更短报文继续由正确性测试覆盖，
不要求携带完整时间戳。UDP checksum
已经提供链路级完整性保护，确定性 body 用于额外发现软件截断、拼包或缓冲覆盖。

定义：

```text
host_visible_loss_count = submitted_sequence_set - unique_valid_received_sequence_set
duplicate_count = valid_received_packets - unique_valid_received_sequences
reorder_count   = valid same-run sequence smaller than highest previously observed sequence
corrupt_count   = source/run_id/header/body/length mismatch packets
```

这里的 `submitted` 只表示 `sendto()` 已成功把报文交给主机内核，不证明 NIC 已经把它发送到线缆。
因此该差值是**主机可见的端到端丢包**。Windows/Python 黑盒测试不能可靠地把 socket 接收队列
溢出与 FPGA 丢包完全分开；发现丢包时必须结合 NIC 统计和 FPGA 内部计数，证据仍不足则标记为
`INCONCLUSIVE`，不能直接判定 FPGA 失败。

发送结束后必须保留 drain 时间，接收所有已在网卡、操作系统或 FPGA FIFO 中排队的回包，再计算
最终丢包。建议 drain 到连续 2 秒无新包或达到 5 秒上限。

### 3.5 时延与抖动

RTT 使用上位机单调时钟计算，至少输出：

- minimum、mean、maximum；
- p50、p95、p99、p99.9；
- 每秒 p99，用于观察长时间运行中的突发抖动。

高包率下不应无界保存每个样本；使用固定范围直方图或有界抽样。Windows 调度、Python 运行时、
网卡中断合并和 socket 缓冲都会进入 RTT，因此主机 RTT 不是纯 FPGA 延迟。若需要拆分 FPGA
内部阶段，应使用仿真周期计数或临时 ILA 测量。

### 3.6 反压和内部状态

需要观察或推导：

- `rx_fifo_level` 的峰值；
- `rx_drop_fifo_full`；
- `rx_udp_accepted`；
- `tx_accepted`、`tx_sent`、`tx_input_error`；
- TEMAC RX/TX FIFO overflow；
- `tx_busy` 持续时间和业务消息接口 ready 低周期数。

当前 `udp_echo_test_top` 将上述 UDP 统计端口悬空。第一阶段可通过主机 sequence 完成黑盒测试；
一旦出现丢包或吞吐异常，应增加独立 `udp_perf_test_top` 或临时 ILA/VIO 快照这些信号，不能只凭
主机结果猜测丢包位置。性能测试外壳不得改变生产 UDP 数据路径语义。

## 4. 理论基线

设 UDP payload 长度为 `P`，当前无 VLAN、IPv4 header 固定 20 byte、UDP header 8 byte。
包含前导码/SFD、FCS 和帧间隔后的线路 byte-time 为：

```text
wire_bytes = max(64, 14 + 20 + 8 + P + 4) + 8 + 12
```

其中 64 byte 是从目的 MAC 到 FCS 的最小 Ethernet 帧，8 byte 是 preamble/SFD，12 byte 是
inter-packet gap。理论值如下：

| UDP payload | Wire byte-time | 理论最大包率 | 理论最大 UDP goodput |
|---:|---:|---:|---:|
| 16 byte | 84 | 1.488 Mpps | 190.5 Mbit/s |
| 64 byte | 130 | 961.5 kpps | 492.3 Mbit/s |
| 256 byte | 322 | 388.2 kpps | 795.0 Mbit/s |
| 512 byte | 578 | 216.3 kpps | 885.8 Mbit/s |
| 1024 byte | 1090 | 114.7 kpps | 939.4 Mbit/s |
| 1472 byte | 1538 | 81.27 kpps | 957.1 Mbit/s |

表中数值是单方向物理上限，不是所有主机软件都能达到的保证值。网卡工具可能按不含 FCS、
preamble 或 IFG 的口径报告速率，最终报告必须同时保留 payload bytes、packet count、持续时间，
并统一换算口径。

## 5. 测试分层

### 5.1 合并测试原则与场景

主机测试工具只实现一套异步收发与统计引擎，再通过运行模式改变包长、发送节奏和持续时间。
每轮 sender 记录 `run_id、sequence、payload_length、submit_time、sendto_result`，receiver 记录
`receive_time、source、length、run_id、sequence、payload_check_result`。由这两份记录一次性导出：

```text
成功提交字节/时间                         -> application offered goodput
唯一正确接收字节/时间                     -> received goodput
成功提交包数或唯一正确接收包数/时间         -> offered/received PPS
本轮提交 sequence 集合 - 唯一接收集合      -> host-visible loss
同一 sequence 接收两次                     -> duplicate
接收 sequence 小于此前最高值               -> reorder
头部、长度或确定性 body 不一致              -> corrupt
receive_time - echoed send timestamp        -> host-visible RTT
```

第一阶段不为每个指标设计一套独立流量，而是合并成以下运行：

| 运行 ID | 流量方式 | 一次得到的主要指标 | 为什么需要这轮 |
|---|---|---|---|
| COMB-01 边界正确性 | 20、256、1472-byte，低速，各 1000 包 | 内容/长度、丢包、重复、乱序、损坏、基础 RTT | 先证明统计报文和三个代表性长度本身正确，避免把测试工具错误误认为性能问题 |
| COMB-02 持续速率 | 64-byte 和 1472-byte，逐级提高目标速率，每档 10 秒，最高无损档 60 秒 | offered/received goodput、PPS、丢包、重复、乱序、损坏、RTT 分布 | 64-byte 暴露逐包固定开销，1472-byte 暴露最大数据吞吐；同一轮同时完成完整性检查 |
| COMB-03 突发与过载恢复 | 受控 burst 或尽力发送，随后降到低速 | 突发丢包、恢复时间、恢复后完整性；有内部观测时再加 ring level/drop reason | 验证缓存吸收能力，以及缓存满后是否只丢完整包并自动恢复 |
| COMB-04 长稳 | 1472-byte、已确认无损的高负载，首轮 10 分钟，正式 30 分钟 | 长时间吞吐、丢包、完整性、RTT 趋势和停滞 | 覆盖大量环形指针回绕、持续 checksum 和偶发反压 |
| DIAG-01 异常归因 | 复现出现异常的原场景 | UDP counters、TEMAC overflow、ring level、ready/valid 和 ILA 窗口 | 只在 COMB-02/03/04 异常时定位瓶颈，不是每轮常规测试 |

COMB-02 已同时覆盖当前回显结构下耦合的全双工压力：Host→FPGA 接收与 FPGA→Host 回发同时
发生并分别统计。它不能替代未来“两个方向采用独立流量源、不同包长和不同速率”的独立全双工
测试；后者等业务 TX 模式明确后再增加。

### 5.2 A 层：RTL 周期效率仿真

目的：排除 FPGA 内部状态机和 ready/valid 逻辑造成的确定性吞吐气泡，不受主机与网卡影响。

在现有 testbench 基础上增加可计数的连续流量场景：

| ID | 场景 | 主要检查 |
|---|---|---|
| SIM-PERF-01 | RX 连续合法报文 | 接收顺序、commit 间隔、`RX_FINALIZE` 停顿、槽位峰值 |
| SIM-PERF-02 | TX 连续业务报文 | TX 两槽并行读写、帧间气泡、payload 每周期一字节 |
| SIM-PERF-03 | 完整 echo pipeline | RX 写、业务搬运、TX 写/读三段并行，无长期积压 |
| SIM-PERF-04 | 随机 AXI 反压 | `valid && !ready` 时数据稳定，恢复后无重复或跳字节 |
| SIM-PERF-05 | 有限时间过载 | 只丢完整报文、drop 计数准确、解除过载后自动恢复 |

每种场景覆盖 16、64、256、512、1024、1472-byte，并至少连续 1000 包。仿真记录：

- 第一输入字节到 RX commit 的周期数；
- RX commit 到业务首字节的周期数；
- TX descriptor 接受、TX commit、帧首字节和帧末字节周期；
- 相邻输出帧之间的空闲周期；
- 所有 `ready=0` 周期及原因；
- 最终收发和丢包计数。

通过条件：

- 数据、长度、顺序和 checksum 全部正确；
- 没有未知态进入有效握手；
- 满速输入下不出现无设计依据的持续气泡；
- 随机反压解除后能够继续运行，不需要复位；
- 预期丢包与统计事件逐包一致。

### 5.3 B 层：当前回显镜像黑盒性能测试

目的：在不修改 FPGA 镜像的情况下先得到真实端到端能力。

新增主机脚本计划入口：

```text
fpga/led/scripts/test_udp_performance.py
```

脚本要求：

- sender 和 receiver 独立运行，不能逐包等待回显；
- 使用 sequence、timestamp 和确定性 payload；
- 支持固定包长、持续时间、目标 Mbps/pps、发送窗口和 drain 时间；
- 调大 `SO_SNDBUF`、`SO_RCVBUF`，并报告实际生效值；
- 使用批次/token-bucket 节流，不能依赖每包 `sleep()`；
- 每秒打印 offered/received Mbps、pps、loss 和 p99 RTT；
- 保存 CSV/JSON 原始结果和 Markdown 摘要；
- 将 `sendto()` 明确失败、sequence 缺失和可获得的 NIC 错误/丢弃计数分开记录；Windows 无法
  从普通 Python UDP socket 可靠取得每个 socket 的接收溢出数时，必须明确标记为不可观测，
  不得把所有 sequence 缺失直接归因给 FPGA。

先执行 10 秒探索，再执行 60 秒正式测试。每个 payload 的目标发送速率按该长度的理论 UDP
goodput 上限取 10%、25%、50%、75%、90%、95%、98% 和尽力最大值。某一级出现持续丢包时，
缩小上下界寻找最大无损速率，不盲目继续所有更高速率。

### 5.4 C 层：带内部观测的性能镜像

满足以下任一条件时进入 C 层：

- 黑盒测试发生丢包；
- 1472-byte 吞吐明显低于主机发生器已证明能提供的速率；
- RTT 出现周期性长尾；
- 无法判断瓶颈位于 host、TEMAC FIFO、RX ring、echo 搬运或 TX ring。

建立开发专用 `udp_perf_test_top`，保持生产 UDP 数据路径语义不变，仅增加性能观测。当前
`udp_echo_test_top` 已将 UDP 统计端口悬空，TEMAC example FIFO 内的 RX/TX overflow 也未向
`ethernet_link_top` 导出；因此仅新增最外层 top 不足以取得全部证据。实现 C 层前必须明确选择：

- 把 TEMAC overflow 和 UDP/ring 统计逐层导出到性能 top；或
- 在内部层次绑定 ILA/调试探针，并保证重新生成 TEMAC example 文件时不会静默丢失观测点。

优先观测计数器和握手事件；ILA 只捕获异常窗口，不用于存储完整长时间流量。至少包括：

- 所有 UDP 统计计数器；
- TEMAC RX/TX FIFO overflow；
- RX/TX ring level、commit、release；
- echo descriptor/data handshake；
- Ethernet FIFO 侧 AXI `valid/ready/last`。

该镜像必须使用独立 bitstream 身份，下载前核对 SHA-256；性能测试完成后不能把它误认为产品
业务镜像。

## 6. 板级测试矩阵

### 6.1 前置检查

| ID | 检查 | 通过条件 |
|---|---|---|
| PRE-01 | bitstream 身份 | 与指定性能/回显镜像 SHA-256 一致 |
| PRE-02 | 链路状态 | 1000 Mbit/s、full duplex、稳定 30 秒 |
| PRE-03 | 地址配置 | Host `192.168.1.10/24`，FPGA `192.168.1.20:32000` |
| PRE-04 | 单包正确性 | 16、64、256、1472-byte 各 100 包零错误 |
| PRE-05 | 主机能力 | 发生器/接收器已证明能达到当前测试目标，不先成为瓶颈 |

优先采用主机与 DB500 直连。若经过交换机，记录型号、端口速率、流控配置和端口丢包计数。
正式跑数期间关闭会争用同一网卡的抓包、同步、杀毒扫描或其他高流量任务；需要抓包时单独执行
低速复现场景，避免抓包工具本身改变满载结果。

### 6.2 功能与尺寸扫描

| ID | Payload | 包数 | 目的 |
|---|---:|---:|---|
| HW-PERF-01 | 16 byte | 10,000 | 最小 Ethernet 帧区间和高包率基础检查 |
| HW-PERF-02 | 64 byte | 10,000 | 短包状态机与软件收包能力 |
| HW-PERF-03 | 256 byte | 10,000 | 中小包效率 |
| HW-PERF-04 | 512 byte | 10,000 | 中等业务报文 |
| HW-PERF-05 | 1024 byte | 10,000 | 大包吞吐过渡点 |
| HW-PERF-06 | 1472 byte | 10,000 | 标准 MTU 最大 UDP payload |

所有尺寸先在不丢包的低速下执行，要求内容、长度、sequence、源端点全部正确。
其中 16-byte 小于完整性能统计头长度，使用紧凑的正确性 payload，只检查长度和内容；20-byte
及以上使用完整 `magic + run_id + sequence + timestamp` 统计头。COMB-01 首轮只要求 20、256、
1472-byte 各 1000 包；上表六种长度和 10,000 包属于正式回归矩阵，不必阻塞首轮结论。

### 6.3 持续吞吐扫描

COMB-02 首轮对 64-byte 和 1472-byte 分别执行；256、512、1024-byte 在业务典型包长确定后加入
正式回归。每种选定 payload 执行：

1. 10% 理论 goodput，10 秒；
2. 50%，10 秒；
3. 75%，10 秒；
4. 90%，10 秒；
5. 95%，10 秒；
6. 98%，10 秒；
7. 已确认无损的最高档，60 秒；
8. 尽力发送，10 秒，用于观察过载行为，不要求零丢包。

正式结果报告每个方向的 offered/received payload Mbps、wire-equivalent Mbps、pps、loss、duplicate、
reorder、corrupt 和 RTT 分位数。

### 6.4 突发测试

板级由上位机以尽可能连续的 `sendto()` 提交报文，burst 之间保留足够间隔使所有 FIFO 排空：

| Payload | Burst 长度 |
|---:|---|
| 64 byte | 1、2、4、8、16、64、256 包 |
| 1472 byte | 1、2、4、6、8、16、64 包 |

正式回归时每个组合重复 1000 次；首轮 COMB-03 可先重复 100 次。记录首次出现丢包的 burst
长度和丢包分布，但该结果只表示 Windows/NIC/FPGA 组合下的**主机可见系统突发能力**。
`sendto()` 连续提交不能保证网线上形成精确的最小 IFG burst，因此不能把板级结果直接解释成
RX 4 槽或 TX 2 槽的准确容量。槽位和受控帧间隔的精确关系由 RTL 仿真验证。

### 6.5 长稳与恢复测试

| ID | 场景 | 建议时长 |
|---|---|---:|
| HW-PERF-LONG-01 | 1472-byte，800 Mbit/s payload | 30 分钟 |
| HW-PERF-LONG-02 | 选定业务包长和目标业务速率 | 30 分钟 |
| HW-PERF-REC-01 | 过载 10 秒后降到低速 | 重复 100 次 |

首轮 COMB-04 先运行 10 分钟，COMB-03 过载恢复先重复 10 次；确认工具和路径稳定后，再执行上表
30 分钟和 100 次的正式回归规模。

长稳测试要求无内容错误、无死锁、无需要人工复位的停滞。过载阶段允许完整报文丢弃，但降速后
必须自动恢复正常回显，计数器继续单调变化且不出现半帧或错误拼接。

链路拔插、速率重协商和复位属于稳定性/恢复测试，不混入吞吐数字；应在性能基线通过后作为
独立场景执行。

## 7. 暂定通过门槛

在产品业务负载尚未确定前，采用以下工程门槛；业务需求明确后可提高，但不能降低数据完整性
要求。

### 7.1 强制门槛

- 任意受支持长度：`corrupt=0`、`duplicate=0`。
- 直连稳定链路在无过载条件下不产生 FPGA 可归因的乱序；已由内部证据归因到外部发送源的乱序
  作为已知缺口单独计数，不阻断吞吐、丢包、完整性和恢复测试。
- 1472-byte、900 Mbit/s UDP payload、持续 60 秒：零丢包。
- 1472-byte、800 Mbit/s UDP payload、持续 30 分钟：零丢包、零错误、无停滞。
- 仿真中的过载/drop 数量与内部统计一致，解除过载后无需复位即可恢复。
- 能取得内部证据的异常应归因到主机、网卡、TEMAC FIFO、UDP drop reason 或业务反压之一；
  当前黑盒镜像证据不足时标记 `INCONCLUSIVE` 并进入 DIAG-01，不能猜测归因。

### 7.2 延伸目标

- 1472-byte、至少 940 Mbit/s UDP payload、持续 60 秒零丢包；理论上限约 957.1 Mbit/s。
- 在经过能力校准的专用发生器上，短包无损包率达到理论值的 90% 以上。

如果 Windows/Python 工具达不到门槛，但网卡或 CPU 已先饱和，该结果只能标记为
`HOST_LIMITED`，不能据此判定 FPGA 不通过。正式线速结论需换用已校准的 C/C++、Linux
packet generator、硬件流量仪或第二台能力足够的测试主机。

延迟暂不设置绝对门槛。首轮测试建立 p50/p99/p99.9 基线，待业务层给出控制响应或图像流时延
要求后再写入正式验收值。

## 8. 执行顺序与停止条件

执行顺序：

1. 保存当前 RTL、bitstream SHA-256、网卡和链路身份。
2. 完成 A 层 RTL 周期效率测试。
3. 校准主机发生器能力和 socket buffer。
4. 完成低速尺寸扫描。
5. 完成 10 秒速率扫描并确定无损区间。
6. 完成 60 秒正式吞吐测试。
7. 完成 burst、长稳和过载恢复测试。
8. 发生无法归因的问题时进入 C 层内部观测。
9. 将最终结论更新到 UDP `DEVELOPMENT.md` 或本文件的结果章节。

出现以下任一情况立即停止当前高负载测试并保存现场：

- payload 内容损坏；
- FPGA 内部新产生 sequence 异常；已归因到当前外部发送源的已知乱序只记录，不停止测试；
- 链路掉线或 PCS 状态异常；
- 回显停止且降速后不能自行恢复；
- FPGA 统计计数出现回退、未知态或与主机结果严重不一致；
- 主机 socket/NIC 已明确丢包，导致本轮无法评价 FPGA。

## 9. 结果记录

每轮必须保存：

- 日期、操作员、Git commit/工作区状态；
- `.xpr` 路径、active top、bitstream 路径、生成时间和 SHA-256；
- FPGA、板卡、PHY、网卡、驱动、操作系统和连接拓扑；
- payload 长度、目标速率、实际发送数、接收数和测试时间；
- goodput、wire-equivalent rate、pps、丢包/重复/乱序/损坏；
- RTT 分位数；
- socket buffer 实际值、CPU 利用率和 NIC 错误/丢包计数；
- FPGA 内部计数器起止值（可获得时）；
- 原始 CSV/JSON、终端日志、Vivado/ILA 采集路径；
- 结果：`PASS`、`PASS_WITH_KNOWN_REORDER_GAP`、`FAIL`、`HOST_LIMITED` 或 `INCONCLUSIVE`。

建议原始产物保存在 `fpga/led/logs/udp_perf_<唯一时间戳>.*`；`AI-work` 只维护测试方案和高密度
结论，不复制大体量原始采样。

## 10. 首轮推荐最小集合

首轮不必一次完成完整回归矩阵，先实施以下合并闭环：

1. 新增异步收发的 `test_udp_performance.py`。
2. COMB-01：20、256、1472-byte，低速，各 1000 包；同时得到完整性、丢包、重复、乱序和基础
   RTT。
3. COMB-02：64、1472-byte 的 10 秒速率扫描；同时得到 goodput、PPS、丢包、重复、乱序、损坏
   和 RTT。对 1472-byte 再执行 900 Mbit/s、60 秒测试。
4. COMB-03：1472-byte burst 1、2、4、6、8、16、64 包，各重复 100 次；再执行过载 10 秒、
   降至 100 Mbit/s 10 秒的恢复测试，共重复 10 次。
5. COMB-04：1472-byte、800 Mbit/s，先运行 10 分钟；首轮稳定后再扩展为 30 分钟正式长稳。
6. 若出现丢包、内容错误、不能恢复或吞吐低于 900 Mbit/s，再执行 DIAG-01，补齐 TEMAC
   overflow 和 UDP/ring 内部观测后归因。

该最小集合用四种运行覆盖全部当前必要指标，依次回答：数据是否正确、短包逐包处理与长包带宽
是否足够、突发或过载后能否恢复、环形指针长期回绕是否稳定。PPS、重复、乱序、损坏和 RTT 都
由相同报文流顺带计算，不再为它们增加独立测试轮次。

## 11. 2026-09-12 首轮执行结果

### 11.1 已完成：RTL 与测试工具

共享工程为 `D:\MyFPGAProject\UDP\fpga\led\led.xpr`，所有本轮仿真均使用 Vivado 2021.1 的
`sim_1` behavioral flow，结束后恢复 `sim_1 top=ad9517_clock_manager_tb`。

| 项目 | 实际结果 | 结论 |
|---|---|---|
| RX/TX payload ring 原有回归 | `UDP_RX_PAYLOAD_RING_PASSED`、`UDP_TX_PAYLOAD_RING_PASSED` | 提交/回滚、反压、同步 BRAM 和指针回绕基线仍通过 |
| UDP transport 原有回归 | `UDP_TRANSPORT_FIXED_HOST_PASSED` | 协议校验、RX 四槽、TX 两槽、checksum 和统计基线仍通过 |
| Payload echo 原有回归 | `UDP_PAYLOAD_ECHO_PASSED` | descriptor 和 payload 反压映射仍通过 |
| 新增完整 echo pipeline 周期仿真：64-byte × 1000 包 | RX/TX `492.399 Mbit/s`，`rx_stalls=0`，`max_rx_level=1` | 与 64-byte 理论上限 `492.3 Mbit/s` 一致 |
| 新增完整 echo pipeline 周期仿真：1472-byte × 1000 包 | RX/TX `957.102 Mbit/s`，`rx_stalls=0`，`max_rx_level=1` | 与 1472-byte 理论上限 `957.1 Mbit/s` 一致 |
| 性能脚本静态与内置自检 | `py_compile`、`UDP_PERFORMANCE_SCRIPT_SELF_TEST_PASSED` | 统计头、确定性 body、分位数和丢包集合计算通过 |
| 性能脚本本机 UDP 回显闭环 | 256-byte × 1000 包，loss/duplicate/reorder/corrupt 均为 0 | 异步 socket 收发和 JSON/CSV 结果链路通过；不计为 FPGA 性能 |

新周期仿真 `udp_echo_pipeline_perf_tb` 对 RX 输入施加 1 Gb/s 线路节奏，并在 TX ready 模型中加入
MAC client AXIS 不可见的 24 byte-time（preamble/SFD、FCS、IFG）。两种包长均完成 1000 次
RX→parser/checksum→RX ring→echo→TX ring/checksum→TX engine 闭环，最终计数为接收 2000、发送
2000，所有 drop/error 为 0。这证明当前 UDP 逻辑在周期级具备线速能力，但不包含真实 TEMAC、
PCS/PMA、PHY、网卡和 Windows 调度。

本轮 Vivado 外层调用日志：

- `fpga/led/logs/udp_payload_ring_recheck_20260912_194700_699.log`
- `fpga/led/logs/udp_transport_recheck_20260912_194748_579.log`
- `fpga/led/logs/udp_echo_recheck_20260912_194821_342.log`
- `fpga/led/logs/udp_echo_pipeline_perf_20260912_195128_815.log`

XSim 原生结果仍位于 `fpga/led/led.sim/sim_1/behav/xsim/`。Vivado 在 elaboration 后输出缺少可选
`wbtcv.exe` 的安装诊断，但 `xelab/xsim` 实际运行完成、进程退出码为 0 且 testbench 给出明确
PASS marker；该诊断未阻止本轮仿真。

### 11.2 未完成：真实板级 COMB-01～04

预检查确认当前 bitstream
`fpga/led/led.runs/impl_udp_echo/udp_echo_test_top.bit` 的 SHA-256 仍为
`29FBF09792054768623AFADFF85FAF364E528B0DDAE1AC74F7B55914223C1619`。但固定主机 MAC
`9C-69-D3-1A-4C-6D` 对应的 ASIX“以太网 2”当前为 `Disconnected / 0 bps`；虽然接口仍保留
`192.168.1.10/24`，现有单包回显脚本实际超时。因此 PRE-02 未通过，不能执行或评价板级
COMB-01～04，也不能把本次超时记为 FPGA 失败。进一步执行只读 JTAG inventory 时，hw_server
能够发现唯一 Digilent target `localhost:3121/xilinx_tcf/Digilent/E3077BAA4210`，但
`open_hw_target` 报告 `No devices detected`；日志为
`fpga/led/logs/udp_echo_hw_inventory_20260912_195746_395.log`。这与板卡未上电或 JTAG/板级连接
未就绪一致，因此本轮没有尝试重新下载 bitstream。

恢复板级测试所需的最小外部条件是：给 DB500/PHY 上电并连接到 ASIX“以太网 2”，确认该接口
恢复 `1 Gbit/s full duplex`，同时确认 JTAG 下重新出现唯一 `xc7k325t_0`，然后重新运行
`test_udp_echo.py`。基线通过后即可使用本轮新增的 `fpga/led/scripts/test_udp_performance.py`
继续 COMB-01 和 COMB-02。

### 11.3 外部条件恢复后的执行命令

以下命令从 `D:\MyFPGAProject\UDP\fpga\led` 执行。先确认单包基线：

```powershell
python scripts/test_udp_echo.py
```

COMB-01 的三个代表长度：

```powershell
python scripts/test_udp_performance.py --payload-bytes 20   --count 1000 --target-mbps 1  --label comb01_20
python scripts/test_udp_performance.py --payload-bytes 256  --count 1000 --target-mbps 10 --label comb01_256
python scripts/test_udp_performance.py --payload-bytes 1472 --count 1000 --target-mbps 50 --label comb01_1472
```

COMB-02 首轮速率扫描按两个包长分别运行。64-byte 建议目标为 50、250、370、440、470、480
Mbit/s；1472-byte 建议目标为 100、480、720、860、900、938 Mbit/s。例如：

```powershell
python scripts/test_udp_performance.py --payload-bytes 64   --duration 10 --target-mbps 440 --label comb02_64_440m
python scripts/test_udp_performance.py --payload-bytes 1472 --duration 10 --target-mbps 900 --label comb02_1472_900m
python scripts/test_udp_performance.py --payload-bytes 1472 --duration 60 --target-mbps 900 --label comb02_1472_900m_60s
```

每条命令都生成 JSON 总结和逐秒 CSV。首先检查 `application_offered_mbps` 是否达到目标；若实际
offered 已明显低于目标，本轮只能说明主机发生器受限。达到目标后，再用 `received_goodput_mbps`
以及 `host_visible_loss/duplicate/reorder/corrupt` 判断端到端结果。出现非零异常时进入 DIAG-01，
不能仅凭黑盒 JSON 判定 FPGA 丢包位置。

## 12. 2026-09-14 首轮真实板级性能结果

### 12.1 身份与前置条件

- ASIX“以太网 2”为 `Up / 1 Gbps`，MAC `9C-69-D3-1A-4C-6D`，IPv4
  `192.168.1.10/24`；到 `192.168.1.0/24` 的直连路由使用该接口。
- JTAG 只发现 `localhost:3121/xilinx_tcf/Digilent/E3077BAA4210/xc7k325t_0`，器件 part 为
  `xc7k325t`。下载前板上是另一套带 8 ILA/4 VIO 的镜像。
- 本轮重新易失下载
  `led.runs/impl_udp_echo/udp_echo_test_top.bit`；SHA-256 为
  `29FBF09792054768623AFADFF85FAF364E528B0DDAE1AC74F7B55914223C1619`。下载后 Vivado 确认
  该镜像无 ILA/VIO，结果 `UDP_ECHO_PROGRAM_PASSED`。
- 下载日志为 `logs/udp_echo_program_perf_20260914_092216_923.log`；下载后的 14、256、1472-byte
  单包基线以及高负载结束后的相同回归均为 `UDP_ECHO_HOST_TEST_PASSED`。
- Vivado 打开工程时仍报告 `.xpr` 引用已移除的 `udp_rx_message_fifo.v` 和
  `udp_tx_message_buffer.v`。现成 bitstream 的下载不受影响，但重新构建前必须清理这两个陈旧引用。

最初一次 COMB-01 调用由操作命令误写为不存在的 `--payload-size`，三个进程均在 argparse 阶段
退出且没有发包；测试文档和脚本的正确参数始终是 `--payload-bytes`，该次调用不计入结果。

### 12.2 COMB-01 与 COMB-02

COMB-01 全部通过：

| Payload | 目标/包数 | 实际发送/接收 | loss/duplicate/reorder/corrupt | 结果文件 |
|---:|---:|---:|---:|---|
| 20 | 1 Mbit/s，1000 包 | 1000/1000 | 0/0/0/0 | `logs/comb01_20_20260914_092311_0x0EDF72B7.json` |
| 256 | 10 Mbit/s，1000 包 | 1000/1000 | 0/0/0/0 | `logs/comb01_256_20260914_092313_0x766A6E9E.json` |
| 1472 | 50 Mbit/s，1000 包 | 1000/1000 | 0/0/0/0 | `logs/comb01_1472_20260914_092315_0x2EA17A45.json` |

COMB-02 证明了较高吞吐下内容与送达保持良好，但发现可重复的回包倒序：

| Payload | 时长 | 实际 offered / received | 包数 | loss/duplicate/reorder/corrupt | 判定 |
|---:|---:|---:|---:|---:|---|
| 64 | 10 s | 20.000 / 20.000 Mbit/s | 390,625 | 0/0/0/0 | PASS |
| 64 | 10 s | 25.000 / 24.999 Mbit/s | 488,282 | 0/0/2/0 | OBSERVED_ERRORS |
| 64 | 10 s | 47.594 / 47.592 Mbit/s | 929,597 | 0/0/265/0 | OBSERVED_ERRORS |
| 1472 | 10 s | 400.0 / 400.0 Mbit/s | 339,662 | 0/0/0/0 | PASS |
| 1472 | 10 s | 420.0 / 420.0 Mbit/s | 356,658 | 0/0/0/0 | PASS |
| 1472 | 60 s | 420.0 / 420.0 Mbit/s | 2,139,942 | 0/0/5/0 | OBSERVED_ERRORS |
| 1472 | 10 s | 440.0 / 440.0 Mbit/s | 373,641 | 0/0/1/0 | OBSERVED_ERRORS |
| 1472 | 10 s | 480.0 / 480.0 Mbit/s | 407,605 | 0/0/5/0 | OBSERVED_ERRORS |
| 1472 | 10 s | 893.2 / 893.2 Mbit/s | 758,488 | 0/0/122/0 | OBSERVED_ERRORS |

64-byte 的 20 Mbit/s/10 秒和 1472-byte 的 400 Mbit/s/10 秒是本轮观察到的无错点，不应解释成
已证明的长期无错上限。420 Mbit/s 在 10 秒通过但扩展到 60 秒出现 5 次倒序，说明异常是低概率、
随包数累积暴露的顺序问题，而不是固定带宽断点。900 Mbit/s 点的 Python 实际 offered 为
  893.2 Mbit/s，略低于请求值；它没有丢包或内容错误。当时按严格顺序门槛停止了后续测试；完成
  DIAG-02 后已确认该乱序是外部发送源缺口，后续不再因此阻断 60 秒吞吐和 COMB-04 长稳。

### 12.3 COMB-03 过载与恢复

1472-byte 尽力发送 10 秒时，实际 offered 达 `956.417 Mbit/s`，接近理论 UDP payload 上限
`957.1 Mbit/s`，按 1538/1472 换算为 `999.300 Mbit/s` wire-equivalent；接收 goodput 为
`952.884 Mbit/s`。812,224 个提交报文中主机可见 loss 为 42、
reorder 为 119、duplicate/corrupt 均为 0，p99 RTT 在积压期间升至 36.9 ms。紧接着降到
100 Mbit/s 运行 10 秒，84,919 个报文全部正确回收，loss/duplicate/reorder/corrupt 全为 0，证明
当前组合在一次过载后可自动恢复，没有死锁、半帧或内容拼接。

本轮只完成一次过载/恢复探索；burst 1、2、4、6、8、16、64 的 100 次矩阵和过载恢复 10 次重复
尚未执行。过载的 42 个 sequence 缺失不能仅凭 Windows UDP socket 归因给 FPGA。

### 12.4 DIAG-01 抓包归因

使用 pktmon interface 12、仅过滤 `192.168.1.20` UDP/32000，对 64-byte、约 46.7 Mbit/s 的
`UPF1` run `0xE2429B64` 抓包。socket 侧为 729,907 发/收、loss 0、reorder 111、corrupt 0。
原始 `capture.pcapng` 的 SHA-256 为
`E5240BAEE2A85C839B915B85C91449E797E3CE7AF627AA83CF2AEE1FCEC547DC`。

确定性流式扫描在抓到的 Host→FPGA 551,120 帧中观测 reorder 0，在 FPGA→Host 609,106 帧中观测
reorder 94。关键窗口的输入 sequence 为 `65744,65745,65746,65747`，回包抓到的顺序为
`65744,65746,65745,65747`；另一个窗口将 `205127` 延迟到 `205131` 之后。pktmon 在高包率下有
漏采且抓包点位于 ASIX/Windows 侧，因此该阶段证据只证明倒序发生在回包方向。进一步提取 IPv4
Identification 后发现，倒序 payload sequence 对应连续递增的 FPGA TX IP ID，说明倒序在 TX
engine 分配 IP ID 前已经存在。完整证据见
`AI-work/reports/packet-audit/20260914-udp-echo-reorder/REPORT.md`。

### 12.5 DIAG-02 FPGA 三边界 ILA 归因

开发专用 `udp_perf_diag_top` 在 125 MHz 域旁路观察 TEMAC RX client AXIS、RX message 和 TEMAC
TX client AXIS；监视器不参与任何 ready/valid 控制。其 testbench 通过，实现结果为
`WNS=+0.327 ns`、`WHS=+0.056 ns`、阻断级 DRC 0。

64-byte、目标 50 Mbit/s、burst 32、`run_id=0xD1A60001` 的硬件轮次发送/接收 934,694 包，
loss/duplicate/corrupt 全为 0，主机观测 reorder 225。ILA 三点依次观测到完全相同的
`0x5FE,0x600,0x5FF,0x601`；倒序脉冲首先在 TEMAC RX client AXIS 的 sample 256 出现，随后在
RX message 的 sample 322 和 TX client AXIS 的 sample 429 出现。由此排除 parser、RX ring、
echo、TX ring 和 TX engine 自行重排，归因状态为 `EXTERNAL_HOST_TX_ORDERING`。

主机脚本由单一发送线程在单一 UDP socket 上顺序调用 `sendto()`；pktmon 发送侧已捕获窗口有序，
而 FPGA RX 边界已倒序，因此故障区间位于 pktmon/NDIS 发送抓包点之后、FPGA UDP parser 之前。
当前 ASIX 驱动为 `AxUsbEth.sys 4.20.1.0`，IPv4 IP/UDP checksum offload、LSO v2 与 EEE 启用；若
继续细分外部根因，需要逐项可恢复 A/B 或物理 TAP。

### 12.6 当前结论与继续条件

- 已证明：低速三种代表长度正确；主机可把 1472-byte 流量实际推至接近理论线速；受控
  893.2 Mbit/s 运行 10 秒无主机可见丢包和内容错误；一次过载后能自动恢复。
- 已知非阻断缺口：高包数场景存在来自当前 ASIX/Windows 发送路径的 sequence 倒序；继续完整
  记录 reorder，但不再用它阻断吞吐、丢包、内容完整性、过载恢复和长稳测试。
- 已归因到边界：UDP RTL 保持输入顺序，倒序在最前端 RX client AXIS 已存在，不是 RX/TX 槽环
  或 checksum/帧发送状态机制造的问题。
- 外部细分未完成：尚不能在 Windows NDIS/offload、ASIX USB 驱动/聚合与适配器硬件之间唯一归因。
- 当前主机链路可以继续评估吞吐、PPS、主机可见丢包、内容完整性、恢复能力和稳定性，但不能作为
  顺序验收基准。运行脚本时显式增加 `--allow-reorder`，仅 reorder 非零时结果记为
  `PASS_WITH_KNOWN_REORDER_GAP`；loss、duplicate、corrupt、发送错误或接收线程错误仍然阻断。
- 如后续需要独立验收顺序，再使用可保证单流顺序的网卡/流量仪或完成 ASIX offload A/B；这不
  阻碍当前性能矩阵继续执行。
- 捕获后已恢复原无 ILA/VIO echo bitstream，14、256、1472-byte 单包回归全部通过。

### 12.7 已知乱序非阻断后的继续测试

按 12.6 的处置口径，后续轮次显式使用 `--allow-reorder`：只出现已归因的外部 sequence 乱序时
记为 `PASS_WITH_KNOWN_REORDER_GAP`；loss、duplicate、corrupt、发送错误和接收线程错误仍按失败
处理。本轮继续使用 SHA-256 为
`29FBF09792054768623AFADFF85FAF364E528B0DDAE1AC74F7B55914223C1619` 的原始 echo bitstream。

COMB-02 的 1472-byte、请求 900 Mbit/s、60 秒持续轮次结果如下：

| run ID | 提交/唯一接收 | 实际 offered / received | loss/duplicate/reorder/corrupt | RTT p99 / max | 判定 |
|---|---:|---:|---:|---:|---|
| `0xAEACEDBF` | 4,529,421 / 4,529,421 | 888.974 / 888.969 Mbit/s | 0/0/769/0 | 773.856 / 2740.1 us | `PASS_WITH_KNOWN_REORDER_GAP` |

该轮证明约 889 Mbit/s 的主机实际负载可持续 60 秒且无主机可见丢包、重复或内容损坏；但实际
offered 低于请求的 900 Mbit/s，所以不能声称精确 900 Mbit/s 目标已由本机 Python 发生器覆盖。
结果文件为
`logs/comb02_continue_1472_900m_60s_20260914_103341_0xAEACEDBF.json`，SHA-256 为
`8C559FE97887414E21991919A960DF65F18DA991B9B6F0292AF47DCA2CC5DA90`。

COMB-03 先用同一 1472-byte/900 Mbit/s 请求比较 burst 形状，每档 10 秒：

| burst | 提交/唯一接收 | 实际 offered / received | loss/duplicate/reorder/corrupt | 判定 |
|---:|---:|---:|---:|---|
| 1 | 653,405 / 653,405 | 769.450 / 769.428 Mbit/s | 0/0/17/0 | `PASS_WITH_KNOWN_REORDER_GAP` |
| 2 | 706,235 / 706,235 | 831.660 / 831.635 Mbit/s | 0/0/50/0 | `PASS_WITH_KNOWN_REORDER_GAP` |
| 4 | 737,057 / 737,057 | 867.957 / 867.933 Mbit/s | 0/0/58/0 | `PASS_WITH_KNOWN_REORDER_GAP` |
| 6 | 742,495 / 742,495 | 874.360 / 874.334 Mbit/s | 0/0/84/0 | `PASS_WITH_KNOWN_REORDER_GAP` |
| 8 | 750,465 / 750,465 | 883.746 / 883.721 Mbit/s | 0/0/84/0 | `PASS_WITH_KNOWN_REORDER_GAP` |
| 16 | 755,531 / 755,531 | 889.713 / 889.690 Mbit/s | 0/0/74/0 | `PASS_WITH_KNOWN_REORDER_GAP` |
| 64 | 760,764 / 760,764 | 895.872 / 895.841 Mbit/s | 0/0/109/0 | `PASS_WITH_KNOWN_REORDER_GAP` |

这里的 burst 参数控制主机发送线程每次节拍内连续提交的包数，不等同于 FPGA ring 深度。结果
表明较大 burst 能提高本机发生器实际 offered；七档均无丢包、重复和内容损坏，没有看到槽环在
这些受控负载下造成半包、拼包或停滞。原始 JSON/CSV 使用
`logs/comb03_continue_1472_900m_burst*` 前缀。

随后完成 10 组“1472-byte 尽力过载 10 秒 → 100 Mbit/s 恢复 10 秒”：

- 十次过载共提交 8,154,880 包，实际 offered 范围为 959.504～960.607 Mbit/s；每轮主机可见
  缺失 45～47 包，合计 463，duplicate/corrupt 均为 0。过载允许丢包，此数据不能仅凭 Windows
  socket 归因到 FPGA。
- 每次过载后紧接的恢复轮均提交 84,919 包；十轮共 849,190 包，loss/duplicate/reorder/corrupt
  全为 0，十次均为严格 `PASS`。这证明重复过载后链路都能自行恢复，没有逐轮累积堵塞或死锁。
- 原始文件使用 `logs/comb03_continue_overload_cycle*` 和
  `logs/comb03_continue_recovery_cycle*` 前缀。

COMB-04 首轮长稳在 1472-byte、请求 800 Mbit/s 下持续 600 秒：

| run ID | 提交/唯一接收 | 实际 offered / received | loss/duplicate/reorder/corrupt | RTT p99 / max | 判定 |
|---|---:|---:|---:|---:|---|
| `0xD7603F72` | 40,653,617 / 40,653,617 | 797.895 / 797.894 Mbit/s | 0/0/2634/0 | 472.4 / 5919.3 us | `PASS_WITH_KNOWN_REORDER_GAP` |

该轮累计覆盖 4065 万次报文槽申请、提交、释放及大量指针回绕，没有主机可见丢包、重复、内容
损坏或停流。结果文件为
`logs/comb04_continue_1472_800m_10min_20260914_105022_0xD7603F72.json`，SHA-256 为
`D3DE67B7C07049E19234B21A34EA463380043136CDDCD78CDBDB1EDDD9CBFBFC`。

本次继续测试共 29 轮、提交 59,293,060 包；全部 463 个主机可见缺失均出现在十次允许丢包的
尽力过载段，其他轮次 loss/duplicate/corrupt 均为 0。测试结束后的 14、256、1472-byte 单包
回归再次为 `UDP_ECHO_HOST_TEST_PASSED`；ASIX 仍为 `Up / 1 Gbps`，适配器累计统计中的
`OutboundDiscardedPackets`、`OutboundPacketErrors`、`ReceivedDiscardedPackets` 和
`ReceivedPacketErrors` 均为 0。

当前结论是：首轮 COMB-04 10 分钟长稳与十次过载恢复已经通过；顺序保证仍未验收，精确
900 Mbit/s 受本机 Python 发生器限制。若要完成正式验收，下一步是 30 分钟长稳，以及在能保证
发送顺序/精确线速的网卡或流量仪上复核顺序和 900 Mbit/s 档。
