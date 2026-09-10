# M88E1111 运行态验证计划

> 修订（2026-09-08）：首次执行把相对插接的 J6/HT2 按同一 A/B 行号机械对应，错误使用 E13/E12。已按 `B16_L21_P/N` 网络名重新闭合为 B14/A14，旧硬件采集已作废。用户已确认按本修订重新构建、JTAG 易失下载和只读 ILA 验证；范围与禁止项保持不变。

## 1. 目标与范围

在既有 Vivado 工程 `D:\MyFPGAProject\UDP\fpga\led\led.xpr` 中实现一个最小 Clause 22 MDIO **只读**探针，并在板卡上验证 M88E1111 的实际响应、工作模式与铜口协商状态。

本工作包验证下列运行态事实：

| 验证项 | 期望值 / 判定 |
|---|---|
| PHY 地址 | 绑带译码为 `0x07`；扫描可作为只读兜底，但不能用扫描结果篡改硬件地址结论。 |
| PHY 身份 | 地址 `0x07` 的寄存器 2 / 3 返回有效 PHY ID；不得为全 `0x0000` 或全 `0xFFFF`。 |
| 接口模式 | 寄存器 27 `[3:0] = 0100`，即 *SGMII without clock with SGMII Auto-Negotiation to copper*。 |
| 铜口自协商使能 | BMCR（寄存器 0）Auto-Negotiation Enable 位为 1。 |
| 铜口链路与协商 | BMSR（寄存器 1）双读后记录 Link Status 与 Auto-Negotiation Complete；需要接入一台千兆自协商对端才可判定为通过。 |
| MDIO 波形 | ILA 看到 Clause 22 读帧、`TA=Z0`、MDIO 在数据阶段由 PHY 驱动，并捕获全部读回字。 |

本工作包**不**实现 UDP、以太网 MAC、SGMII PCS/PMA、GT 收发、ARP/ICMP，也不验证数据帧收发。它只验证 M88E1111 的 MDIO 可达性和 PHY 运行配置；SGMII 实际收发和 UDP 由后续工作包完成。

## 2. 已确认的硬件事实

| 事实 | 证据 | 可用于本计划的结论 |
|---|---|---|
| U79 复位后模式 | `AI-work/history/legacy-2026-09-08/diagnostics/m88e1111-mode-2026-09-08/TRACEABILITY.md` | `HWCFG_MODE=0100`、`ANEG=1110`、MDIO 地址 `0x07`、`SEL_TWSI=0`（MDC/MDIO）。 |
| PHY 侧管理网络 | MCON 原理图第 9 页 | `PHY_MDC_L`、`PHY_MDIO_L`、`PHY_INT_L`、`PHY_RESET_L` 存在；本次只使用 MDC/MDIO。 |
| 跨板管理路径 | MCON 原理图第 4 页 + CORE 原理图第 10 页 + `AI-work/history/legacy-2026-09-08/diagnostics/m88e1111-mdio-pin-mapping-2026-09-08/PIN_MAPPING_CORRECTION.md` | U82 `TXS0104` 将 PHY 侧 2.5 V 管理网络转换至 `B16_L21_P/N`；MCON J6.B54/B55 依网络名对应 CORE HT2.A53/A54，因此 `MDC=B14`、`MDIO=A14`，均位于 Bank 16。 |
| MDIO IO 电平 | 用户确认 + `AI-work/history/legacy-2026-09-08/HARDWARE_ENVIRONMENT-legacy.md` | Bank 16 为 3.3 V；MDC/MDIO 使用 `LVCMOS33`。MDIO 保持三态/开漏。 |
| 既有工程 | `fpga/led/led.xpr` | 器件 `xc7k325tffg676-2`；现有 `led_static.v`、`led_static.xdc` 和 LED ILA 均保留在同一工程。 |
| 可用系统时钟 | `AI-work/history/legacy-2026-09-08/HARDWARE_ENVIRONMENT-legacy.md`，AA3 | `sys_clk_i` 为 100 MHz、Bank 34 `LVCMOS15`；可生成不高于 1 MHz 的 MDC。 |

### 已闭合的实施前硬件门槛

原理图交叉核对已闭合本工作包所需的两个管理 IO：`PHY_MDC_L → B14`、`PHY_MDIO_L → A14`，两者均为 Bank 16 / 3.3 V / `LVCMOS33`。MCON 第 9 页显示 MDIO 具有板端 4.7 kohm 上拉，RTL 必须以 `IOBUF` 的低电平或高阻两种状态驱动。

`PHY_RESET_L` 与 `PHY_INT_L` 不属于首轮驱动范围，因此 Reset 端点和复位时序不阻塞只读 MDIO 验证。

## 3. 拟议工程改动（仅在用户确认计划后）

所有改动仅在 `led.xpr` 注册，不建立平行 Vivado 工程。

