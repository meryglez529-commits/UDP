# LED 下载验证 - 计划记录

状态：`SUPERSEDED_BY_HARDWARE_ENVIRONMENT_REWORK`

本计划的历史目的，是通过一个常量输出的 FPGA 镜像验证易失 JTAG 下载和板载 LED。重建后的 `HARDWARE_ENVIRONMENT.md` 已确认当时使用的 LED1 端到端路径并未闭合：只能证明 MCON `LED1 → J7.A36`，不能证明它对应 `M17/B150L230P` 或 `U20/B13_L18_N`。

因此，本计划、其 XDC、工程与 bitstream 不得用于下载，也不得作为 LED1 或 JTAG 下载链路的验收依据。后续如继续此需求，必须先在硬件环境中闭合 LED1 路径和所用 Bank 电压，再按新版 Mode 4 规则重提简洁计划。

历史范围中的 Flash、PHY、网络等无关列项系模板污染，已废止；正确的 LED 工作包只应记录 LED 路径、Bank、电平、Configuration Bank 与易失 JTAG 操作边界。
