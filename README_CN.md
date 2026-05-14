# digital-front-end-skill

一个面向数字前端 RTL 设计的领域专用 AI Agent Skill。它将通用 LLM 转变为严格遵循工程规范的数字前端设计助手，把权威工程知识（IEEE 标准、Arm AMBA 规范、综合/CDC 方法论）提炼为紧凑、可机器执行的规则，并强制执行「合同优先」工作流：先写时序合同，再写周期迹线，最后才写 RTL。

## 为什么需要它

通用 LLM 能生成语法正确的 Verilog，但它们通常会：

- 先写代码，再把时序行为当作事后补充
- 猜测 FIFO 边界语义和握手策略，而不是向用户确认
- 混用阻塞/非阻塞赋值，或遗漏组合逻辑默认值
- 把总线协议知识当作文本而非周期级行为来对待

本 Skill 通过编码经验丰富的 RTL 工程师内部遵循的工程规范来解决这些问题，使其对 Agent 变得显式且强制。

## 它能做什么

给定一个数字前端设计请求，本 Skill 会强制 Agent 走完一套结构化工作流：

1. 解析并分类请求（叶子模块 / 子系统 / 完整系统）
2. 构建时序合同（时钟、复位、握手、延迟、停顿、冲刷、边界策略）
3. 冻结设计规格（端口、位宽、命名、协议规则）
4. 识别状态元素（寄存器、存储器、转移条件）
5. 编写周期迹线（边沿前状态、组合条件、有效沿更新、下一可见状态）
6. 选择设计模式（FSM、FIFO、流水线、仲裁器等）
7. 生成可综合 RTL（Verilog 优先，保守默认值）
8. 生成验证计划（测试平台骨架、定向测试、断言）
9. 工程评审（成熟度等级、残余风险）
10. 针对合同和迹线验证 RTL

对于大型系统（DMA 引擎、总线桥、多通道控制器），本 Skill 拒绝生成整体式 RTL，而是产出系统合同、子模块分解、接口合同、集成不变量和分阶段实现序列。

## 目录结构

```
digital-front-end-skill/
├── SKILL.md                          # Skill 定义（入口文件）
├── README.md                         # 英文说明文档
├── README_CN.md                      # 中文说明文档（本文件）
├── references/                       # 60 份精选知识文档
│   ├── authority-synthesis.md        # 权威来源如何转化为规则
│   ├── timing-semantics.md           # 周期级时序语言
│   ├── timing-contract-template.md   # 通用时序合同模板
│   ├── cycle-trace-guidelines.md     # 周期迹线编写指南
│   ├── rtl-writing-guidelines.md     # RTL 编码规则
│   ├── rtl-patterns.md               # 模式目录与选择逻辑
│   ├── naming-guidelines.md          # 信号命名规范
│   ├── protocol-authority-map.md     # 协议到官方规范的映射
│   ├── axi-full-guidelines.md        # AXI4 Full 主/从端规则
│   ├── axi-lite-guidelines.md        # AXI-Lite 寄存器块规则
│   ├── axi-dma-channel-guidelines.md # DMA 通道设计规则
│   ├── axi-dma-planning-example.md   # DMA 架构规划示例
│   ├── apb-guidelines.md             # APB 协议规则
│   ├── ahb-lite-guidelines.md        # AHB-Lite 协议规则
│   ├── axi-stream-guidelines.md      # AXI-Stream 协议规则
│   ├── cdc-guidelines.md             # 跨时钟域安全规则
│   ├── hierarchical-design-guidelines.md  # 大型系统分解指南
│   ├── staged-bringup-guidelines.md  # 分阶段上电序列
│   ├── engineering-review-checklist.md    # 设计成熟度评估
│   ├── verification-matrix-template.md    # 验证规划模板
│   ├── toolchain-closure-guidelines.md    # 签核门控定义
│   ├── tradeoff-guidance.md          # 微架构权衡框架
│   ├── ...                           # 另有 38 份模式/示例/指南文件
│   └── frame-assembler-examples.md
├── evals/
│   ├── evals.json                    # 44 个评估提示，含 250+ 条断言
│   ├── benchmark.json                # 基准元数据与维度覆盖
│   ├── task_benchmark.json           # 12 个工程师级 A/B 对比任务
│   ├── task-benchmark.md             # 基准工作流文档
│   ├── fixtures/                     # 4 个 Bug 固件，用于调试评估
│   │   ├── ready_valid_stall_bug/    # 下游停顿时 valid/data 发生变化
│   │   ├── fifo_boundary_bug/        # FIFO 满时仍接受写入
│   │   ├── fsm_reset_release_bug/    # 复位释放后 FSM 卡死
│   │   └── pipeline_stall_bug/       # 停顿时流水线数据继续推进
│   └── trials/                       # 19 个可执行 RTL + 测试平台试用例
│       ├── credit_counter_trial/
│       ├── rr_arbiter_trial/
│       ├── skid_buffer_trial/
│       ├── axi_read_tracker_trial/
│       ├── axi_write_tracker_trial/
│       ├── dma_burst_planner_trial/
│       ├── vfs_sw_hw_comm_hierarchy_trial/
│       ├── multi_bank_scheduler_trial/
│       └── ... (另有 11 个)
└── scripts/
    ├── skill_static_check.py         # 包健康检查
    ├── eval_benchmark_check.py       # 评估维度覆盖检查
    ├── rtl_check.py                  # 通过 Icarus Verilog 运行 RTL 固件
    ├── run_all_trials.py             # 批量运行所有可执行试用例
    ├── init_task_benchmark.py        # 初始化基准迭代
    ├── run_task_benchmark.py         # 准备 Agent 运行提示
    └── grade_task_benchmark.py       # 用确定性断言评分
```

