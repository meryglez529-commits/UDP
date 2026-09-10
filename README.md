# DB500 UDP FPGA 工程

本仓库用于在 MK7XCORE676 / Kintex-7 平台上逐步开发可验证的 FPGA 设计。当前已完成 LED
基础设计和 M88E1111 MDIO 只读验证；UDP 数据面仍处于规划阶段。

目录职责：

- [`fpga/led/led.xpr`](fpga/led/led.xpr)：用户通过 Vivado GUI 创建并持续使用的共享工程。
  RTL、testbench、XDC、IP、仿真、综合、实现和 Hardware Manager 都以这份工程为上下文。
- [`fpga/led/scripts/sources.tcl`](fpga/led/scripts/sources.tcl)：与 `.xpr` 对齐的显式输入清单。
- [`AI-work/ARCHITECTURE.md`](AI-work/ARCHITECTURE.md)：项目身份、模块组成和集成事实。
- [`AI-work/modules/`](AI-work/modules/)：每个模块的动态设计记录。
- [`AI-work/history/legacy-2026-09-08/`](AI-work/history/legacy-2026-09-08/)：旧记录和原始
  审计材料，仅作历史参考。

原理图和 DB500 协议文档保留在仓库根目录，PHY 手册按模块文档记录的官方来源查阅；其来源
和已核对的结论记录在架构或模块文档中。需要仿真、构建、下载、ILA 或只读诊断时，使用新版
`fpga-cowork` 的 S/B/H/D 规范，并始终复用上述 GUI 工程及其原生产物目录。
