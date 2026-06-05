# Prompt: NVMe Admin Queue Engine

请使用 `digital-front-end-skill`，从 0 开始设计一个简化 NVMe Admin Queue engine。

我没有提供额外项目 SPEC。请你自行形成必要假设、接口合约、验证计划和可交付 RTL 工程。目标是考察队列、doorbell、completion 和 host-visible 状态一致性，不要求实现完整 PCIe 或完整 NVMe controller。

## 需求

设计一个管理 Admin Submission Queue 和 Admin Completion Queue 的 RTL 子系统。它从 host memory 中 fetch Admin SQE，解析基础字段，然后向 completion queue 写回 CQE。

## 功能

- 支持 Admin SQ tail doorbell 输入。
- 根据 SQ head/tail 管理待处理 command。
- 通过 AXI4 master read 从 host memory fetch 64-byte SQE。
- 至少支持一个简单命令返回 success，例如 Identify 或 Get Features 的简化响应。
- 对不支持的 opcode 返回 invalid opcode 或类似错误状态。
- 通过 AXI4 master write 向 host memory 写入 16-byte CQE。
- 管理 CQ phase tag 和 CQ head wrap。
- 输出 interrupt/event pulse 或 completion notification。

## 外部接口

配置/doorbell 接口至少包含：

- Admin SQ base address
- Admin CQ base address
- queue depth
- SQ tail doorbell value
- enable/reset 控制

AXI4 master 接口至少包含：

- read address/read data for SQE fetch
- write address/write data/write response for CQE write

状态/事件接口至少包含：

- busy
- command accepted/processed count
- completion event
- error/status output

## 交付目标

请交付完整工程：RTL、testbench、文档、编译/仿真证据和最终结论。请自行处理 queue wrap、phase tag、AXI response、unsupported opcode 和 reset 后状态。不要把 NVMe 规则只写在注释里；需要在 RTL 和 testbench 中体现。