## 设计哲学

### 合同优先，始终如此

Agent 必须先写时序合同才能写 RTL。这不是建议——本 Skill 的工作流从结构上使跳过这一步变得不可能。合同包括时钟域、复位风格、握手语义、延迟、停顿行为、冲刷行为和边界策略。

### 拒绝猜测

当需求不完整时（例如「设计一个 FIFO」却没有指定满/读行为），本 Skill 会强制 Agent 向用户提问或声明保守假设。静默发明协议语义被视为 Bug，而非特性。

### 大型系统必须分解

请求「完整的 AXI DMA 引擎」不会产生 500 行猜测的 RTL，而是产出系统合同、子模块分解、接口合同、集成不变量，以及优先实现哪个叶子模块的建议。

### CDC 不可妥协

多位跨时钟域不能通过「每比特加两个触发器」来修复。本 Skill 拒绝生成猜测的 CDC RTL，要求使用明确的安全跨域模式（握手、快照、格雷码计数器或异步 FIFO）。

### Verilog 优先

默认输出为纯 Verilog，而非 SystemVerilog，以最小化综合工具兼容性问题。SystemVerilog 特性仅在明确要求或任务确实需要时才使用（如 SVA 断言）。

## 评估框架

项目包含两层评估系统：

### 第一层：提示覆盖（evals.json）

44 个提示，覆盖 14 个质量维度：

| 维度 | 测试内容 |
|------|----------|
| module_timing | 叶子 RTL 时序合同、状态元素、周期迹线 |
| protocol_axi_full | AXI Full 通道、突发、乱序、响应语义 |
| protocol_axi_lite | AXI-Lite 寄存器块与小型从端 |
| protocol_axi_dma | DMA 排序、响应跟踪、完成、分片规划 |
| protocol_apb | APB 建立/访问阶段、等待状态、字节选通 |
| protocol_ahb_lite | AHB-Lite 地址/数据阶段对齐 |
| protocol_axi_stream | AXI-Stream 载荷、侧带、反压 |
| system_hierarchy | 大型系统分解、接口合同、不变量 |
| verification_closure | 验证矩阵、工具证据、签核规范 |
| debug_review | 首个分歧周期推理与协议 Bug 评审 |
| cdc_safety | CDC 拒绝、安全模式选择 |
| project_adaptation | 现有仓库规范适配 |
| synthesis_timing | 综合推断、约束、时序收敛意识 |
| specialized_rtl_patterns | 信用、重试缓冲、位宽转换、ECC、多 Bank |

每个提示有 5-7 条由正则匹配检查的确定性断言。

### 第二层：工程师级任务基准（task_benchmark.json）

12 个模拟真实 RTL 开发的任务，采用 A/B 对比：
- **with_skill**：Agent 加载 `digital-front-end-skill` 运行
- **baseline**：Agent 不加载 Skill 运行

评分由 `scripts/grade_task_benchmark.py` 自动完成，产出结构化的 `benchmark.md` 和 `benchmark.json` 报告。

### 可执行试用例

19 个试用例包含可综合 RTL + 测试平台 + 清单文件。每个都可通过 `scripts/rtl_check.py` 用 Icarus Verilog 编译和仿真，提供生成代码通过仿真的硬证据，而非仅看起来正确。

