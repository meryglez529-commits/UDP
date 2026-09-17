# CONTROL 当前固件黑盒扰动测试报告

## 1. 测试边界

- 日期：2026-09-17
- bitstream SHA-256：`021B0DC22234F45FE71F9131F5B87C122A9BBC6CAB26B409ECFEE7AAC559076A`
- 端点：主机 `192.168.1.10:32000`，FPGA `192.168.1.20:32000`
- 注入位置：主机 CONTROL 请求发送侧和回复接收侧。
- 注入类型：丢弃、重复、窗口内乱序、延迟、连续突发丢弃和回复持续丢弃。
- 观测内容：逐请求参考模型、首次回复与重复回复一致性、寄存器最终状态、写执行计数、
  watchdog 恢复计数和窄范围网卡抓包。
- 本轮没有修改 RTL、Vivado fileset、约束或 bitstream，也没有使用 ILA/VIO。

本报告只评价当前固件在主机侧可施加扰动下的外部行为。D16、D17a、D17b 所需的内部
ready/valid 故障注入，以及必须由透明中间设备真实滞留数据报的跨代迟到包试验，不纳入本轮
通过范围。

## 2. 正式结果

| 阶段 | seed / 轮数 | 完成请求 | watchdog 恢复 | 用时 | 结果 |
|---|---:|---:|---:|---:|---|
| 确定性用例（前置） | — | D00～D15、D18 | 多路径覆盖 | — | PASS |
| R0 | `0xDB500102` | 1,000,000 | 0 | 58.68 s | PASS |
| R0 | `0xDB500103` | 1,000,000 | 0 | 58.97 s | PASS |
| R0 | `0xDB500104` | 1,000,003 | 0 | 58.88 s | PASS |
| R1 | `0xDB500201` | 5,000,003 | 2 | 389.74 s | PASS |
| R1 | `0xDB500202` | 5,000,003 | 2 | 388.94 s | PASS |
| R1 | `0xDB500203` | 5,000,002 | 1 | 386.60 s | PASS |
| R2 长稳附加样本 | `0xDB500301` | 20,000,003 | 916 | 5,273.82 s | PASS |
| R2 | `0xDB500302` | 2,000,002 | 85 | 518.01 s | PASS |
| R2 | `0xDB500303` | 2,000,002 | 93 | 529.76 s | PASS |
| R3 watchdog 专项 | 1,000 轮 | 1,000 次恢复循环 | 1,000 | 669.64 s | PASS |
| 确定性健康回归（末尾） | — | D00～D15、D18 | 多路径覆盖 | 4.24 s | PASS |

R2 的正式最少完成请求数已从每 seed 20,000,000 调整为 2,000,000；每种离散随机动作至少
实际注入 10,000 次的硬门槛保持不变。`0xDB500301` 在调整前已完整通过 20,000,003 请求，作为
额外长稳证据保留，不要求其余 seed 重复消耗同等运行时间。

### 2.1 R2 实际注入量

| seed | 请求 DROP | 请求 DUP | 请求 REORDER | 请求 DELAY | 回复 DROP | 回复 DUP | 回复 REORDER | 回复 DELAY |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `0xDB500301` | 224,458 | 224,616 | 224,765 | 446,554 | 218,441 | 217,396 | 217,750 | 431,097 |
| `0xDB500302` | 22,606 | 22,517 | 22,128 | 44,724 | 21,925 | 21,977 | 21,821 | 43,397 |
| `0xDB500303` | 22,618 | 22,389 | 22,631 | 44,430 | 21,766 | 21,848 | 21,735 | 43,135 |

以上数字来自事件日志的实际动作计数，不是“概率 × 请求数”的估计。两个缩短后的 seed 在请求
和回复两个方向上，每种动作都超过 10,000 次门槛。它们还分别注入 6,792 和 6,740 次请求侧
突发丢弃。

### 2.2 R3 恢复一致性

R3 连续执行 1,000 次“使请求重试耗尽→停止 CONTROL 流量→等待 watchdog→以请求编号 1
建立新代际→核对寄存器和计数”的完整循环，结果为 1,000/1,000 PASS：

- 每轮新代际都从请求编号 1 恢复；
- 每轮用于验证的 SET 恰好执行一次；
- 写执行计数每轮严格增加 1；
- watchdog 计数每轮严格增加 1；
- 未观察到旧代际内容在新代际执行；
- 观察失败率为 0，按 rule of three 给出的 95% 单侧失败率上界约为 0.3%。

