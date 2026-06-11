# digital-front-end-skill

一个面向数字前端 RTL 设计的领域专用 AI Agent Skill。它将通用 LLM 转变为严格遵循工程规范的数字前端设计助手，把权威工程知识（IEEE 标准、Arm AMBA 规范、综合/CDC 方法论）提炼为紧凑、可机器执行的规则，并强制执行「合同优先」工作流：先写时序合同，再写周期迹线，最后才写 RTL。

## 最新版本：v2026.06.11-r3

**r3 — 工程化设计模式强化：**

**FSM 拆分强制化（C8 R→M + C8a 阈值）：** ≥4 状态且 ≥6 控制输出 → 必须独立 `_fsm.v` 文件，主模块禁 `case(cstate)`，FSM 文件禁实例化 IP。


**AXI 通道分离模板：** 通用五模块 AW/W/B/AR/R 独立通道分离模式，纯结构封装，零逻辑。

**命名约定强化（N14）：** 多实例数字前缀（`ch0_`, `ch1_`）。
## 为什么需要这个 Skill

通用 LLM 能生成语法正确的 Verilog，但经常：

- 先写代码再补时序行为描述
- 猜测 FIFO 边界语义和握手策略，而不是询问
- 混用阻塞/非阻塞赋值，遗漏组合默认值
- 把总线协议知识当文本处理，而非周期级行为
- 生成结构审查通过但功能测试失败的代码

这个 Skill 通过编码资深 RTL 工程师内化的工程纪律来解决这些问题。

## 工作流（三档闸门 + 阶段导航）

1. 解析需求并三档分类（L0：简单 / L1：叶子模块 / L2：子系统 — L0 自动跳过早期检查点）
2. 建立时序合同（时钟、复位、握手、延迟、停顿、冲刷、边界行为）
2a. 原则检查 — P4 独立性 + P6 边界（L0 跳过）
3. 冻结设计规格（端口、宽度、命名、协议规则）
4. 识别状态元素（寄存器、存储器、移动条件）
5. 编写周期迹线（沿前状态、组合条件、有效沿更新、下一可见状态）
5a. 原则检查 — P1 时序合同 + P2 FSM 安全（线性 FSM 用 LITE 模式）
6. 选择设计模式（FSM、FIFO、流水线、仲裁器等）
7. 只生成可综合 RTL（不写 TB），并通过带 RTL-only compile evidence 的 post-rtl 门禁
8. 结构自审（13 大类 79 项检查）
8c. 原则检查 — P3 已知值 + P5a 输出纪律（P5b 物理实现仅 L2）
8b. 功能验证计划（Golden Reference、scoreboard、false-pass audit；只写计划，不写 TB）
9. L2 逐模块 TB + guarded simulation + sim_log_gate + module verification matrix
9-EXIT. module-sim/pre-integration 门禁；PASS 前仍禁止集成 TB
10. pre-integration 通过后，再写集成 TB 并进行集成仿真与原则驱动 debug
10-EXIT. post-sim 门禁
11. final delivery 门禁；PASS 后才允许声明交付成功

## 目录结构

```
digital-front-end-skill/
├── SKILL.md                          # Skill 定义（~345 行，三档闸门）
├── SKILL_CHANGELOG.md                # 完整迭代历史（R5-R10 A/B 实验 + NVMe Phase 1）
├── README.md / README_CN.md          # 本文件
├── references/                       # 90+ 个知识文档
│   ├── reference-index.md            # 任务到参考文件的映射
│   ├── timing/                       # 时序语义、合同、命名、协议
│   ├── architecture/                 # 层次结构、系统合同、集成不变量
│   ├── axi-dma/                      # AXI full/Lite/Stream、DMA 通道指南
│   ├── bus/                          # APB、AHB-Lite、NVMe 协议规则
│   ├── rtl/                          # 编码指南、FSM/FIFO/流水线/握手示例
│   ├── patterns/                     # 仲裁器、信用流控、CRC、ECC、宽度转换等
│   ├── synthesis/                    # CDC、约束、综合指导
│   ├── verification/                 # 测试台（骨架+BFM）、断言、仿真闭环、Golden Reference、**Icarus 陷阱**
│   ├── debug/                        # Bug pattern 库（66+ pattern）
│   ├── design/                       # **7 大设计原则（P5a/P5b 拆分）**、启发式、PTA 规则
│   ├── project/                      # 棕地开发、大模块指导
│   └── advanced/                     # 低功耗、DFT、UVM、物理感知
├── evals/                            # 63 个评估 prompt、23 个试用、4 个 bug fixture
├── scripts/                          # 10 个 Python 脚本
└── projects/                         # 16 个已验证项目 + A/B 实验（含 NVMe Phase 1、Split-Merge Pipeline）
```

