# UDP 载荷报文槽环开发记录

## 当前实现

- RX 实现入口：`udp_rx_payload_ring`，默认 4 槽。
- TX 实现入口：`udp_tx_payload_ring`，默认 2 槽。
- 两个模块均使用固定大小报文槽环和同步 Block RAM 读口。
- `udp_transport_fixed_host` 外部端口保持不变；内部已切换到新槽环模块。
- `fixed_host_tx_engine` 使用读地址 look-ahead 适配 TX 同步 BRAM。
- TEMAC RX/TX Ethernet FIFO 保持不变。

## 验证状态

状态：`HARDWARE_PERFORMANCE_10MIN_PASS_WITH_KNOWN_REORDER_GAP`

2026-09-11 已完成：

1. `udp_rx_payload_ring_tb` 与 `udp_tx_payload_ring_tb` 单元自检通过，覆盖 abort、满槽反压、
   同周期提交/释放、同步读反压稳定、并行读写与多次指针回绕。
2. `udp_transport_fixed_host_tb` 完整协议回归通过，并验证 TX 两槽填满、第三条消息反压、恢复后
   顺序发送及最终 IPv4/UDP checksum。
3. `udp_payload_echo_tb`、`udp_top` 和 `udp_echo_test_top` 分别通过行为仿真或完整 IP 展开。
4. `udp_echo_test_top` 综合、实现与 bitstream 生成通过：`WNS=+0.614 ns`、`WHS=+0.063 ns`，
   阻断级 DRC 为 0。
5. 层次资源报告确认 `udp_rx_payload_ring` 使用 2 个 RAMB36，`udp_tx_payload_ring` 使用
   1 个 RAMB36；payload 主存储未落入大容量 Distributed RAM。
6. 新镜像已下载到唯一 `xc7k325t_0`，主机 14、256、1472-byte UDP 回显全部通过。

新 bitstream：
`fpga/led/led.runs/impl_udp_echo/udp_echo_test_top.bit`，SHA-256
`29FBF09792054768623AFADFF85FAF364E528B0DDAE1AC74F7B55914223C1619`。

关键日志：

- `logs/udp_payload_ring_final_sim_20260911_231657.log`
- `logs/udp_transport_ring_20260911_225814.log`
- `logs/udp_echo_ring_20260911_225848.log`
- `logs/udp_top_ring_elab_20260911_225926.log`
- `logs/udp_echo_top_ring_elab_20260911_230328.log`
- `logs/udp_echo_ring_build_20260911_230739.log`
- `logs/udp_echo_ring_program_20260911_231023.log`
- `led.runs/impl_udp_echo/reports/utilization_hierarchical.rpt`

## 回包 sequence 倒序诊断方案（2026-09-14）

板级性能测试在高包数场景发现 payload sequence 倒序。现有抓包进一步确认 FPGA 回包的 IPv4
Identification 按实际回包顺序连续递增，例如 payload sequence
`65744,65746,65745,65747` 对应 IP ID `47781,47782,47783,47784`。因此异常在 TX engine 分配
IP ID 之前已经存在，但仅凭主机侧抓包仍无法区分 ASIX 出网重排和 FPGA RX/echo/TX ring 重排。

为完成归因，增加独立开发顶层 `udp_perf_diag_top`，保持 `udp_echo_test_top` 和生产数据路径不变。
该顶层继续例化相同的 `udp_top + udp_payload_echo`，只增加无反压、无数据修改能力的旁路观察：

1. 在 TEMAC RX Ethernet FIFO 输出、进入 `fixed_host_rx_parser` 前观察 Ethernet AXIS；按固定
   Ethernet II + IPv4 IHL=5 + UDP 头布局，在帧偏移 42..53 识别 `UPF1/run_id/sequence`。
2. 在 `udp_rx_payload_ring` 的业务消息输出握手处观察 payload 偏移 0..11，识别相同字段。
3. 在 `fixed_host_tx_engine` 输出、进入 TEMAC TX Ethernet FIFO 前再次观察帧偏移 42..53。
4. 每个观察点按 run ID 独立维护最高 sequence、报文计数、倒序计数和首次异常上下文。新的 run ID
   自动建立新基线，避免不同主机测试轮次从 sequence 0 开始造成假触发。
5. 三个观察器只读取已发生的 `valid && ready` 字节，不驱动任何数据或握手信号。任一倒序脉冲触发
   125 MHz ILA，并同时采集三个观察点的 current/highest/run ID/count 及实时握手信号。