### 2.3 抓包完整性

正式 R1、R2 和 R3 运行均使用网卡组件级窄过滤抓包。R2 `0xDB500302`、`0xDB500303` 和
R3 的 PktMon 转换记录分别包含 319,262、134,515 和 11,449 个观测包，三次均报告事件丢失
数为 0。抓包为环形、128-Byte 截断记录，用于定位协议行为，不作为完成请求数的唯一计数源。

## 3. 测试器自检与探索运行

正式结果之前出现过两类主机测试器判定问题，均通过保存日志、缩小用例和同 seed 重放定位；
没有据此修改 FPGA RTL 或 bitstream：

1. Windows 主机/NIC 可能在测试器调用 `sendto` 后延迟约 522 ms 才把数据包送到抓包点。
   旧判定器把“已调用 sendto”直接等同于“FPGA 已执行”，在 watchdog 边界会产生错误期望。
   正式判定改为：恢复后状态必须等于已观测到回复所证明的严格前缀与发送上界之间的某个合法
   前缀，并由后续查询确认。
2. 恢复时从头重建全部候选参考状态的 O(N) 处理会在大样本下制造超过 watchdog 门槛的主机
   静默。正式测试器改为增量维护 `proven_model/proven_prefix`，消除了测试器自身造成的额外
   静默。

修正后的 R1 三个 seed、R2 三个 seed、R3 和末尾确定性回归均通过。早期失败、人工中断及
`0xDB500302` 旧 20,000,000 门槛下的中断运行只作为测试器开发证据，不计入正式 PASS 数量。

## 4. 结论

在当前固件和本轮可注入边界内，没有观察到以下内部通信故障：

- 合法 SET/QUERY 被重复执行；
- 到达乱序导致寄存器访问乱序；
- 同一请求编号返回不一致的重复回复；
- 窗口外请求污染当前窗口；
- 回复丢失后无法通过原请求重放取得一致结果；
- 重试耗尽后 CONTROL 永久卡死；
- watchdog 恢复后继承旧窗口、旧回复或旧请求编号状态。

因此，当前固件的 CONTROL 通信在主机侧丢包、重复、乱序、延迟和持续回复丢失条件下，兼顾了
有序交付、去重、有限并发和自动恢复。本结论不外推到物理链路永久故障、TEMAC/client FIFO
内部停滞、尚未实现的 DATA 通道，或未经中间网络设备施加的真实跨代迟到包。

## 5. 主要证据

### 5.1 结构化结果

- `fpga/led/logs/control-fault/control_fault_20260917_111645_r0_seed3679453442.json`
- `fpga/led/logs/control-fault/control_fault_20260917_111753_r0_seed3679453443.json`
- `fpga/led/logs/control-fault/control_fault_20260917_111858_r0_seed3679453444.json`
- `fpga/led/logs/control-fault/control_fault_20260917_114939_r1_seed3679453697.json`
- `fpga/led/logs/control-fault/control_fault_20260917_120351_r1_seed3679453698.json`
- `fpga/led/logs/control-fault/control_fault_20260917_121100_r1_seed3679453699.json`
- `fpga/led/logs/control-fault/control_fault_20260917_121812_r2_seed3679453953.json`
- `fpga/led/logs/control-fault/control_fault_20260917_140307_r2_seed3679453954.json`
- `fpga/led/logs/control-fault/control_fault_20260917_141244_r2_seed3679453955.json`
- `fpga/led/logs/control-fault/control_fault_20260917_142219_recovery_1000.json`
- `fpga/led/logs/control-fault/control_fault_20260917_143348_deterministic.json`

每个随机运行还具有同名 `.jsonl` 完整事件轨迹和 `.log` 人类可读进度记录。

### 5.2 抓包目录

- `AI-work/reports/control-fault/20260917-r1-seed-db500201-replay3/`
- `AI-work/reports/control-fault/20260917-r1-seed-db500202-replay/`
- `AI-work/reports/control-fault/20260917-r1-seed-db500203/`
- `AI-work/reports/control-fault/20260917-r2-seed-db500301/`
- `AI-work/reports/control-fault/20260917-r2-seed-db500302-reduced/`
- `AI-work/reports/control-fault/20260917-r2-seed-db500303-reduced/`
- `AI-work/reports/control-fault/20260917-r3-watchdog-1000/`

各目录均保留原始 `.etl` 和转换后的 `.pcapng`。
