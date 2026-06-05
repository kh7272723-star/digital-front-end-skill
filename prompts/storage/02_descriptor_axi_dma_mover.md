# Prompt: Descriptor-Based AXI DMA Mover

请使用 `digital-front-end-skill`，从 0 开始设计一个面向存储系统的数据搬运引擎：descriptor-based AXI DMA mover。

我没有提供额外项目 SPEC。请你自行形成设计假设、接口合约、验证计划和可交付 RTL 工程。不要只交付单个 RTL 文件；如果这是多模块系统，请按合理层级拆分并说明集成关系。

## 需求

设计一个 DMA mover，用于根据上层 descriptor 在 AXI4 memory space 内搬运数据。该模块可用于存储控制器的 host buffer、internal buffer、metadata buffer 之间的数据搬运。

请合理使用sub-agent，提高开发效率。

## 功能

- 接收 descriptor，请求内容包括 source address、destination address、byte count、direction/mode、tag。
- 发起 AXI4 read transaction 读取 source 数据。
- 发起 AXI4 write transaction 写入 destination。
- 支持 backpressure，不能丢数据、重复数据或提前完成。
- 捕获 AXI read/write response error，并在 completion 中返回。
- completion 必须和 descriptor tag 对应。
- 可以采用保守的 in-order descriptor 处理；支持 outstanding。

## 外部接口

Descriptor 输入接口使用 ready/valid，至少包含：

- `desc_valid_i`, `desc_ready_o`
- source address
- destination address
- byte count
- mode/direction
- descriptor tag

AXI4 master 接口至少包含：

- read address channel
- read data channel
- write address channel
- write data channel
- write response channel

Completion 输出接口至少包含：

- `cpl_valid_o`, `cpl_ready_i`
- descriptor tag
- bytes completed
- status/error code

## 交付目标

请交付完整 RTL 工程和可运行 testbench。请自行决定 FIFO、buffer、burst 切分、错误处理和完成顺序策略，并在文档中说明。验证需要能证明数据内容、地址序列、burst shape、response propagation 和 completion ordering，而不是只看 done 信号。

