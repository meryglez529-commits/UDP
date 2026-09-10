# LED 模块

状态：`IMPLEMENTED`

## 目的

提供一个最小、可回退的板级指示设计：`LED1` 由 FPGA 输出固定高电平，经 MCON 的低端
开关点亮。`led_static` 可以作为独立验证顶层，并承载 M88E1111 只读探针和两个 ILA；工程
当前选择的 active top 以 [`../../ARCHITECTURE.md`](../../ARCHITECTURE.md) 为准。

## 设计层次与文件

```text
led_static.v（独立验证候选顶层）
├── assign led1 = 1'b1
├── m88e1111_runtime_probe（见 ../m88e1111-mdio/MODULE.md）
├── ila_led
└── ila_mdio
```

工程输入均登记在 `D:\MyFPGAProject\UDP\fpga\led\led.xpr`：

- RTL：`led.srcs/sources_1/new/led_static.v`
- 约束：`led.srcs/constrs_1/new/led_static.xdc`
- 仿真顶层：`led.srcs/sim_1/new/led_static_tb.v`
- 调试 IP：`led.srcs/sources_1/ip/ila_led/ila_led.xci`、`ila_mdio/ila_mdio.xci`

## 接口与约束

| 端口 | FPGA 资源 | 约束/含义 |
|---|---|---|
| `led1` | `A18` / Bank 15 | `LVCMOS33`；高电平点亮，路径为 `LED1→J7.A36→HT3.B36→A18` |
| `sys_clk_i` | `AA3` / Bank 34 | `LVCMOS15`，100 MHz；仅作为 RTL 和 ILA 时钟，不代表 GT 参考时钟 |
| `mdc` | `B14` / Bank 16 | `LVCMOS33`；由 M88E1111 探针驱动 |
| `mdio` | `A14` / Bank 16 | `LVCMOS33`；顶层 `IOBUF` 只输出低电平或高阻 |

`led_static.xdc` 还定义了 Configuration Bank 0 的 `CFGBVS=VCCO`、`CONFIG_VOLTAGE=3.3`。

## 验证记录

- S：`led_static_tb` 自检 MDIO 探针，同时确认 LED 顶层可仿真；原生结果在
  `D:\MyFPGAProject\UDP\fpga\led\led.sim\`。
- B：当前 `synth_1`、`impl_1`、DRC 和 bitstream 已完成；`.bit`/`.ltx` 在
  `D:\MyFPGAProject\UDP\fpga\led\led.runs\impl_1\`。
- H：LED ILA 与 M88E1111 正确端点采集使用同一工程的 `led.hw`；原始 `.ila`/CSV 在
  `D:\MyFPGAProject\UDP\fpga\led\led.hw\hw_1\`。板上镜像是否仍与当前输入匹配，使用前重新核对。

## 设计决定与后续

LED 固定高电平是可观察的基础回退状态，不承担 UDP 功能。网络顶层确定后，LED 逻辑可以
作为子模块保留，或由新的顶层例化；届时同步更新 `ARCHITECTURE.md` 和本文件的层次关系。
