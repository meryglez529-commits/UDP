# M88E1111 工作方式只读诊断

## 待回答问题

根据 MCON 原理图、用户提供的配置脚局部图和浏览器中打开的 Marvell 88E1111 官方数据手册，确定 PHY 在硬件复位释放后的默认 MAC 接口模式及自协商设置；保留完整的“原理图绑带→手册表项→位译码→最终配置”证据链；不进行 MDIO、JTAG 或网络操作。

## 最小证据

- `D:\MyFPGAProject\UDP\sem-sgsc2450-mcon_v1_3_2021-9-2(1).pdf` 第 9 页：U79 的 `CONFIG[0]` 至 `CONFIG[6]`、`S_CLK`、`S_IN`、`S_OUT`。
- 用户提供的配置脚局部图：`C:\Users\Administrator\AppData\Local\Temp\codex-clipboard-aceff68e-f02c-4479-95c0-168435fe9e24.png`。
- Codex In-app Browser 中的 Marvell *Alaska 88E1111 Datasheet*, Doc. No. `MV-S100649-00`, Rev. M, 2020-08-31：第 68 页（Table 32）、第 70 页（Table 34）、第 71-72 页（Table 35）、第 64 页（2.3.1.5）。

## 验收准则

给出可复算的 `HWCFG_MODE`、`ANEG`、MDIO 地址及管理接口选择值，明确区分硬件默认值和尚未进行的运行时读回；将来源、页码、译码和更正历史集中记录在 `TRACEABILITY.md`。
