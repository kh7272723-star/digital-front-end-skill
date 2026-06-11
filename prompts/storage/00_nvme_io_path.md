# Prompt: NVMe I/O Read Path

请使用 `digital-front-end-skill`，严格遵循skill的工作流，从 0 开始设计一个符合协议的 NVMe I/O read path 子系统。

我没有提供额外项目 SPEC。请你自行根据需求形成合理的设计假设、接口合约、验证计划和可交付 RTL 工程。如果存在会阻塞正确设计的关键信息，可以先提出；否则请记录假设后继续完成设计。

## 需求

设计一个面向 NVMe 的存储控制器的数据读取路径。该子系统接收上层已经解析出的 read command，从内部 NVM/backend 读取数据，并把数据写入 host memory 中的目标 buffer，最后返回 completion。

目标不是实现完整 NVMe controller、PCIe controller 或完整 Admin/I/O queue 系统，而是实现 read command 进入数据路径后的核心搬运逻辑。


## 功能

- 接收一个 read command 请求。
- 根据 command 中的 namespace/LBA/length 等字段生成内部 NVM/backend 读取请求。
- 根据 command 中的 host buffer 描述信息，把读取出的数据写入 host memory。
- 支持跨页或多段 host buffer 的基本处理。
- 支持 NVM/backend backpressure 和 host memory write backpressure。
- 支持错误传播：NVM read error、host write response error、非法或不支持的 command 条件。
- 输出 completion，包含 command id/tag、bytes completed、status/error。
- 可以采用保守的单 command in-order 处理，不强制多 command 并发。

## 外部接口

Command 输入接口使用 ready/valid，至少包含：

- `cmd_valid_i`, `cmd_ready_o`
- command id 或 tag
- namespace id
- starting LBA
- transfer length
- host buffer address/descriptor information

NVM/backend 读取接口至少包含：

- read request valid/ready
- read address 或 LBA/offset
- read length
- read data valid/ready/data/last
- read error/status

Host memory 写入接口至少包含：

- AXI-like write address channel
- AXI-like write data channel
- AXI-like write response channel

Completion 输出接口至少包含：

- `cpl_valid_o`, `cpl_ready_i`
- command id/tag
- bytes completed
- status/error code

## 交付目标

请交付一个完整工程，而不是只给代码片段。工程应包含 RTL、testbench、必要文档、编译日志、仿真日志和最终结论。

请自行按 skill 工作流判断复杂度等级、是否需要拆分模块或委派子任务，并在交付材料中留下依据。验证应证明数据内容、host write 地址序列、burst/beat 边界、backpressure、错误传播和 completion 行为，而不是只观察 done 信号。

