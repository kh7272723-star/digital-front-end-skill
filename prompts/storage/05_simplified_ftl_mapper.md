# Prompt: Simplified FTL Mapper

请使用 `digital-front-end-skill`，从 0 开始设计一个简化 FTL logical-to-physical mapper。

我没有提供额外项目 SPEC。请你自行形成合理假设、接口合约、验证计划和可交付 RTL 工程。目标是设计一个可综合的地址映射/更新控制器骨架，不要求实现完整商用 SSD FTL。

## 需求

设计一个逻辑页到物理页的映射管理模块。上层输入 logical page request，模块查询或更新 mapping table，并输出 physical page address 或 allocation/update 结果。

## 功能

- 支持 logical page lookup。
- 支持 logical page remap/update。
- 支持 free physical page 分配接口。
- 支持 old physical page invalidation 或 release notification。
- 支持 mapping table RAM 访问。
- 支持 request tag 和 completion status。
- 需要定义当 table miss、free list empty、RAM error、update conflict 发生时的行为。
- 可以采用单请求 in-order 处理，不强制乱序或多 outstanding。

## 外部接口

请求接口使用 ready/valid，至少包含：

- `req_valid_i`, `req_ready_o`
- operation: lookup / update / allocate
- logical page number
- optional new physical page
- request tag

Mapping table RAM 接口至少包含：

- address
- read enable / write enable
- write data
- read data
- read data valid 或固定读延迟假设
- error input

Free-page allocator 接口至少包含：

- allocate request/ack
- physical page output
- empty/error indication

Completion 输出至少包含：

- `cpl_valid_o`, `cpl_ready_i`
- tag
- logical page
- physical page
- status/error code

## 交付目标

请交付完整工程：RTL、testbench、文档、编译/仿真证据和最终结论。请自行决定 RAM 时序、更新原子性、冲突处理、free-page empty 行为和错误传播策略，并在交付文档中说明。验证需要覆盖 lookup hit/miss、update、allocator empty、RAM error、backpressure 和 reset 后状态。