| 输入 | 拟议改动 | 目的 |
|---|---|---|
| `led.srcs/sources_1/new/` | 新增 `mdio_clause22_reader` 与 `m88e1111_runtime_probe` RTL；将现有 LED 静态功能保留 | 从 100 MHz 产生 1 MHz MDC，执行标准 Clause 22 读操作，MDIO 使用三态/开漏输出。 |
| `led_static.v` | 仅扩展顶层端口并例化探针；保留 `led1=1` | 连接 `sys_clk_i`、MDC、MDIO 和调试状态。 |
| `led_static.xdc` | 将 MDC 更正为 B14 / `LVCMOS33`，MDIO 更正为 A14 / `LVCMOS33`；保留既有时钟约束，不添加复位、INT 或猜测性约束 | 使管理接口连接到正确的 PHY 管理网络。 |
| `scripts/capture_mdio_*.tcl` | 仅将本轮 ILA 导出基名加上 `b14a14` 标识；增加对既有自主只读事务的 ILA 触发器 | 保留旧 E13/E12 采集作为可追溯的无效证据，不覆盖原始 CSV/ILA；采集不同寄存器窗口以覆盖自协商和 BMSR 双读。 |
| `led.srcs/sources_1/ip/` | 新增或调整 ILA，使其观察 MDIO 状态机、帧阶段、OE、MDC、MDIO 采样值、寄存器号、读回字、完成/错误标志 | 生成可审计的板级波形证据。 |
| `led.srcs/sim_1/` | 新增 MDIO 从机行为模型与 testbench | 在构建前验证 preamble、`ST`、`OP`、PHY 地址、寄存器地址、`TA=Z0`、数据采样及三态切换。 |

### MDIO 事务序列

探针只发送 Clause 22 **读**命令，MDC 设置为 1 MHz（低于 2.5 MHz 上限）。每轮按如下顺序执行，并将原始 16 位值保存至 ILA：

1. 可选只读地址扫描：PHY 地址 0-31 的寄存器 2 / 3，仅用于识别异常装配或地址译码不一致；正常判定仍以 `0x07` 为目标。
2. 地址 `0x07`：读取寄存器 2（PHYID1）、寄存器 3（PHYID2）。
3. 读取寄存器 27，检查 `[3:0]` 是否为 `0100`。
4. 读取寄存器 0（BMCR）、4（ANAR）、9（1000BASE-T Control），记录自协商使能和通告能力。
5. 连续读取寄存器 1（BMSR）两次，避免 Link Status 的 latch-low 语义造成假阴性；记录第二次的 Link 与 Auto-Negotiation Complete 位。
6. 释放 MDIO 为高阻态并保持空闲；不向任何寄存器写入数据。

首次上板**不驱动** `PHY_RESET_L`，不重启协商、不改变模式。只有当读回证明模式被其他软件覆盖，才另行提出写寄存器/复位计划并等待新的确认。

## 4. 执行流程

### S - 仿真

在 `led.xpr` 已注册的 `sim_1` fileset 中运行行为仿真。MDIO 从机模型固定返回与本板绑带一致的模式字和可控的 BMSR 场景。

通过条件：读帧字段、转向、采样边沿和读回寄存器字均与模型一致；测试必须覆盖 BMSR 的第一次为 latch-low、第二次为有效值的场景。仿真原生产物保留于 `D:\MyFPGAProject\UDP\fpga\led\led.sim\`，工作包只记录路径和结论。

### B - 构建

本次仅变更 XDC 引脚约束，既有行为仿真不受影响，不重跑 S。重新运行 `synth_1`、`impl_1` 与 bitstream 生成。验证 B14/A14 的 IO 位置、`LVCMOS33`、DRC、时钟约束与时序；生成的 `.bit`、`.ltx`、报告保留于 `D:\MyFPGAProject\UDP\fpga\led\led.runs\impl_1\`。

### H - 板级只读验证

在用户确认本计划后：

1. 检查本次使用的 `led.hw` 工作区没有被占用；连接电源和 JTAG，目标为 `xc7k325t`。
2. 易失下载本次 `impl_1` 生成且与 `.ltx` 匹配的镜像；不写 Flash。
3. 连接已知可自协商的千兆交换机或 PC；记录是否已接线。无对端时仍可完成 ID/模式/BMCR 验证，但链路和协商完成只能标为未验证。
4. 触发 ILA，采集一次成功的寄存器读取轮次；原生 `.ila` 留在 `led.hw`。
5. 导出原始寄存器读回、ILA 核标识、镜像与 `.ltx` 的绝对路径到本工作包 `out/hardware/`，并按第 5 节判定。

**板级影响：** 此步骤会易失覆盖 FPGA 当前配置，并会驱动 MDC/MDIO 发起只读管理事务；不会写 PHY 寄存器、复位 PHY、发送以太网帧或写入非易失存储器。

## 5. 验收标准

| 等级 | 通过条件 | 失败 / 限制处理 |
|---|---|---|
| A. 管理可达 | 地址 `0x07` 读到有效 PHY ID，ILA 显示正确 Clause 22 波形与 turnaround | 无响应、全 0 或全 1：记录波形，检查端点、VCCO、MDIO OE 和 PHY 复位状态；不写寄存器。 |
| B. 模式正确 | 寄存器 27 `[3:0]=0100` | 值不同：报告运行配置被覆盖；不自行改写。 |
| C. 自协商配置正确 | BMCR 的 AN enable=1，ANAR/寄存器 9 与读回结果已记录 | 不满足：报告，后续改写需新计划。 |
| D. 实际铜口链路 | 有千兆自协商对端时，BMSR 双读后 Link=1 且 Auto-Neg Complete=1 | 未接线或对端不兼容：A-C 可 PASS，D 标为 PARTIAL/未验证。 |

本工作包整体 `PASS` 需 A、B、C 全部通过；D 的要求取决于执行时是否具备已记录的合格对端。它不等价于 SGMII 帧收发或 UDP 可用。

## 6. 计划边界与授权点

- 本修订仅修改既有 XDC 的 MDC/MDIO 管脚；不改变 RTL、ILA/IP、testbench 或工程设置。
- 用户已于 2026-09-08 确认本修订后，允许修改上述 XDC、运行 B、易失下载和 ILA 捕获。
- PHY 配置写入、PHY 复位、模式重配、网络发包、Flash 写入均不在本计划授权范围内。
