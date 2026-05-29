# digital-front-end-skill

一个面向数字前端 RTL 设计的领域专用 AI Agent Skill。它将通用 LLM 转变为严格遵循工程规范的数字前端设计助手，把权威工程知识（IEEE 标准、Arm AMBA 规范、综合/CDC 方法论）提炼为紧凑、可机器执行的规则，并强制执行「合同优先」工作流：先写时序合同，再写周期迹线，最后才写 RTL。

## 为什么需要这个 Skill

通用 LLM 能生成语法正确的 Verilog，但经常：

- 先写代码再补时序行为描述
- 猜测 FIFO 边界语义和握手策略，而不是询问
- 混用阻塞/非阻塞赋值，遗漏组合默认值
- 把总线协议知识当文本处理，而非周期级行为
- 生成结构审查通过但功能测试失败的代码

这个 Skill 通过编码资深 RTL 工程师内化的工程纪律来解决这些问题。

## 工作流（12 步）

1. 解析需求（叶子模块/子系统/全系统分类）
2. 建立时序合同（时钟、复位、握手、延迟、停顿、冲刷、边界行为）
3. 冻结设计规格（端口、宽度、命名、协议规则）
4. 识别状态元素（寄存器、存储器、移动条件）
5. 编写周期迹线（沿前状态、组合条件、有效沿更新、下一可见状态）
6. 选择设计模式（FSM、FIFO、流水线、仲裁器等）
7. 生成可综合 RTL（Verilog 优先、保守默认值、bug pattern 扫描）
8. 结构自审（10 大类 57 项检查）
8b. 功能验证（强制 — Golden Reference 方法论，6 种策略）
8c. 设计原则审查（强制 — 6 核心原则 + 主动搜索问题）
9. 仿真闭环（lint → 编译 → 仿真 → VCD 波形分析 → 修复 → 重跑）
10. 综合反馈（Yosys：latch/loop/关键路径/cell count 检查）
11. 审查迭代
12. 验证时序对齐

## 目录结构

```
digital-front-end-skill/
├── SKILL.md                          # Skill 定义（415 行）
├── SKILL_CHANGELOG.md                # 完整迭代历史
├── README.md / README_CN.md          # 本文件
├── references/                       # 87 个知识文档
│   ├── reference-index.md            # 任务到参考文件的映射
│   ├── timing/                       # 时序语义、合同、命名、协议
│   ├── architecture/                 # 层次结构、系统合同、集成不变量
│   ├── axi-dma/                      # AXI full/Lite/Stream、DMA 通道指南
│   ├── bus/                          # APB、AHB-Lite 协议规则
│   ├── rtl/                          # 编码指南、FSM/FIFO/流水线/握手示例
│   ├── patterns/                     # 仲裁器、信用流控、CRC、ECC、宽度转换等
│   ├── synthesis/                    # CDC、约束、综合指导
│   ├── verification/                 # 测试台、断言、仿真闭环、Golden Reference
│   ├── debug/                        # Bug pattern 库（57 个 pattern）
│   ├── design/                       # **6 大设计原则**、启发式、PTA 规则、直觉检查表
│   ├── project/                      # 棕地开发、大模块指导
│   └── advanced/                     # 低功耗、DFT、UVM、物理感知
├── evals/                            # 63 个评估 prompt、23 个试用、4 个 bug fixture
├── scripts/                          # 10 个 Python 脚本
└── projects/                         # 13 个已验证 RTL 项目
```

## 核心能力

### 6 大设计原则（核心创新）

57 个 bug pattern 被组织在 6 个核心设计原则之下。Agent 不再逐条扫描 57 个 pattern，而是用这些原则作为"主动搜索"透镜来发现功能 bug：

| # | 原则 | 核心问题 |
|---|------|---------|
| P1 | 每个信号都有时序合同 | 每个输出的信号类型（脉冲/电平/寄存器）是否已文档化？ |
| P2 | 每个状态机都必须能回到家 | 每个状态是否能回到 IDLE？中间状态是否有 abort 路径？ |
| P3 | 每个寄存器在任何时刻的值都必须可知 | 复位后每个寄存器是什么值？未初始化的存储器有策略吗？ |
| P4 | 独立的事物必须保持独立 | AXI 通道/时钟域/读写路径是否解耦？ |
| P5 | 物理世界永远赢 | 功耗序列、隔离、操作数门控是否正确？ |
| P6 | Bug 藏在边界处 | 每个模块边界是否有显式合同（端口宽度、信号类型、复位行为）？ |

详见 `references/design/design-principles.md`。

### 57 个 Bug Pattern（带权威来源）