### Bug 固件

4 个固件编码了真实 RTL Bug 模式（停顿保持违规、边界策略错误、复位释放问题、流水线数据损坏）。每个固件的清单指定了预期失败特征，用于评估 Agent 的调试能力。

## 使用方法

### 作为 Claude Code Skill 使用

将 `digital-front-end-skill` 目录放在项目下，在 CLAUDE.md 中引用或通过 Skill 机制加载。Agent 会自动对任何 RTL 设计请求执行合同优先工作流。

### 运行静态检查

```bash
python scripts/skill_static_check.py
```

验证内容：evals JSON schema、SKILL.md 中列出的参考文件、禁止的遗留术语（fire/push/pop）、固件清单。

### 运行评估基准覆盖检查

```bash
python scripts/eval_benchmark_check.py
```

检查所有 14 个维度是否有足够的评估覆盖，以及必需模式是否存在可执行试用例。

### 运行可执行试用例

```bash
python scripts/rtl_check.py --case evals/trials/rr_arbiter_trial
```

用 Icarus Verilog 编译和仿真该试用例，然后根据清单的预期结果检查输出。

### 运行全部试用例

```bash
python scripts/run_all_trials.py
```

批量运行所有 19 个可执行试用例并报告通过/失败状态。

### 运行任务基准

```bash
# 初始化迭代
python scripts/init_task_benchmark.py --iteration 1

# （使用和不使用 Skill 运行 Agent，保存输出）

# 对迭代评分
python scripts/grade_task_benchmark.py --iteration-dir ../digital-front-end-skill-workspace/iteration-1
```

## 协议覆盖

所有协议特定规则均基于官方规范：

| 协议 | 来源 | 参考文件 |
|------|------|----------|
| AXI4 Full | Arm IHI 0022 | axi-full-guidelines, axi-multi-outstanding-guidelines, axi-dma-channel-guidelines |
| AXI4-Lite | Arm IHI 0022 | axi-lite-guidelines |
| APB | Arm IHI 0024 | apb-guidelines |
| AHB-Lite | Arm IHI 0033 | ahb-lite-guidelines |
| AXI4-Stream | Arm IHI 0051 | axi-stream-guidelines |

`references/protocol-authority-map.md` 文件记录了每个协议到其权威来源及派生的本地参考文件的映射。

## 设计模式目录

本 Skill 覆盖 18 种可复用 RTL 模式：

| 模式 | 用途 |
|------|------|
| Ready/Valid 寄存器切片 | 带反压的单周期解耦 |
| Skid Buffer | 反压下保持吞吐的双入口缓冲 |
| FIFO | 有序存储与边界保证 |
| 流水线级 | 时序收敛与可控延迟 |
| FSM（双进程） | 多阶段控制与显式状态 |
| 仲裁器（固定/轮询） | 共享资源仲裁 |
| 基于信用的流控 | 长延迟反压与信用记账 |
| 重试缓冲 | ACK/NAK 重放与有限在飞窗口 |
| 位宽转换器 | 窄到宽或宽到窄的流式传输 |
| CRC 生成器 | 数据通路错误检测 |
| SECDED ECC | 单错纠正，双错检测 |
| 多 Bank 存储调度器 | Bank 冲突检测与公平仲裁 |
| 计数器 / 寄存器切片 | 简单状态跟踪 |
| Req/Ack 适配器 | 协议转换 |
| 速率限制器 | 吞吐量约束 |
| 帧组装器 | 带侧带的分组成帧 |
| CAM | 内容寻址查找 |
| AXI DMA 切片 | 描述符解析、突发规划、完成跟踪 |

## 成熟度等级

本 Skill 定义了四个设计成熟度等级，以防止过度声明：

- **草稿（Sketch）**：行为看似合理，但合同和检查不完整。
- **可评审 RTL（Reviewable RTL）**：合同、周期迹线、RTL 和定向检查均已就位。
- **可集成 RTL（Integration-ready RTL）**：接口、复位、错误、反压和不变量均已检查。
- **签核候选（Signoff candidate）**：Lint、CDC、仿真、形式/覆盖、综合和时序风险已由项目工具覆盖。

Agent 被要求在完成任何非平凡设计前声明成熟度等级和主要残余风险。

## 许可

本项目是一个精选工程知识库和评估框架。各参考文件中注明了权威来源的归属信息。
