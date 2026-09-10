# AI-work 工程记录

`AI-work` 保存人与 AI 共同维护的设计上下文，不承载 Vivado 工程或工具生成物。活动记录
与 FPGA 层次一致：

```text
AI-work/
├── ARCHITECTURE.md
└── modules/
    ├── led/MODULE.md
    ├── m88e1111-mdio/MODULE.md
    ├── ad9517/MODULE.md
    └── udp/MODULE.md
```

使用约定：

- 开始任务先读 `ARCHITECTURE.md`，再读涉及模块的 `MODULE.md`；新增、删除、重命名或集成
  模块时同步更新上层架构。
- 模块文档随讨论和实现动态更新，重点保留背景资料、接口、代码设计、约束和验证结论；
  上层只记录组成与连接，避免重复。
- 只有用户要求记录某个具体问题时，才在所属模块目录增加一份针对该问题的记录，并持续
  更新行动计划、关键发现、设计决定和结果。
- Vivado 输入（RTL、testbench、XDC、IP、ILA/VIO、Block Design）必须登记在用户指定的
  `.xpr`；仿真、构建和硬件结果留在该工程的原生目录。AI-work 只引用路径和结论。
- AI 使用 Vivado 时，按需遵循 S、B、H、D 对应规范；它们彼此独立，不自动联动。Tcl 只
  作为这些规范内部的执行手段，不能创建平行工程或绕开 GUI 工程上下文。

旧的分散计划、诊断和复制产物已完整移入
[`history/legacy-2026-09-08/`](history/legacy-2026-09-08/)，仅供追溯，不是新任务的活动入口。
