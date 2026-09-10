# M88E1111 MDIO 模块

状态：`IMPLEMENTED_AND_VERIFIED`

## 目的与依据

该模块通过 Clause 22 MDIO 只读访问 M88E1111，确认 PHY 身份、启动模式和自协商状态。
启动绑带来自 MCON 原理图第 9 页与 Marvell *Alaska 88E1111 Datasheet* Rev. M（Table
32/34/35）；PHY 地址为 `0x07`，`HWCFG_MODE=0100`，`ANEG=1110`，选择 MDC/MDIO 管理接口。

## 设计层次与文件

```text
led_static.v
├── IOBUF（A14/MDIO：低电平或释放）
└── m88e1111_runtime_probe.v
    └── mdio_clause22_reader.v
```

已登记输入：

- `fpga/led/led.srcs/sources_1/new/m88e1111_runtime_probe.v`
- `fpga/led/led.srcs/sources_1/new/mdio_clause22_reader.v`
- `fpga/led/led.srcs/sim_1/new/mdio_clause22_model.v`
- `fpga/led/led.srcs/sources_1/ip/ila_mdio/ila_mdio.xci`

## 接口和实现要点

| 信号/参数 | 设计 |
|---|---|
| `sys_clk_i` | 100 MHz；探针产生约 1 MHz MDC |
| `mdc` | FPGA `B14`，Bank 16，`LVCMOS33` |
| `mdio` | FPGA `A14`，Bank 16，`LVCMOS33`；板端上拉，FPGA 不主动输出高电平 |
| PHY 地址 | `5'h07` |
| 事务 | 只读寄存器 2、3、27、0、4、9、1、1；BMSR 连读两次 |
| 复位/写入 | 不驱动 PHY reset，不写 PHY 寄存器，不写 Flash |

端到端路径为 `B14/A14 → CORE HT2.A53/A54 → MCON J6.B54/B55 → U82 → PHY`。这里按共同
网络名 `B16_L21_P/N` 对接；`E13/E12` 是另一组 `B16_L18_P/N`，不作为 PHY 管理端点。

## 验证结果

- S：`led_static_tb` 的 MDIO 从机模型检查前导码、Clause 22 字段、`TA=Z0`、三态释放、
  BMSR latch-low 双读和寄存器值。
- B：更正为 B14/A14 后，同一 `led.xpr` 的综合、实现、时序和 DRC 通过，生成匹配的
  `.bit` 与 `.ltx`。
- H：同一镜像下载后 ILA 读回 `PHYID=0x0141_0CC2`、reg27=`0x8484`（`[3:0]=0100`）、
  BMCR 自协商使能为 1、BMSR 双读=`0x796D`（Link=1、AN Complete=1）。原生采集在
  `D:\MyFPGAProject\UDP\fpga\led\led.hw\hw_1\`。

先前 E13/E12 的低电平和 `0x0000` 采集只覆盖错误网络，已作废；保留在
`AI-work/history/legacy-2026-09-08/` 供追溯，不与当前 PHY 结论混用。

## 边界与后续

当前模块只负责只读管理和观测，不负责 SGMII 数据面、PHY 模式重配或网络协议。若后续需
写寄存器、复位 PHY 或读取中断，先在本模块记录接口和时序设计，再更新顶层架构与工程输入。