判定规则：原始 RX AXIS 已倒序表示问题在主机 socket 之后、FPGA parser 之前，优先排查 ASIX
TX/USB/驱动或物理输入；原始 RX 有序而 RX message 倒序表示 parser/RX ring；RX message 有序而
TX AXIS 倒序表示 echo/TX ring/TX engine；三个 FPGA 边界均有序而主机仍倒序则表示 FPGA 发出后
的 NIC/Windows ingress。诊断 bitstream 和 LTX 使用独立 run、文件名和 SHA-256，不替代原 echo
镜像；捕获结束后恢复原 echo 镜像。

### 诊断执行结果

状态：`UDP_RTL_ORDER_PRESERVED_EXTERNAL_HOST_TX_ORDERING`

- `udp_sequence_order_monitor_tb` 已覆盖递增、倒序、新 run ID 重建基线和非 UPF1 过滤，结果为
  `UDP_SEQUENCE_ORDER_MONITOR_SIM_PASSED`；`sim_1` 已恢复为 `ad9517_clock_manager_tb`。
- `udp_perf_diag_top` 使用独立 `synth_udp_perf_diag/impl_udp_perf_diag` 构建通过，结果为
  `WNS=+0.327 ns`、`WHS=+0.056 ns`、阻断级 DRC 0。工程 active top 已恢复为
  `udp_echo_test_top`。
- 硬件轮次 `run_id=0xD1A60001` 在 64-byte、目标 50 Mbit/s、burst 32 下发送/接收 934,694 包，
  loss/duplicate/corrupt 均为 0，主机记录 reorder 225。
- ILA 在最前端 TEMAC RX client AXIS 直接观察到 `0x5FE,0x600,0x5FF,0x601`；随后 RX message
  与 TX client AXIS 均保持同一顺序。倒序触发分别发生在 sample 256、322、429，三个边界记录的
  `previous_highest/current` 都是 `0x600/0x5FF`。
- 因此 `fixed_host_rx_parser`、`udp_rx_payload_ring`、`udp_payload_echo`、
  `udp_tx_payload_ring` 和 `fixed_host_tx_engine` 没有制造倒序。结合此前 Host→FPGA pktmon 窗口
  有序，异常边界位于 pktmon/NDIS 发送抓包点之后、FPGA UDP parser 之前，工程归因为
  `EXTERNAL_HOST_TX_ORDERING`，优先排查 ASIX `AxUsbEth.sys 4.20.1.0` 的发送卸载/USB 聚合路径。
- 原 `udp_echo_test_top.bit` 已重新下载，硬件显示 ILA/VIO 数量均为 0；14、256、1472-byte 单包
  回显再次全部通过。
- 处置口径：该外部乱序作为已知缺口持续记录，但不阻断吞吐、PPS、丢包、内容完整性、过载恢复
  和长稳测试；当前 ASIX 链路不承担顺序保证验收。

详细原始证据和 SHA-256 见
[`20260914-udp-echo-reorder/REPORT.md`](../../reports/packet-audit/20260914-udp-echo-reorder/REPORT.md)。

## 非阻断乱序口径下的性能继续测试（2026-09-14）

- 1472-byte、请求 900 Mbit/s 的 60 秒轮实际 offered/received 为
  `888.974/888.969 Mbit/s`，4,529,421 包全部回收，loss/duplicate/corrupt 为 0。
- burst 1/2/4/6/8/16/64 的七档受控轮次均无 loss/duplicate/corrupt；实际 offered 范围为
  `769.450～895.872 Mbit/s`，未出现半包、拼包或停流。
- 十次尽力过载后均立即进入 100 Mbit/s 恢复轮；十个恢复轮共 849,190 包，
  loss/duplicate/reorder/corrupt 全为 0，没有出现跨轮积累的槽占用或死锁。
- 1472-byte、请求 800 Mbit/s 的 10 分钟长稳实际 offered/received 为
  `797.895/797.894 Mbit/s`，40,653,617 包全部回收，loss/duplicate/corrupt 为 0；已知外部
  reorder 为 2634，结果为 `PASS_WITH_KNOWN_REORDER_GAP`。
- 以上黑盒结果与 ILA 归因一致：RX/TX 槽环没有制造已观察到的顺序变化，且在大量指针回绕与
  重复过载后保持完整报文所有权和恢复能力。详细数据见
  [`PERFORMANCE_TEST_PLAN.md`](../udp/PERFORMANCE_TEST_PLAN.md) 第 12.7 节。
