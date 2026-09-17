# DB500 UDP CONTROL 开发记录

状态：`CONTROL_V1_WATCHDOG_TEST_BANK_BOARD_VERIFIED`

## 1. 本轮交付范围

按照 `MODULE.md` 实现 CONTROL V1，并在共享 Vivado 工程
`D:\MyFPGAProject\UDP\fpga\led\led.xpr` 中完成仿真、综合实现、bitstream、JTAG 易失下载、
协议抓包和主机板级测试。

本轮板级镜像使用独立测试寄存器适配器，不接产品业务寄存器。产品寄存器路由和业务寄存器表
仍是后续集成项；CONTROL 静默 watchdog 已完成通信代际恢复，不增加线上复位指令。

## 2. 实现内容

CONTROL 核心按单一职责拆分为：

- `db500_ctrl_rx_decoder.v`：固定 16-Byte 请求收集、格式检查和规范化。
- `db500_ctrl_window.v`：W=4 有序窗口、完整 64-bit 标签、去重、结果保存、重放和 fail-stop。
- `db500_ctrl_reg_executor.v`：单一寄存器请求/结果握手事务。
- `db500_ctrl_rsp_select.v`：四槽 pending 结果的轮询选择。
- `db500_ctrl_tx_encoder.v`：结果副本锁存并编码成 UDP descriptor 与 16-Byte payload。
- `db500_ctrl_stats.v`：饱和诊断计数器。
- `db500_ctrl_watchdog.v`：500 ms CONTROL 静默检测、32 周期软复位和代际诊断。
- `db500_udp_control.v`：只连接以上六个原子子模块，不实现产品寄存器语义。
- `db500_ctrl_test_reg_bank.v`：板级验收用测试寄存器；含两个 RW scratch、签名和写计数。
- `udp_control_test_top.v`：现有 UDP transport、CONTROL 核心和测试寄存器适配器的板级外壳。

`udp_top.v` 现在分别导出基础复位并组合
`comm_resetn_o = comm_base_resetn_o && comm_soft_resetn_i`。watchdog 只由基础复位清空；其软复位
清空 UDP transport、CONTROL 和测试适配器事务状态，Ethernet client FIFO 和测试寄存器存储值
保持。`udp_echo_test_top.v` 以常量 1 关闭软复位输入并保留原回归入口。

配套入口：

- `fpga/led/scripts/run_db500_control_sim.tcl`
- `fpga/led/scripts/build_udp_control.tcl`
- `fpga/led/scripts/program_udp_control.tcl`
- `fpga/led/scripts/test_udp_control.py`
- `fpga/led/scripts/audit_db500_control_v1.py`

## 3. 仿真结果

所有仿真均使用 Vivado/XSim 2021.1，结果如下：

| 范围 | 结果 | 证据 |
|---|---|---|
| CONTROL 组合仿真 | PASS | `fpga/led/logs/db500_control_sim_20260916_222713.log` |
| 既有 UDP transport 回归 | PASS | `fpga/led/logs/udp_transport_control_regression_20260916_222813.log` |
| 既有 UDP echo 回归 | PASS | `fpga/led/logs/udp_echo_control_regression_20260916_222854.log` |
| CONTROL + watchdog 最终回归 | PASS | `fpga/led/logs/db500_control_watchdog_sim_post_boundary_20260917_095922.log` |
| UDP transport 最终回归 | PASS | `fpga/led/logs/run_udp_transport_sim_20260917_094911.log` |
| UDP RX/TX ring 最终回归 | PASS | `fpga/led/logs/run_udp_payload_ring_sim_20260917_094911.log` |
| UDP echo 最终回归 | PASS | `fpga/led/logs/run_udp_echo_sim_20260917_094911.log` |

CONTROL testbench 覆盖基本 QUERY/SET、错误长度、`3,1,2` 乱序、执行前/后的重复请求、回复重放、
TX backpressure、寄存器适配器 ERROR、同号不同内容冲突和 UDP TX 契约故障。新增 watchdog 单元与
集成测试覆盖 FRESH/ACTIVE/RESET、活动重装、精确保持周期、无空闲反复复位、跨代编号重启、
故障锁存清除和寄存器值保持。最终标志为 `RESULT=DB500_CONTROL_SIM_PASSED`。

## 4. 综合、实现和 bitstream

- 构建 top：`udp_control_test_top`
- 专用 run：`synth_udp_control`、`impl_udp_control`
- 构建结果：`RESULT=DB500_CONTROL_BUILD_PASSED`
- WNS：`+0.445 ns`
- WHS：`+0.079 ns`
- timing failing endpoints：0；内部最大延时未约束端点：0；无时钟寄存器/锁存器：0
- blocking DRC：0
- 全 top：4417 LUT、4690 FF、5 RAMB36
- `db500_udp_control`：1606 LUT、1090 FF、0 BRAM；独立 watchdog：56 LUT、68 FF、0 BRAM

实现报告：`fpga/led/led.runs/impl_udp_control/reports/`。
最终构建日志：`fpga/led/logs/db500_control_watchdog_build_final_20260917_100051.log`。

DRC 保留 20 条 `REQP-1839 RAMB36 async control check` Warning，来自既有 Ethernet MAC FIFO 和
UDP RX ring 的 RAMB 控制路径；另有 1 条 `CHECK-3` 表示该规则达到报告上限。没有阻塞 DRC 或
Critical Warning。本轮没有把这些既有复位结构混入 CONTROL 核心重构。

