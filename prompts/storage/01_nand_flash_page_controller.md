# Prompt: NAND Flash Page Controller

请使用 `digital-front-end-skill`，从 0 开始设计一个 NAND Flash page controller。

我没有提供额外项目 SPEC。请你自行根据需求形成合理的设计假设、接口合约、验证计划和可交付 RTL 工程。如果存在会阻塞正确设计的关键信息，可以先提出；否则请记录假设后继续完成设计。

## 需求

设计一个面向存储子系统的 NAND-like 介质控制器，负责把上层 page/block 请求转换为 NAND 侧控制时序。目标不是兼容某个具体厂商 datasheet，而是实现一个可综合、可仿真、接口清晰的控制器骨架。
请合理使用sub-agent，提高开发效率。
## 功能

- 支持 page read、page program、block erase 三类请求。
- 支持请求 accepted、busy、done、status/error 上报。
- page read 需要从 NAND 侧读出数据并通过上层 read data stream 输出。
- page program 需要从上层 write data stream 接收数据并写入 NAND 侧。
- block erase 不传输 page data，但需要等待 ready/busy 完成并返回状态。
- 需要包含 timeout 或 busy-wait 保护，避免 NAND ready/busy 永久不返回时系统卡死。
- 预留 ECC/metadata hook 即可，不要求实现完整 ECC 算法。

## 外部接口

上层请求接口使用 ready/valid 风格，至少包含：

- `cmd_valid_i`, `cmd_ready_o`
- operation type: read / program / erase
- block/page/column address
- transfer length 或 page size 参数
- request tag 或 command id

上层数据接口至少包含：

- write data stream: valid/ready/data/last
- read data stream: valid/ready/data/last

NAND-like 介质接口至少包含：

- command/address/data IO 控制信号
- chip enable / write enable / read enable / command latch / address latch
- bidirectional data bus 或分离 input/output/oe
- ready/busy 输入

完成接口至少包含：

- completion valid/ready
- command id/tag
- status/error code

## 交付目标

请交付一个完整工程，而不是只给代码片段。工程应包含 RTL、testbench、必要文档、仿真/编译证据和最终结论。请自行按 skill 工作流判断复杂度等级、是否需要拆分模块或委派子任务，并在交付材料中留下依据。

