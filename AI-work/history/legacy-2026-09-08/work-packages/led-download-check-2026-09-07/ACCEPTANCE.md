# LED 下载验证 - 验收

状态：`NOT_ACCEPTABLE_HARDWARE_MAPPING_SUPERSEDED`

验收结论：不通过，且不进入下载。

原因不是 Vivado 构建失败，而是其 LED 管脚依据已经被硬件环境重建撤销。现有 bitstream 虽曾生成，仍不能证明其连接的是 MCON LED1；没有下载，也没有 LED 目视证据。

重新开始此工作包的前置条件：在 `HARDWARE_ENVIRONMENT.md` 中以页码和连接器互配资料闭合 `LED1 → FPGA ball`，确认对应 Bank 的电压与 IOSTANDARD；之后由用户确认新的计划，才可重建和下载。
