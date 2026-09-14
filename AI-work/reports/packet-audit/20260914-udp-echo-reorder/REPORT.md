# UDP echo 回包倒序抓包审计

结论：后续 125 MHz ILA 已在 FPGA 的 TEMAC RX client AXIS 输出处直接看到相同倒序。异常进入
`fixed_host_rx_parser` 之前就已存在；UDP parser、RX ring、echo、TX ring 和 TX engine 均保持了该
输入顺序。因此这不是 UDP RTL 产生的倒序，根因边界位于主机 pktmon 发送抓包点之后、FPGA UDP
parser 之前，优先指向 Windows NDIS/offload、ASIX USB 发送路径或适配器本身。

## 会话与证据

- 接口：ASIX USB to Gigabit Ethernet Family Adapter，pktmon interface 12。
- 过滤范围：仅 `192.168.1.20`、UDP port `32000`。
- 流量：`UPF1`，run ID `0xE2429B64`，64-byte payload，目标 50 Mbit/s，持续 8 秒。
- socket 结果：729,907 发/收、loss 0、duplicate 0、reorder 111、corrupt 0。
- 原始抓包：`capture.pcapng`，SHA-256 `E5240BAEE2A85C839B915B85C91449E797E3CE7AF627AA83CF2AEE1FCEC547DC`。
- 解码依据：当前主机脚本 `test_udp_performance.py`，header 为大端 `magic[4] + run_id[4] + sequence[4] + timestamp[8]`。

## 确定性审计结果

完整抓包流式扫描得到：Host→FPGA 匹配帧 551,120、观测倒序 0；FPGA→Host 匹配帧 609,106、观测倒序 94。pktmon 在该包率下有明显漏采，因此这些数量只用于证明倒序存在与方向，不用于计算丢包率。

关键窗口：

| 方向 | 抓包编号 | sequence 顺序 | 结论 |
|---|---|---|---|
| PC → FPGA | 40863–40866 | 65744, 65745, 65746, 65747 | 输入侧在该窗口保持顺序 |
| FPGA → PC | 40887, 40888, 40894, 40895 | 65744, 65746, 65745, 65747 | sequence 65745 晚于 65746，FAIL |

第二个窗口同样可复现：Host→FPGA 抓包 110655–110661 为 205126…205132；FPGA→Host 抓包 110696–110702 为 `205126,205128,205129,205130,205131,205127,205132`。

回包 IPv4 Identification 提供了额外顺序证据。第一个窗口中，payload sequence
`65744,65746,65745,65747` 对应 FPGA TX engine 生成的连续 IP ID
`47781,47782,47783,47784`；第二个窗口中 sequence
`205126,205128,205129,205130,205131,205127,205132` 对应连续 IP ID
`56091..56097`。由于 IP ID 在 TX engine 实际取包时递增，这排除了 FPGA 发包后由 ASIX/Windows
收包路径制造倒序的解释。

## 字节证据

Packet #40894，FPGA → PC，UDP 32000，64-byte payload：

```text
Offset  00 01 02 03 | 04 05 06 07 | 08 09 10 11 | 12 .. 19
Raw     55 50 46 31 | E2 42 9B 64 | 00 01 00 D1 | 00 01 66 92 FC B6 53 90
Field   magic       | run_id      | sequence     | send_timestamp_ns
Decode  UPF1        | 0xE2429B64  | 65745        | big-endian
```

完整 payload 原始字节保存在 `packets.json`；未对捕获字节做重排或重构。

## FPGA 内部三点 ILA 归因

使用开发专用 `udp_perf_diag_top` 在同一个 125 MHz 时钟域旁路观察三个边界：TEMAC RX client
AXIS、RX 业务消息口、TEMAC TX client AXIS。监视器仿真通过；诊断镜像实现结果为
`WNS=+0.327 ns`、`WHS=+0.056 ns`、阻断级 DRC 0。

