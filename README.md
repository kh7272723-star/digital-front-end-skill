# digital-front-end-skill

这是一个面向数字前端 RTL 设计的领域专用 AI Agent Skill，用来把通用大语言模型约束成一名遵循工程纪律的数字前端设计助手。它将权威工程知识（IEEE 标准、Arm AMBA 规范、综合 / CDC 方法学）提炼为紧凑、可机器执行的规则，并强制执行“契约优先”的工作流：先写时序契约，再写周期轨迹，最后才写 RTL。

## 为什么要做这个项目

通用大语言模型虽然能生成语法正确的 Verilog，但经常会：

- 先写代码，再事后补充时序行为说明
- 不去澄清 FIFO 边界语义和握手策略，而是直接猜测
- 混用阻塞 / 非阻塞赋值，或者遗漏组合逻辑默认值
- 把总线协议知识当作文档描述，而不是按周期行为去理解

这个 Skill 的目标，就是把资深 RTL 工程师日常隐式遵循的工程纪律显式化、规则化，并强制 Agent 遵守。

## 它能做什么

面对一个数字前端设计请求时，这个 Skill 会强制 Agent 按以下结构化流程执行：

1. 解析并分类请求（叶子模块 / 子系统 / 完整系统）
2. 建立时序契约（时钟、复位、握手、延迟、停顿、冲刷、边界语义）
3. 冻结设计规格（端口、位宽、命名、协议规则）
4. 识别状态元素（寄存器、存储器、数据移动条件）
5. 编写周期轨迹（沿前状态、组合条件、有效沿更新、下一拍可见状态）
6. 选择设计模式（FSM、FIFO、流水线、仲裁器等）
7. 生成可综合 RTL（优先 Verilog，默认保守实现）
8. 生成验证计划（testbench 骨架、定向测试、断言）
9. 做工程评审（成熟度等级、剩余风险）
10. 将 RTL 回对照到契约与周期轨迹进行验证

对于大型系统（例如 DMA 引擎、总线桥、多通道控制器），这个 Skill 不会直接输出一个庞大的单体 RTL 文件，而是会给出系统契约、子模块拆分、接口契约、集成不变量，以及分阶段实施顺序。

## 仓库内容

```
digital-front-end-skill/
├── SKILL.md                          # Skill 定义（入口文件）
├── README.md                         # 当前说明文档
├── references/                       # 60 份整理后的知识文档
│   ├── authority-synthesis.md        # 如何将权威资料提炼成规则
│   ├── timing-semantics.md           # 周期级时序语义
│   ├── timing-contract-template.md   # 通用时序契约模板
│   ├── cycle-trace-guidelines.md     # 周期轨迹编写指南
│   ├── rtl-writing-guidelines.md     # RTL 编码规则
│   ├── rtl-patterns.md               # 设计模式目录与选择逻辑
│   ├── naming-guidelines.md          # 信号命名规范
│   ├── protocol-authority-map.md     # 协议与官方规范映射
│   ├── axi-full-guidelines.md        # AXI4 Full 主从设计规则
│   ├── axi-lite-guidelines.md        # AXI-Lite 寄存器块规则
│   ├── axi-dma-channel-guidelines.md # DMA 通道设计规则
│   ├── axi-dma-planning-example.md   # DMA 架构规划示例
│   ├── apb-guidelines.md             # APB 协议规则
│   ├── ahb-lite-guidelines.md        # AHB-Lite 协议规则
│   ├── axi-stream-guidelines.md      # AXI-Stream 协议规则
│   ├── cdc-guidelines.md             # 时钟域跨越安全指南
│   ├── hierarchical-design-guidelines.md  # 大系统拆分方法
│   ├── staged-bringup-guidelines.md  # 分阶段实现流程
│   ├── engineering-review-checklist.md    # 设计成熟度评审清单
│   ├── verification-matrix-template.md    # 验证规划模板
│   ├── toolchain-closure-guidelines.md    # 签核门槛定义
│   ├── tradeoff-guidance.md          # 微架构权衡方法
│   ├── ...                           # 另外 38 份模式 / 示例 / 指南文档
│   └── frame-assembler-examples.md
├── evals/
│   ├── evals.json                    # 44 个评测提示词与 250+ 条断言
│   ├── benchmark.json                # 基准元数据与维度覆盖信息
│   ├── task_benchmark.json           # 12 个工程级 A/B 对比任务
│   ├── task-benchmark.md             # 基准流程说明
│   ├── fixtures/                     # 4 个调试评测缺陷样例
│   │   ├── ready_valid_stall_bug/    # 下游停顿时 valid/data 非法变化
│   │   ├── fifo_boundary_bug/        # FIFO 满时仍错误接受写入
│   │   ├── fsm_reset_release_bug/    # 复位释放后 FSM 卡死
│   │   └── pipeline_stall_bug/       # 流水线停顿时数据仍继续前进
│   └── trials/                       # 19 个可执行 RTL + testbench 样例
│       ├── credit_counter_trial/
│       ├── rr_arbiter_trial/
│       ├── skid_buffer_trial/
│       ├── axi_read_tracker_trial/
│       ├── axi_write_tracker_trial/
│       ├── dma_burst_planner_trial/
│       ├── vfs_sw_hw_comm_hierarchy_trial/
│       ├── multi_bank_scheduler_trial/
│       └── ...（其余 11 个）
└── scripts/
    ├── skill_static_check.py         # Skill 包完整性检查
    ├── eval_benchmark_check.py       # 评测维度覆盖检查
    ├── rtl_check.py                  # 使用 Icarus Verilog 跑 RTL 样例
    ├── run_all_trials.py             # 批量运行全部可执行样例
    ├── init_task_benchmark.py        # 初始化一次 benchmark 迭代
    ├── run_task_benchmark.py         # 为 Agent 运行准备提示词
    └── grade_task_benchmark.py       # 使用确定性断言进行评分
```

