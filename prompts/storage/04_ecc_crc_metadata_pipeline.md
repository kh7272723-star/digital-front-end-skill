# Prompt: ECC/CRC Metadata Pipeline

请使用 `digital-front-end-skill`，从 0 开始设计一个存储数据完整性 pipeline，用于对 sector/page 数据和 metadata 进行 CRC/ECC 相关处理。

我没有提供额外项目 SPEC。请你自行选择合理的简化策略、接口合约、验证计划和可交付 RTL 工程。如果选择具体 CRC 多项式或 ECC 简化模型，请在文档中说明。

## 需求

设计一个可 backpressure 的 streaming pipeline。输入为数据流和 sideband metadata，输出为原始数据或处理后数据，同时生成完整性检查结果。

## 功能

- 支持输入数据 stream，包含 data、valid、ready、last。
- 支持随数据同行的 sideband，例如 LBA、sector index、tag、metadata。
- 对每个 sector/page 计算或检查 CRC。
- 预留 ECC syndrome/correction hook；可实现简化 syndrome 计算或错误标记逻辑。
- 输出数据流必须保持 data 与 sideband 对齐。
- 输出 error report，包含 tag/LBA、错误类型、错误位置或 syndrome 摘要。
- 支持 backpressure 和 pipeline flush/reset。

## 外部接口

输入 stream 至少包含：

- `in_valid_i`, `in_ready_o`
- `in_data_i`
- `in_last_i`
- sideband: tag/LBA/sector metadata

输出 stream 至少包含：

- `out_valid_o`, `out_ready_i`
- `out_data_o`
- `out_last_o`
- aligned sideband

错误/状态接口至少包含：

- `err_valid_o`, `err_ready_i`
- tag/LBA
- error type/status

## 交付目标

请交付完整 RTL 工程和 testbench。验证重点应覆盖 pipeline latency、backpressure、sideband 对齐、last 边界、CRC mismatch、错误上报和 reset/flush 行为。不要只做波形刺激；需要明确 pass/fail 判断。