硬件轮次 `run_id=0xD1A60001` 使用 64-byte payload、目标 50 Mbit/s、burst 32，实际发送/接收
934,694 包，loss 0、duplicate 0、corrupt 0，主机记录 reorder 225。ILA 捕获到：

| ILA sample | 边界 | 新完成 sequence | previous highest | reorder pulse |
|---:|---|---:|---:|---:|
| 124 | TEMAC RX client AXIS | `0x600` | `0x5FE` | 0 |
| 256 | TEMAC RX client AXIS | `0x5FF` | `0x600` | 1 |
| 190 / 322 | RX message | `0x600` / `0x5FF` | `0x5FE` / `0x600` | 0 / 1 |
| 297 / 429 | TEMAC TX client AXIS | `0x600` / `0x5FF` | `0x5FE` / `0x600` | 0 / 1 |
| 1342 / 1408 / 1515 | RX AXIS / RX message / TX AXIS | `0x601` | `0x600` | 0 |

三处顺序均为 `0x5FE, 0x600, 0x5FF, 0x601`。RX message 相对 raw RX 固定晚 66 cycles，TX
边界继续保持同一倒序；这直接排除 parser、RX ring、echo、TX ring 和 TX engine 自行重排。

证据文件：

- `udp_sequence_reorder_20260914.csv`，SHA-256
  `94360741FDA7B3CC8DF15990C45A615DE841F38E2F755E9821480B118CB6D839`；
- `udp_sequence_reorder_20260914.ila`，SHA-256
  `04342F2257DC2CE80186990D91C00246E05EBAF2707D98609229AAECB6B152DB`；
- 性能 JSON，SHA-256
  `03A07EB16FE63D1C01F3C94A7520B2DCEDB5B8DE40EE64910D2E25ECA179B392`。

## 最终归因边界

主机发送脚本在单一线程、单一 UDP socket 中按 sequence 顺序调用 `sendto()`；此前 pktmon 在
Host→FPGA 方向的已捕获窗口也保持有序，而 FPGA 最前端可见帧已经倒序。于是已证明的故障区间是
“pktmon/NDIS 发送捕获点之后，到 TEMAC RX client AXIS 之前”。点到点 Ethernet/SGMII 与 TEMAC
RX FIFO 只串行接收和 FIFO 转交帧，不具备按报文重排机制，因此工程结论为
`EXTERNAL_HOST_TX_ORDERING`，主要嫌疑是当前 ASIX USB 网卡驱动/发送卸载/USB 聚合路径。

当前 ASIX 为 `ASIX USB to Gigabit Ethernet Family Adapter`，驱动 `AxUsbEth.sys 4.20.1.0`
（2026-01-05），IPv4 IP/UDP checksum offload、LSO v2、EEE 均启用。要把外部根因继续细分到某一
offload 或适配器硬件，需要对这些特性做逐项、可恢复 A/B，或在铜线侧使用 TAP；这不影响“UDP
RTL 未制造倒序”的结论。

处置：该问题登记为已知外部测试环境缺口，不阻断后续吞吐、PPS、丢包、内容完整性、过载恢复与
长稳测试；每轮仍保留原始 reorder 数量，并以 `PASS_WITH_KNOWN_REORDER_GAP` 区别于严格 PASS。
当前 ASIX 链路不用于宣称顺序保证，loss、duplicate、corrupt 或收发错误仍是阻断项。

诊断后已恢复原 `udp_echo_test_top.bit`；14、256、1472-byte 单包回归全部通过。

## 复现命令

```powershell
python scripts/test_udp_performance.py --payload-bytes 64 --duration 8 --target-mbps 50 --label comb02_capture_64_50m
```

未完成检查：尚未用物理 TAP 区分 Windows/ASIX 驱动、USB 传输与适配器硬件，也尚未逐项关闭发送
offload 做 A/B；细分外部根因仍待验证，但 FPGA UDP 数据通路归因已经完成。