## 核心能力

### 7 大设计原则（核心创新，含复杂度闸门）

66+ 个 bug pattern 被组织在 7 个核心设计原则之下。**P5 已被拆分**（R5-R8 实验数据显示 P5 在 leaf module 上从未触发——输出纪律和物理实现是正交的关注点）。每个原则都有**何时跳过/简化**规则，避免在不适用的问题上浪费时间：

| # | 原则 | 适用范围 | 核心问题 |
|---|------|:---:|---------|
| P1 | 每个信号都有时序合同 | L1/L2 | 每个输出的信号类型（脉冲/电平/寄存器）是否已文档化？ |
| P2 | 每个状态机都必须能回家 | L1/L2（线性 FSM 简化） | 每个状态是否能回到 IDLE？是否有 abort 路径？ |
| P3 | 每个寄存器在任何时刻的值都必须可知 | **全部** | 复位后每个寄存器是什么值？ |
| P4 | 独立的事物必须保持独立 | L1/L2（单通道跳过） | 独立通道/路径/时钟域是否解耦？ |
| P5a | 每个输出都对下一个工程师负责 | L1/L2 | 模块边界输出是否从寄存器驱动（非组合 state_q）？ |
| P5b | 物理世界永远赢 | 仅 L2/ASIC | 功耗门控、DVFS、布局——FPGA 和 L0/L1 跳过 |
| P6 | Bug 藏在边界处 | 全部（单模块简化） | 每个模块边界是否有显式合同？ |

详见 `references/design/design-principles.md`（含主动搜索问题、协议无关化、跳过/简化规则）。

### 66+ 个 Bug Pattern（全部带权威来源）

| 类别 | 数量 | 示例 |
|------|------|------|
| 握手 (H1-H8) | 8 | 载荷稳定性、ready 循环、valid 门控 |
| 协议 (P4-P13) | 10 | AXI 通道分离、WVALID burst、APB 时序 |
| 计数器/状态 (P14-P18) | 5 | 自动重载竞争、专用清除、流水线延迟 |
| 状态机 (SM1-SM3) | 3 | 影子数据通路、FSM abort 路径 |
| 数据通路 (DP1-DP5) | 5 | 宽度转换、bit-slicing、错误路径 |
| RTL 正确性 (E1-E8) | 8 | Latch 推断、多驱动、截断、阻塞/非阻塞 |
| FIFO (F1-F2) | 2 | FWFT 输出偏移、寄存器输出竞态 |
| CDC (D1-D2) | 2 | 格雷码、ASYNC_REG |
| 低功耗 (LP1-LP7) | 7 | 隔离时序、保持握手、DVFS 门控 |
| 物理感知 (PH1-PH4) | 4 | 注册 I/O、扇出控制、SRAM 邻近、总线分组 |
| 验证盲点 (V1) | 1 | 结构 PASS 但功能 FAIL |
| **Testbench 陷阱 (A1-E1)** | **16** | **Icarus 特定：return/break 不支持、delta-cycle race、#1 settling、地址别名、while(busy_o) 时序** |

### Icarus Testbench 陷阱（16 个已文档化）