## 设计理念

### 始终契约优先

在生成任何 RTL 之前，Agent 必须先写出时序契约。这不是建议，而是 Skill 工作流中的强制结构。契约必须覆盖时钟域、复位方式、握手语义、延迟、停顿行为、冲刷行为，以及边界策略。

### 拒绝猜测

当需求不完整时（例如“设计一个 FIFO”，却没有说明 full+read 行为），Skill 会强制 Agent 主动询问，或显式声明保守假设。未经说明就擅自补全协议语义，会被视为缺陷，而不是“聪明”。

### 大系统必须拆分

对于“完整 AXI DMA 引擎”这类需求，Skill 不会直接产出数百行靠猜测拼出来的 RTL，而是会先给出系统契约、子模块划分、接口契约、集成不变量，以及推荐优先实现的叶子模块。

### CDC 不可妥协

多比特时钟域跨越不能靠“每一位各加两个触发器”来解决。Skill 会拒绝生成拍脑袋式 CDC RTL，并要求使用明确的安全跨域模式（握手、快照、格雷码计数器或异步 FIFO）。

### Verilog 优先

默认输出为纯 Verilog，而不是 SystemVerilog，以尽量减少综合工具兼容性问题。只有在用户明确要求，或任务确实需要时（例如 SVA 断言），才会使用 SystemVerilog 特性。

## 评测框架

项目提供两层评测体系：

### 第一层：提示词覆盖（evals.json）

44 个提示词覆盖 14 个质量维度：

| 维度 | 测试内容 |
|-----------|---------------|
| module_timing | 叶子 RTL 的时序契约、状态元素、周期轨迹 |
| protocol_axi_full | AXI Full 通道、burst、outstanding、响应语义 |
| protocol_axi_lite | AXI-Lite 寄存器块和轻量从设备 |
| protocol_axi_dma | DMA 顺序性、响应跟踪、完成路径、slice 规划 |
| protocol_apb | APB setup/access 阶段、等待状态、字节使能 |
| protocol_ahb_lite | AHB-Lite 地址相位 / 数据相位对齐 |
| protocol_axi_stream | AXI-Stream 负载、边带、反压 |
| system_hierarchy | 大系统拆分、接口契约、不变量 |
| verification_closure | 验证矩阵、工具证据、签核纪律 |
| debug_review | 首个发散周期定位与协议缺陷评审 |
| cdc_safety | CDC 拒绝策略与安全模式选择 |
| project_adaptation | 对现有仓库约定的适配能力 |
| synthesis_timing | 综合推断、约束、时序收敛意识 |
| specialized_rtl_patterns | credit、retry buffer、宽度转换、ECC、多 bank 等模式 |

每个提示词都配有 5-7 条基于正则匹配的确定性断言。

### 第二层：工程级任务基准（task_benchmark.json）

12 个任务模拟真实 RTL 开发，并采用 A/B 对比：

- **with_skill**：加载 `digital-front-end-skill` 的 Agent 输出
- **baseline**：不加载 Skill 的 Agent 输出

评分由 `scripts/grade_task_benchmark.py` 自动完成，并生成结构化的 `benchmark.md` 与 `benchmark.json` 报告。

### 可执行样例

