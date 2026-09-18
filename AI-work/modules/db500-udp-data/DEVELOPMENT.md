# DB500 UDP DATA 开发记录

状态：`RTL_IMPLEMENTED_BUILT_AND_BOARD_VERIFIED`

## 1. 实施范围

按 `MODULE.md` 在共享工程 `D:\MyFPGAProject\UDP\fpga\led\led.xpr` 内实现 DATA 通道、
CONTROL/DATA 双端口分流、共享发送仲裁、Jumbo 路径及 1G 全双工链路准入。实现不依赖产品
寄存器接入；板级外壳继续使用 CONTROL 测试寄存器 bank 和透明 DATA 回显器。

## 2. 已完成实现

- 新增 `udp_data_rx_ring`：32 KiB 可变长度字节环、16 条描述符、整包 reserve、commit/abort 和
  同步 BRAM 读取。
- 新增 `udp_data_tx_ring`：请求/数据/取消/结果接口，提交与 Ethernet FIFO 复制完成后的释放分离。
- 新增 `udp_data_ring_tb`，覆盖提交、回滚、顺序读取、非法长度、错误 last 和取消。
- 新增 `fixed_host_rx_parser_dual`、`fixed_host_tx_engine_dual` 和 `udp_transport_dual_host`：共享
  Ethernet/IPv4/UDP parser 与发送 engine，按 32000/32001 分流，CONTROL 有界优先，ARP/DATA
  低优先级轮询，CONTROL watchdog 清理不复位 DATA。
- `udp_top` 已改接双端口 transport；`udp_data_test_top` 保留 CONTROL 测试寄存器 bank，并以
  `udp_data_echo_bridge` 对 DATA payload 做透明回环。
- TEMAC client RX/TX FIFO 地址宽度从 12 bit 扩到 14 bit，每方向 16 KiB；MAC RX/TX Jumbo
  配置已开启。`ethernet_link_speed_ctrl` 仅在协商为 1G 全双工时开放通信。

## 3. 仿真证据

2026-09-17 使用 Vivado 2021.1/XSim 在同一工程运行：

| 检查 | 结果 | 证据 |
|---|---|---|
| DATA RX/TX ring | reserve/commit/abort/release、非法长度、错误 last、取消、顺序读出通过 | `RESULT=UDP_DATA_RING_PASSED` |
| 双端口 transport | CONTROL 16 Byte RX、DATA 8172 Byte RX、坏 checksum 丢弃、DATA 8972 Byte TX、CONTROL 复位隔离通过 | `RESULT=UDP_TRANSPORT_DUAL_HOST_PASSED` |
| DATA 回归总结果 | 以上两项均通过 | `fpga/led/logs/udp_data_sim_20260917_193338.log`，`RESULT=UDP_DATA_SIM_PASSED` |
| 1G-only 准入 | 100M/10M 不开放通信，重新协商 1G 后恢复 | `fpga/led/logs/ethernet_speed_sim_20260917_192902.log`，`RESULT=ETHERNET_SPEED_SIM_PASSED` |
| CONTROL 回归 | 核心、watchdog、watchdog 集成三项通过 | `fpga/led/logs/db500_control_sim_20260917_194825.log`，`RESULT=DB500_CONTROL_SIM_PASSED` |

## 4. 构建证据

`scripts/build_udp_data.tcl` 使用独立 `synth_udp_data` / `impl_udp_data` run 构建
`udp_data_test_top`：

| 项目 | 结果 |
|---|---:|
| Vivado | 2021.1 |
| 器件 | `xc7k325tffg676-2` |
| WNS / WHS | `+0.371 ns` / `+0.021 ns` |
| 阻断 DRC | 0 |
| Slice LUT / Register | 5347 / 5030 |
| Block RAM Tile | 28 |
| bitstream SHA-256 | `5CFFD530AA1F40B72192A92821595C6D41CABF26F6684FC18C0E327C73531911` |

构建日志为 `fpga/led/logs/build_udp_data_20260917_192958.log`；bitstream 为
`fpga/led/led.runs/impl_udp_data/udp_data_test_top.bit`。扩容后的官方 FIFO 保留其原有
REQP-1839/1840 BRAM 异步复位警告，未产生 Error 或 Critical Warning。

## 5. 上板证据

`scripts/program_udp_data.tcl` 将上述 bitstream 下载到唯一 JTAG 设备 `xc7k325t_0`，器件核对为
`xc7k325t`，PROGRAM.FILE 回读一致；日志为
`fpga/led/logs/program_udp_data_20260917_193939.log`。

主机 `192.168.1.10` 使用 ASIX USB 千兆网卡，实测链接为 1 Gbps，驱动 `JumboPacket=9KB`。
`scripts/test_udp_data.py --jumbo-count 256` 对 FPGA `192.168.1.20` 执行并通过；记录为
`fpga/led/logs/test_udp_data_20260917_194604.log`：

- DATA 端口 32001 原样回环 1、2、7、64、1472、8160、8172、8972 Byte payload。
- 连续 256 个 8972-Byte Jumbo payload 全部逐字节一致。
- 16 轮 8172-Byte DATA 与 CONTROL 查询并发，两个端口均收到正确回复。
- CONTROL watchdog 超时复位后，8972-Byte DATA 仍可回环，CONTROL 从 request_id 1 恢复。

最终标志为 `RESULT=DB500_DATA_BOARD_TEST_PASSED`。

## 6. 当前边界

本次板测使用透明 DATA 回环器和 CONTROL 测试寄存器 bank，尚未接 ADC、DDR、图像/RTM 组包器
或产品寄存器。已验证 1G 直连、MTU9000、最大 payload、双端口共存和 watchdog 隔离；业务源
持续线速、长时间丢包率和产品侧跨时钟适配由后续业务接入测试覆盖。
