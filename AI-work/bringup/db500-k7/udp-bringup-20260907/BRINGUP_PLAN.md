# UDP Bring-up 计划

## 过程规则

下列每个阶段均必须具备三类记录：执行前的计划、记录命令或板级操作及证据的执行记录、以及依据预定义标准作出的验收结论。不得因某阶段曾尝试过而允许后续阶段依赖它。

## 范围与顺序

| 顺序 | 阶段或 Demo | 计划：问题与安全行为 | 执行：受限工作 | 验收：所需证据与关卡 | 状态 |
|---:|---|---|---|---|---|
| 0 | 治理与环境预检 | 建立职责边界、输入来源、工具链、Git 远端、物理链路和被动 JTAG 身份；不得下载镜像或发包。 | 初始化 Git、登记输入资料、枚举主机网络和 JTAG 链。 | 文档已提交并推送；扫描识别出预期 FPGA 且未改变板卡状态。 | ACCEPTED |
| 0.1 | SGMII/PHY 硬件契约闭合 | 能否用权威资料确认 MGT116 通道、差分极性、参考时钟、PHY strap/MDIO/复位和 Demo 网络参数？不得创建 XDC、IP 或主动发包。 | 已只读审阅核心板/MCON 原理图和已解除占用的协议文档；未做任何主动硬件或网络操作。 | 每项事实均标记为“已确认”或明确阻塞；未确认项不得进入 XDC/IP。 | BLOCKED |
| 1 | configuration-safe | 能否构建并安全配置最小镜像？所有非必要输出必须保持安全。 | 契约关闭后，创建规范工程 Tcl、基础 XDC、时钟复位逻辑和安全 GPIO Demo。 | 适用时完成自检仿真、实现与时序证据、精确候选镜像身份和明确板级观测。 | PLANNED |
| 2 | clock-reset | 实际板级时钟和复位能否以声明频率工作？外部接口保持不活动。 | 将审核后的时钟约束和复位时序写入共享板级层。 | 所有声明时钟满足时序，板级观测证实复位退出确定。 | PLANNED |
| 3 | sgmii-link | FPGA 与 M88E1111 能否建立并维持预期以太网链路？不得执行协议命令。 | 仅在通道、极性和时钟事实确认后，配置 PHY 管理接口、SGMII PCS/PMA 和 MAC。 | 记录 MDIO 身份或状态、PCS 锁定、链路状态与错误计数。 | PLANNED |
| 4 | udp-smoke | 板卡能否在 ARP 和 IPv4 上回应受限 UDP 请求？回包数据必须静态或只读。 | 加入 ARP、IPv4、UDP 解析与封装，以及上位机测试脚本。 | 仿真协议判定器和抓包均显示正确的 ARP 与 UDP 回包。 | PLANNED |
| 5 | db500-protocol | 能否安全解析并响应 DB500 协议子集？只包含发现、信息和只读寄存器命令。 | 仅实现与解除锁定后的协议规范相符的字段。 | 上位机判定器和抓包与指定帧字段一致；不启用控制、采集、图像上传或远程升级命令。 | PLANNED |

## 阶段 0 执行记录

- Git：已初始化本地 main 分支，并设置远端为 https://github.com/meryglez529-commits/UDP.git。
- 工具链：Vivado 2021.1 位于 D:/Xilinx/Vivado/2021.1/bin/vivado.bat。
- 主机网络：ASIX USB 千兆网卡“以太网 2”为 Up，速率 1 Gbps；主机 IPv4 地址为 192.168.1.10/24；预检查询中接收报文错误数为零。
- 被动 JTAG 扫描：Vivado 打开了一个目标 localhost:3121/xilinx_tcf/Digilent/E3077BAA4210，并发现一个器件 xc7k325t_0，型号为 xc7k325t。随后已关闭目标和 Hardware Manager；未执行 bitstream、LTX、寄存器写入、复位或 ILA 捕获。
- 输入完整性：已记录三份可读取 PDF 的 SHA-256。协议 Word 文件被其他程序占用，已登记为待处理。

## 阶段 0 验收记录

- 标准：过程记录、输入登记、板卡契约、矩阵、计划与首个 UDP Demo 计划已提交并可在 origin/main 查看。
- 结论：ACCEPTED
- 证据：Git 提交 d5725bf，说明为 chore: establish UDP FPGA bring-up workflow，已于 2026-09-07 推送至 origin/main。该提交记录了环境预检；根据后续用户范围调整，根目录的 Word/PDF 输入资料仅保留本地且不再由当前分支跟踪，过程记录继续保留在 Git。

## 阶段 0.1 执行与验收记录

- 计划：已由 `PHASE_0_1_CONTRACT_CLOSURE.md` 固化，并在执行前以提交 `08f9121` 推送至 `origin/main`。
- 执行：协议 Word 已可读且已登记 SHA-256；确认 DB500 寄存器 UDP 端口 32000、ARP 扩展发现和三类大端载荷帧。确认 M88E1111 PHY 端 SGMII P/N、MDIO/MDC/INTN/RESETN 网络，以及 MGT116 的时钟对和 TX/RX 资源。未创建 XDC/IP/RTL，未下载、未写 MDIO、未发包。
- 验收：BLOCKED。核心板和 MCON 原理图没有给出 SGMII 到某一 MGT116 lane 的端到端对应、GT 端极性或有效参考频率；也没有给出 PHY strap/MDIO 地址/复位时序、实物板版本或部署 MAC/IP/UDP 校验策略。详见 `PHASE_0_1_CONTRACT_CLOSURE.md` 与 `OPEN-QUESTIONS.md`。

## 产品基线提升计划

| 已验证资产 | 预期类别 | 规范位置 | 产品使用方 |
|---|---|---|---|
| 审核后的板卡引脚和时钟约束 | BOARD_FACT | fpga/boards/db500-k7/constraints/ | 所有 Demo 与产品 |
| 时钟和复位控制器 | REUSABLE_CORE | fpga/common/clock_reset/ | 所有同步设计 |
| SGMII PCS/PMA 与 MAC 配置 | VENDOR_CONFIG | fpga/boards/db500-k7/ip/ | UDP 产品 |
| ARP/IP/UDP 传输层 | REUSABLE_CORE | fpga/common/udp_transport/ | UDP 产品 |
| 协议解析器和软寄存器映射 | REUSABLE_CORE | fpga/product/rtl/ | DB500 协议产品 |
| GPIO 与初始链路测试顶层 | TEST_ONLY | Demo 专用路径 | NONE |

## 授权边界

- 正式源码写入：仅当相关契约行达到“已确认”且该阶段获得执行授权后，方可写入 fpga/。
- 板卡下载和主动网络发包：本准备阶段未授权。
- 硬件故障边界：保留一次决定性观测，在 hardware-handoff/ 记录后停止无法区分根因的 FPGA 修改。
- 输入资料策略：根目录的 Word/PDF 是本地证据，不纳入 Git；在 SOURCE_REGISTER.md 中登记其来源、版本和可获得的哈希。