R5-R8 实验发现 16 个反复出现的 Icarus 特定 testbench bug。每个陷阱都有 broken/fix 代码、权威来源引用和实证验证。分类：语法兼容（return/break/ref）、delta-cycle 时序、协议合规、结构问题、CDC。详见 `references/verification/icarus-common-pitfalls.md`。

### 标准 Testbench 骨架 + BFM 库

`references/verification/tb-examples.md` Section 0 提供可直接复制的骨架（含安全时钟生成、错误累计、输出协议标记）。APB BFM（write/read/check/PSLVERR，符合 ARM IHI 0024C）和 AXI-Stream BFM（send/recv/packet，符合 ARM IHI 0051B）。

### Golden Reference 功能验证（强制）

6 种 Golden Reference 策略覆盖所有模块类型。全部 6 种策略已在 10+ 个真实项目中验证。

### 仿真闭环 + 原则驱动 Debug

完整的闭环验证：先读 `icarus-common-pitfalls.md`（强制）→ `iverilog` 编译 → `vvp` 仿真 → Phase 4 原则驱动 debug（重读 2a/5a/8c 原则审查文档再修 bug）→ bug pattern 匹配 → 最小修复 → 重跑。最多 3 次迭代。

### A/B 实验方法论（4 轮已验证）

R5-R10 实验为工作流决策建立了证据基础。分布式检查点将子系统仿真迭代减少 3×。原则疲劳已确认——6 原则堆在一起会漏 bug。R9-R10 验证了 Step 8d 原则驱动 debug（P2/P3 bug 类型）。复杂度闸门从数据中校准。

## 协议覆盖

| 协议 | 来源 | 参考文件 |
|------|------|---------|
| AXI4 Full | Arm IHI 0022 | axi-full-guidelines, axi-multi-outstanding, axi-dma-channel |
| AXI4-Lite | Arm IHI 0022 | axi-lite-guidelines |
| APB | Arm IHI 0024 | apb-guidelines |
| AHB-Lite | Arm IHI 0033 | ahb-lite-guidelines |
| AXI4-Stream | Arm IHI 0051 | axi-stream-guidelines |
| NVMe | NVM Express 2.3 + NVM Cmd Set 1.2 | nvme-guidelines（Admin + NVM I/O + PRP 遍历） |

## 设计模式目录（18 个）

Ready/valid 寄存器切片、Skid buffer、FIFO、流水线阶段、FSM（双进程）、仲裁器（固定/轮询）、信用流控、重试缓冲、宽度转换、CRC 生成器、SECDED ECC、多 bank 存储调度、计数器/寄存器切片、req/ack 适配器、限速器、帧组装器、CAM、AXI DMA 切片。

## 已验证项目（14 个 + 4 轮 A/B 实验）

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
| **Low-Power SoC** | **子系统** | **28/28** | **LP1-LP7 + PH1-PH4 全验证** |
| **AXI-S→APB Bridge** | **双协议** | **36/36** | **E2E 工作流验证，发现 B6 pitfall** |
| **Split-Merge Pipeline** | **流水线** | **5/5** | **3 条模式：反压丢数据、对齐延迟反模式、信号类型不匹配** |
| **NVMe Admin Engine** | **存储** | **2/2** | **首个领域扩展，5 模块 L2 子系统，AXI 适配器** |

### A/B 实验轮次

| 轮次 | 项目 | 结果 | 核心发现 |
|:---:|------|------|------|
| R5 | AXI-S Packet FIFO | 双方 12/12 | 首次分布式检查点试验 |
| **R6** | **AXI-S 2×2 Switch** | **新：0 RTL bug，旧：2 bug** | **3× 更少迭代，bug 在 Step 5a 被发现** |
| R7 | Width Converter | 无效（合同不匹配） | 实验设计教训 |
| R8 | UART TX + I2C | 双方 6/6（UART） | Leaf module 天花板确认 |
| **R9** | **UART TX（P2 bug）** | **32K tokens, 44s** | **Step 8d Keeper Test 通过** |
| **R10** | **UART TX（P3 bug）** | **30K tokens, 55s** | **跨原则验证：P2+P3 均有效** |

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