19 个 trial 提供了可综合 RTL、testbench 和 manifest 文件。每个样例都可以通过 `scripts/rtl_check.py` 配合 Icarus Verilog 编译与仿真，用硬证据证明生成代码不仅“看起来对”，而且真的能通过仿真。

### 缺陷样例

4 个 fixture 编码了真实 RTL 缺陷模式（停顿保持违规、边界策略错误、复位释放问题、流水线数据损坏）。每个样例都带有 manifest，用于声明预期的失败特征，以评估 Agent 的调试能力。

## 使用方式

### 作为 Claude Code skill 使用

将 `digital-front-end-skill` 目录放到你的项目中，并在 `CLAUDE.md` 中引用，或通过 skill 机制加载。之后，Agent 在处理 RTL 设计请求时会自动遵循“契约优先”流程。

### 运行静态检查

```bash
python scripts/skill_static_check.py
```

会校验：evals JSON 结构、SKILL.md 中列出的 reference 文件、被禁用的旧术语（fire/push/pop）、fixture manifest。

### 检查评测覆盖情况

```bash
python scripts/eval_benchmark_check.py
```

用于检查 14 个维度是否有足够的评测覆盖，以及所需设计模式是否存在可执行样例。

### 运行单个可执行样例

```bash
python scripts/rtl_check.py --case evals/trials/rr_arbiter_trial
```

该命令会使用 Icarus Verilog 对指定样例进行编译和仿真，然后根据 manifest 中的期望结果判断是否通过。

### 运行全部样例

```bash
python scripts/run_all_trials.py
```

批量执行全部 19 个可执行样例，并输出通过 / 失败结果。

### 运行任务基准

```bash
# 初始化一次迭代
python scripts/init_task_benchmark.py --iteration 1

# （分别运行加载 Skill 与未加载 Skill 的 Agent，并保存输出）

# 对本次迭代进行评分
python scripts/grade_task_benchmark.py --iteration-dir ../digital-front-end-skill-workspace/iteration-1
```

## 协议覆盖范围

所有协议相关规则都基于官方规范整理：

| 协议 | 来源 | 参考文件 |
|----------|--------|-----------------|
| AXI4 Full | Arm IHI 0022 | axi-full-guidelines, axi-multi-outstanding-guidelines, axi-dma-channel-guidelines |
| AXI4-Lite | Arm IHI 0022 | axi-lite-guidelines |
| APB | Arm IHI 0024 | apb-guidelines |
| AHB-Lite | Arm IHI 0033 | ahb-lite-guidelines |
| AXI4-Stream | Arm IHI 0051 | axi-stream-guidelines |

`references/protocol-authority-map.md` 记录了每种协议与其权威来源、以及本地参考文件之间的映射关系。

## 设计模式目录

这个 Skill 覆盖了 18 类可复用 RTL 模式：

| 模式 | 典型用途 |
|---------|----------|
| Ready/valid register slice | 单周期解耦与反压传递 |
| Skid buffer | 在反压场景下保持吞吐的两级缓冲 |
| FIFO | 带边界语义与顺序保证的存储结构 |
| Pipeline stage | 为时序收敛提供受控延迟 |
| FSM（双进程） | 带显式状态的多阶段控制 |
| Arbiter（固定优先级 / 轮询） | 共享资源仲裁 |
| Credit-based flow control | 面向长延迟链路的 credit 回压控制 |
| Retry buffer | 基于 ACK/NAK 的重放缓冲 |
| Width converter | 宽窄流数据转换 |
| CRC generator | 数据路径错误检测 |
| SECDED ECC | 单错纠正、双错检测 |
| Multi-bank memory scheduler | 带 bank 冲突检测的公平调度 |
| Counter / register slice | 简单状态跟踪 |
| Req/ack adapter | 协议适配转换 |
| Rate limiter | 吞吐率限制 |
| Frame assembler | 带边带信息的成帧逻辑 |
| CAM | 内容寻址查找 |
| AXI DMA slice | 描述符解析、burst 规划、完成跟踪 |

## 成熟度等级

Skill 定义了四个设计成熟度等级，用来避免 Agent 过度承诺：

- **Sketch**：行为大体合理，但契约和检查还不完整。
- **Reviewable RTL**：已有契约、周期轨迹、RTL 和定向检查。
- **Integration-ready RTL**：接口、复位、错误路径、反压和不变量都已检查。
- **Signoff candidate**：已通过项目工具覆盖 lint、CDC、仿真、formal/coverage、综合与时序风险。

在结束任何非平凡设计任务之前，Agent 都必须说明当前成熟度等级，以及最重要的剩余风险。

## License

本项目是一个经过整理的工程知识库与评测框架。权威来源的归属信息请参阅各参考文件。
