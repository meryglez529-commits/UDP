# 工程边界与授权规则

- 项目根目录：D:/MyFPGAProject/UDP
- 正式设计根目录：fpga/
- 当前 bring-up 工作单元：AI-work/bringup/db500-k7/udp-bringup-20260907/
- 远程仓库：https://github.com/meryglez529-commits/UDP.git
- FPGA 目标证据：原理图为 XC7K325T-2FFG676I；实时 JTAG 扫描报告为 xc7k325t。
- 工具链：Vivado 2021.1，路径为 D:/Xilinx/Vivado/2021.1。

本准备阶段仅允许修改 Git 元数据、AI-work/ 与 fpga/ 下的文件。根目录中的原理图和协议文档是输入证据，不得编辑、移动或重命名。

本工作单元仅授权于 2026-09-07 执行一次被动 JTAG 链扫描。扫描发现目标器件，但没有下载 bitstream、刷新器件、复位器件或改变 FPGA 行为。后续 bitstream 下载、PHY 寄存器写入、主动网络发包和产品行为均须在新阶段计划中明确授权。

每个阶段在状态推进前必须具备计划、执行记录和独立验收结论。