生成镜像：

```text
D:\MyFPGAProject\UDP\fpga\led\led.runs\impl_udp_control\udp_control_test_top.bit
SHA-256 021B0DC22234F45FE71F9131F5B87C122A9BBC6CAB26B409ECFEE7AAC559076A
```

## 5. JTAG 与板级功能测试

JTAG 清单和下载均使用唯一目标
`localhost:3121/xilinx_tcf/Digilent/E3077BAA4210`、唯一器件 `xc7k325t_0`，器件型号
`xc7k325t`。下载脚本逐次核对 `PROGRAM.FILE`，镜像中没有 ILA/VIO。

板级主机接口为 ASIX USB 千兆网卡 `以太网 2`：

- 主机 MAC：`9C-69-D3-1A-4C-6D`
- 主机：`192.168.1.10:32000`
- FPGA：`192.168.1.20:32000`
- 链路：1 Gbit/s

最终 60 秒板级测试结果：

```text
PASS initial_window ids=1..4
PASS reordered_window arrival=7,5,8,6 execution=5,6,7,8
PASS lost_response_replay write_count=4
PASS stress requests=1497887 elapsed_s=60.000 rate=24964.7_requests_per_s
PASS fail_stop subsequent_request_blocked
PASS watchdog_recovery request_id_restarted=1 scratch0=0x90090009 write_count=4 reset_count=1
RESULT=DB500_CONTROL_HOST_TEST_PASSED
```

实测吞吐 `24,964.7 requests/s`，是 5,000 requests/s 验收门槛的 4.99 倍。最终测试日志：
`fpga/led/logs/db500_control_watchdog_board_acceptance_20260917_100601.log`。

fail-stop 后主机停止全部 CONTROL 650 ms，watchdog 自动结束旧代际。随后用同一 SHA-256 镜像
重新下载并独立完成普通空闲跨代验收；读取诊断后又保持超过 500 ms 静默，板卡当前停留在
FRESH 状态。最终下载日志：
`fpga/led/logs/db500_control_watchdog_program_quiet_acceptance_20260917_100942.log`；普通空闲跨代日志：
`fpga/led/logs/db500_control_watchdog_quiet_acceptance_20260917_101017.log`。

## 6. 线路抓包审计

抓包文件：
`AI-work/reports/packet-audit/20260916-control-timeout/capture.pcapng`，SHA-256：
`5981E6FCBDF18E61BABE8540C00C4620E14FCC21A3093D9C08AA5456C616697B`。

抓包包含 23 个 CONTROL 报文，全部符合当前 16-Byte 格式。可见请求按 `7,5,8,6` 到达而回复按
`5,6,7,8` 发出；SET 9 原样重发后取得相同回复，QUERY 10 返回写计数 4，证明 SET 9 没有再次
访问寄存器。当前格式的确定性审计结果为
`RESULT=DB500_CONTROL_PACKET_AUDIT_PASS`。

报告入口：
`AI-work/reports/packet-audit/20260916-control-timeout/report/REPORT.md` 和同目录 `report.html`。

通用审计器最初使用旧版 `0x5555/0xAAAA` payload profile，曾将这 23 个新格式报文错误标记为
FAIL；该输出已经由 `audit_db500_control_v1.py` 按当前 `MODULE.md` 和 RTL 重新解码覆盖，不能再用
旧协议 profile 审计 CONTROL V1。

## 7. 恢复路径实测结论

早期试验已证明 Windows 禁用/启用 ASIX 网卡不能作为 FPGA 通信代际复位条件，因此最终实现不再
依赖主机网卡状态或物理链路重建。CONTROL watchdog 在首次活动后监视 500 ms 完全静默，产生
32 个 125 MHz 周期的软复位，清空 UDP/CONTROL 事务状态并回到 FRESH。

第一次板级尝试把运行时软复位同时接入 TEMAC client FIFO，静默后链路仍为 Up/1 Gbit/s，但
CONTROL 不再响应。由此将复位边界修正为 UDP transport 及其上层；Ethernet client FIFO 留在链路
复位域。修正后已同时验证普通空闲跨代和 fail-stop 跨代：`request_id=1` 可重新执行，scratch 与
写计数保持，watchdog `reset_count=1`。

当前恢复契约只解决 FPGA 内部仍可运行时的通信状态问题。时钟停止、PCS/PMA 失效、FPGA 逻辑
停止或物理硬件故障仍需掉电、JTAG 或人工处理。

## 8. 后续集成项

2026-09-17 当前顺序调整：产品寄存器接入暂缓，先推进透明 DATA 通道、双端口隔离、Jumbo 与
差异化缓存设计；DATA 交付完成按 TX 队列提交定义，现有测试 bank 可继续支撑共存验证。
详见用户通信架构与 DATA MODULE.md。

1. 实现 `db500_register_router`、`db500_register_bank` 或等价适配层，把旧协议文档中的产品寄存器
   信息放到寄存器层，不放进 CONTROL 协议核心。
2. 用产品寄存器适配器替换测试 bank 后，重新运行 CONTROL 仿真、UDP 回归、实现和板级测试。
3. DATA 通道不以产品寄存器接入为前提，不修改当前 CONTROL V1 记录格式；双通道集成后验证
   CONTROL 静默复位不打断 DATA，以及 DATA 满载时 CONTROL 的响应和恢复。
