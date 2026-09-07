# Demo 状态

以下 State 行为校验器读取的机器字段，状态码保持英文。

- State: PLANNED
- Demo：udp-smoke-v1
- 接口：通过 M88E1111 SGMII 链路实现 ARP、IPv4 与 UDP 回包
- 正式源码路径：fpga/demos/udp-smoke/
- 顶层 / FPGA：NOT_CREATED / XC7K325T-2FFG676I
- 工具 / 版本：Vivado 2021.1
- 候选镜像：NONE
- 合格镜像：NONE

## 阶段证据

| 阶段 | 状态 | 命令或过程 | 证据 | 结论 |
|---|---|---|---|---|
| 计划 | ACCEPTED | REQUIREMENTS.md 与 ARCHITECTURE.md | 当前计划单元 | 范围限制为安全的 ARP/UDP 回包 |
| 契约 | OPEN | 核对 SGMII 参考时钟、PHY 控制、MAC/IP/端口；MGT116 lane 3 与极性已确认 | BOARD_CONTRACT.md 与 OQ-003 至 OQ-005 | 不允许实现 |
| 仿真 | NOT_RUN | 后续自检以太网报文测试平台 | NONE | NOT_RUN |
| 综合 | NOT_RUN | 后续源码驱动的 Vivado 构建 | NONE | NOT_RUN |
| 实现 | NOT_RUN | 后续源码驱动的 Vivado 构建 | NONE | NOT_RUN |
| bitstream | NOT_RUN | 仅在构建验收后生成候选镜像 | NONE | NOT_RUN |
| 板级 | NOT_RUN | 经过授权的直连主机过程和抓包 | NONE | NOT_RUN |

## 当前结论与下一关卡

Demo 范围已验收，但物理契约尚未关闭。下一关卡是审核 MGT116/SGMII 通道和参考时钟映射，随后取得创建源码和测试板卡的明确授权。