| 类别 | 数量 | 示例 |
|------|------|------|
| 握手 (H1-H8) | 8 | 载荷稳定性、ready 循环、valid 门控 |
| 协议 (P4-P13) | 10 | AXI 通道分离、WVALID burst、APB 时序 |
| 计数器/状态 (P14-P18) | 5 | 自动重载竞争、专用清除、流水线延迟 |
| 状态机 (SM1-SM3) | 3 | 影子数据通路、FSM 中多比特 _d、FSM abort 路径 |
| 数据通路 (DP1-DP5) | 5 | 宽度转换、bit-slicing、错误路径 |
| RTL 正确性 (E1-E8) | 8 | Latch 推断、多驱动、截断、阻塞/非阻塞 |
| FIFO (F1-F2) | 2 | FWFT 输出偏移、寄存器输出竞态 |
| CDC (D1-D2) | 2 | 格雷码、ASYNC_REG |
| 低功耗 (LP1-LP7) | 7 | 隔离时序、保持握手、PSM 状态、CDC 脉冲同步、DVFS 门控、操作数隔离、脉冲转换检测 |
| 物理感知 (PH1-PH4) | 4 | 注册 I/O、扇出控制、SRAM 邻近、总线分组 |
| 验证盲点 (V1) | 1 | 结构 PASS 但功能 FAIL |

### Golden Reference 功能验证（强制）

Step 8b 要求用已知输入和预期输出运行功能测试。6 种 Golden Reference 策略覆盖所有模块类型：已知 I/O 对（CRC/ECC）、软件参考模型（算法）、写回读记分板（寄存器块）、数据完整性记分板（DMA/FIFO）、不变量检查（仲裁器）、延迟验证（流水线）。全部 6 种策略已在 10 个真实项目中验证。

### 仿真闭环 + VCD 波形分析

完整的闭环验证：`iverilog` 编译 → `vvp` 仿真 → PASS/FAIL 解析 → `vcd_extract.py` 波形分析（信号时间线提取、AXI/APB 协议重建、违规检测）→ bug pattern 匹配 → 最小修复 → 重跑仿真。最多 3 次迭代。

### Yosys 综合反馈

仿真通过后运行综合检查：latch 推断、组合环路、关键路径（ltp）、cell count。`yosys_extract.py` 自动化报告提取。

### 多模块集成

子代理委托 + 接口合约确保独立生成的模块端口宽度一致。已在 UART（4 子代理）、DMA 子系统（4 子代理）、Low-Power SoC（5 子代理）上验证。

## 协议覆盖

| 协议 | 来源 | 参考文件 |
|------|------|---------|
| AXI4 Full | Arm IHI 0022 | axi-full-guidelines, axi-multi-outstanding, axi-dma-channel |
| AXI4-Lite | Arm IHI 0022 | axi-lite-guidelines |
| APB | Arm IHI 0024 | apb-guidelines |
| AHB-Lite | Arm IHI 0033 | ahb-lite-guidelines |
| AXI4-Stream | Arm IHI 0051 | axi-stream-guidelines |

## 设计模式目录（18 个）

Ready/valid 寄存器切片、Skid buffer、FIFO、流水线阶段、FSM（双进程）、仲裁器（固定/轮询）、信用流控、重试缓冲、宽度转换、CRC 生成器、SECDED ECC、多 bank 存储调度、计数器/寄存器切片、req/ack 适配器、限速器、帧组装器、CAM、AXI DMA 切片。

## 已验证项目（13 个）

| 项目 | 类型 | 测试 | 关键发现 |
|------|------|------|---------|
| CDMA x6 | AXI DMA | 多轮 | AW/W/B 通道分离，6 轮迭代 |
| Timer | 计数器 | 16/16 | P14-P17：触发竞争、状态寄存器 |
| INTC | 中断控制器 | 12/12 | PSLVERR 范围、组合输出时序 |
| CRC | 数据通路 | 7/7 | P18：流水线延迟、功能验证 |
| Async FIFO | CDC | 10/10 | CDC 指南质量验证 |
| AHB-Lite | 总线 | 11/11 | 读数据时序、仿真闭环首验 |
| DMA 子系统 | 多模块 | 1/2 | 接口合约、SVA 兼容性 |
| UART | 多模块 | 6/6 | 接口合约模式验证 |
| Crossbar | 参数化 | 0/4 | 结构 vs 功能 gap 再确认 |
| Arbiter | 仲裁器 | 6/6 | 综合感知、mask 重置 bug |
| Clock Gate | 低功耗 | 8/8 | P1 规则验证、零设计缺陷 |
| SPI Master | 复杂 FSM | 5/5 | 6 状态 FSM、首次 Yosys 综合 |
| **Low-Power SoC** | **子系统** | **28/28** | **LP1-LP7 + PH1-PH4 全验证，SM3+LP7 新 pattern** |

## 使用方法

### 作为 Claude Code Skill

将 skill 放在 `~/.claude/skills/` 下，或在项目 CLAUDE.md 中引用。Agent 会自动遵循合同优先工作流。

### 运行静态检查

```bash
python scripts/skill_static_check.py
python scripts/eval_benchmark_check.py
```

### 运行试用

```bash
python scripts/rtl_check.py --case evals/trials/rr_arbiter_trial
python scripts/run_all_trials.py              # 批量 23 个
```

### VCD 波形分析

```bash
python scripts/vcd_extract.py dump.vcd --signals WVALID,WDATA --range 0:50000
python scripts/vcd_extract.py dump.vcd --protocol axi-write
python scripts/vcd_extract.py dump.vcd --find-violation stall-data-change
```

### Yosys 综合检查

```bash
python scripts/yosys_extract.py --top <module> --sources <files>
```

## 许可证

本项目是策划的工程知识库和评估框架。各参考文件中注明了权威来源的归属（IEEE、Arm、SNUG 等）。
