# Skill Iteration Changelog

记录 digital-front-end-skill 的迭代历史：每次项目 review 发现的 skill 缺陷、改进措施、当前状态。

---

## 2026-05-30 — R5-R8 复盘驱动的工作流迭代（三档闸门 + P5 拆分 + 原则可跳过 + 8d 迁移）

### 背景

R5-R8 四轮 A/B 实验的复盘分析发现了 7 个根因：
1. P5 物理世界原则 4 轮零触发 — "output discipline" 和 "power gating" 混在一起
2. Agent B 在 I2C 项目上 3 次超时 — 复杂度闸门只有 1D（代码行数）
3. UART TX 的 2a/5a 零发现 — 检查点是固定指派的，不是按需触发的
4. Step 8d 从未被需要 — 夹在 8c 和 9 之间，仿真直接过就跳过了
5. 旧流程 8c 漏了 APB delta-cycle race — 原则抓不住新的 failure mode
6. I2C 无 reference → agent 模式断裂 — 没有 "first-contact protocol" 回退
7. R7 实验合同不匹配 — 缺少 contract compliance check

### 改动文件

| 文件 | 改动 | 行数变化 |
|------|------|:---:|
| `SKILL.md` | Step 1: 三档复杂度闸门 (L0/L1/L2) + 分解建议；Step 2a/5a: L0 跳过条件；Step 8c: 三档闸门 + P5a/P5b 拆分；Step 9: 集成原 8d 到 Phase 4 | 305→338 (+33) |
| `references/design/design-principles.md` | P5 拆为 P5a(Output Discipline) + P5b(Physical Impl)；P1-P6 每个增加 "When to skip/lite"；P4/P6 增加协议无关首问；更新检查点表和映射表 | ~200→257 (+57) |

### 改动详情

**三档复杂度闸门：**
| Level | 标准 | 审查范围 |
|:---:|---|------|
| **L0: Trivial** | ≤200行, ≤8 FSM states, 线性流 | 跳过 2a/5a，仅 P3 at 8c |
| **L1: Leaf** | 200-500行, 或非线性FSM, 或双协议 | FAST: 1-2 问/原则 |
| **L2: Subsystem** | >500行, 或多模块, 或多时钟 | FULL: 3-5 问/原则 + P5b + 分解建议 |

**P5 拆分：**
- P5a (Output Discipline): 始终适用于 L1/L2 — registered I/O, counter gating, bit widths, pulse width
- P5b (Physical Implementation): 仅 L2/ASIC — power gating, DVFS, placement, fanout

**原则可跳过判定：**
- P1: L0 skip (信号分类在合约阶段内联完成)
- P2: LITE 模式 (线性 FSM 跳过 abort 路径分析), 无 FSM 则完全跳过
- P3: 所有 level 适用 (最一致地抓到 bug)
- P4: 单通道/单时钟域/无并发 → skip
- P5a: L0 skip
- P5b: L0/L1 skip, FPGA skip
- P6: 单模块 LITE (只检查端口宽度)

**P4/P6 协议无关化：**
- 每个原则首问改为 protocol-independent (列举独立关注点 → 检查解耦)，然后才切入协议特化问题 (AXI/Serial/CDC)
- 解决了 I2C/UART 等非 AXI 协议下 agent 标记 NA 的问题

**Step 8d 迁移：**
- 从独立步骤 (夹在 8c 和 9 间) 迁移到 Step 9 Phase 4 (Failure Analysis) 的第一步
- 不再是被跳过的独立步骤，而是仿真 debug 的标准流程

### 实验依据

详细分析见 `projects/test-workflow-round8/SKILL_IMPROVEMENT_ANALYSIS.md`。

### SKILL.md 行数

~338 / 500 行

---

## 2026-05-30 — A/B 实验 Round 8（最终轮）：UART TX + I2C 工作流稳定性验证

### 实验设计

**项目：** UART Transmitter + APB（~240 行，Leaf）+ I2C Master Controller + APB（~614 行，Leaf++，补充数据）

**对照：** Agent A（旧工作流，6 原则全堆 Step 8c）vs Agent B（新工作流，三检查点 + FAST 闸门）

### 核心结果（UART TX）

| 指标 | Agent A（旧）| Agent B（新）| 差异 |
|------|:---:|:---:|:---:|
| 仿真 | 6/6 PASS | 6/6 PASS | — |
| 仿真迭代 | **4** | **2** | B 快 2× |
| RTL 行数 | 240 | 357 | B 多 117 行（更完整的文档和 registered outputs）|
| RTL bug（预仿真）| 0 | **1（Step 8c）** | B 发现更早 |
| RTL bug（仿真）| **1（iter 2）** | 0 | A 的 APB delta-cycle race 被仿真抓到 |
| Testbench bug | 2 | 0 | B 的 testbench 更干净 |

### Bug 发现时机对比（UART TX）

| 检查点 | Agent A | Agent B |
|--------|:---:|:---:|
| Step 2a（P4+P6）| ❌ 跳过 | 0 bug |
| Step 5a（P1+P2）| ❌ 跳过 | 0 bug |
| **Step 8c（P3+P5）** | 0 bug（6 原则全 PASS，漏了 APB race）| **1 bug: fifo_rd_en_o 名字不匹配** |
| Step 9 iter 1 | 编译错误 | 编译错误 |
| Step 9 iter 2 | **APB delta-cycle race** | 时序调整 |
| Step 9 iter 3 | T2 测试顺序 | — |
| Step 9 iter 4 | All PASS | All PASS (iter 2) |

### I2C 补充实验

| Agent | 结果 | 备注 |
|-------|------|------|
| Agent A（旧）| ✅ 29/29 PASS, 614 行, 8 bug | P7 agent, ~36 分钟 |
| Agent B（新）| ❌ 3 次超时 | 1 次 harness error, 2 次 watchdog stall |

I2C controller 的复杂度（13 FSM 状态 + SCL 生成 + 时钟拉伸 + ACK 追踪 + 9 APB 寄存器）超出单 sub-agent 的 600s 窗口。Agent A 仅在 P7 的结构化方法下才完成，Agent B 的分布式检查点文档开销推高了时间。

### 跨轮次分析（R5-R8）

| 项目复杂度 | 工作流差异 | 证据 |
|-----------|-----------|------|
| **低**（UART TX, FIFO, Width Conv）| 极小 — 两者正确，1-2 次迭代差 | R5, R7, R8 |
| **中-高**（AXI-S Switch, I2C）| **显著** — 3× 更少迭代，bug 在 Step 5a 被抓 | R6 |
| **很高**（I2C 全特性）| Sub-agent 模型不可完成 | R8b |

### 关键发现

1. **Leaf module 天花板确认：** 对 ≤300 行的简单模块，分布式检查点的价值是边际的。复杂度闸门应该**更激进**：对 ≤200 行 + 线性 FSM 的项目，直接跳过 Step 2a 和 5a。

2. **P5 物理世界原则仍是短板：** R5-R8 共 4 轮实验，P5 零问题发现。不是因为设计完美——因为问题太抽象。Leaf module 需要更具体的 P5 检查项（如"所有输出是否从寄存器驱动而非组合 state_q"）。

3. **Sub-agent 可扩展性天花板：** ~500 行 / ~10 FSM 状态是单 sub-agent 的可靠上限。分布式工作流增加约 30% 的文档开销，可能把接近上限的项目推过边界。

4. **复杂度闸门需要"分解建议"：** 不只是 Leaf vs Subsystem 审查深度，还需要在预计 >400 行时建议拆分为多 agent。

5. **Step 8d 仍未压力测试：** 4 轮实验中没有一次需要在仿真失败后深挖原则文档——所有项目在 1-4 次迭代内通过。

### 结论

**分布式检查点工作流对子系统级设计（>300 行、多模块、多协议）验证有效。** 对 leaf module 应更激进地跳过早期检查点。工作流应成为永久设计，增加按复杂度自动分类的机制。

详见 `projects/test-workflow-round8/EXPERIMENT_REPORT.md`。

### SKILL.md 行数

~305 / 500 行（本轮纯实验验证，无文件改动）

---

## 2026-05-30 — A/B 实验 Round 6：新工作流端到端验证

### 实验设计

**项目：** AXI4-Stream 2×2 Switch with APB Routing（子系统，4 子模块，双协议）

**对照：** Agent A 用旧工作流（6 原则堆在 Step 8c），Agent B 用新工作流（三检查点分散 + 复杂度闸门 FULL + 修复纪律）

### 核心结果

| 指标 | Agent A（旧） | Agent B（新） | 差异 |
|------|:---:|:---:|:---:|
| 仿真 | 12/12 PASS | 7/7 PASS | — |
| 仿真迭代 | **3** | **1** | B 快 3× |
| Yosys cells | 791 | 948 | B 大 20%（多 registered I/O） |
| Yosys DFFs | 82 | 202 | B 多 120 flops |
| Yosys latch | 0 | 0 | 都干净 |
| 设计 bug（预仿真） | 2（Step 7） | **1（Step 5a）** | B 发现更早 |
| Testbench bug | 6 | 0 | B 干净 |

### Bug 发现时机对比

| 检查点 | Agent A | Agent B |
|--------|:---:|:---:|
| Step 2a（合约：P4+P6） | ❌ 跳过 | 0 bug |
| **Step 5a（迹线：P1+P2）** | ❌ 跳过 | **1 bug：仲裁器 grant 卡死** |
| Step 7（RTL 自审） | 2 bug | — |
| Step 8c（RTL 后） | 0 bug | 0 bug |
| Step 9（仿真） | 6 bug（全 testbench） | 0 bug |

### 架构差异

| 决策 | Agent A | Agent B |
|------|---------|---------|
| Router tready | Combinational | **Registered** |
| Arbiter 输出 | Combinational (wire) | **Registered (flop)** |
| PH1 合规性 | PARTIAL（自评） | Full |
| 数据路径延迟 | 0 cycle | 1 cycle |

### 关键发现

1. **分布式审查让 bug 在 Step 5a 被发现**——Agent B 在写 RTL 之前通过 P2 FSM 安全性检查抓到了仲裁器 race condition（grant 选中但 valid 撤销→永久卡死），修复只需修改迹线。Agent A 的等价 bug 在 Step 7（RTL 写完后）才发现。

2. **复杂度闸门产生更安全的架构**——Agent B 的 PH1 registered I/O 决策是 Step 5a P1 时序分析的直接结果；Agent A 把所有原则堆到最后，默认走了组合透传。

3. **认知负荷降低是真实效果**——2 原则/次 × 3-5 问 vs 6 原则/次 × 42 问。Agent A 在 42 问中错过了地址解码别名（`paddr_i[4:2]` 把 0x40 映射为 0x00），直到仿真第 3 轮才被 PSLVERR 测试抓到。

4. **Step 8d 未触发**——Agent B 仿真一次通过，不需要用原则文档 debug。需要后续实验专门注入 bug 来验证 Step 8d 效果。

5. **6 个 testbench 基础设施 bug 是独立信号**——skill 缺少"常见 Icarus testbench 陷阱"reference。

### 结论

**新工作流验证有效。** 三检查点分散 + 复杂度闸门应该成为永久设计。详见 `projects/test-workflow-round6/EXPERIMENT_REPORT.md`。

### SKILL.md 行数

~305 / 500 行（本轮无文件改动，纯实验验证）

---

## 2026-05-30 — 工作流重构：原则审查分散化 + 复杂度闸门 + 8c 定位调整

### 问题背景

四轮 A/B 实验暴露了工作流层面的三个结构性问题：

1. **6 原则全部堆在 Step 8c**（RTL 完成后），导致审查负担过重（18-30 个问题），且错失了早期发现架构问题的机会（R1 的 tready 隔离 bug 如果在合约阶段审查 P4 就不会出现）
2. **8c 被定位为"仿真前的门"**，但实际 Agent 行为是先跑仿真再补文档——工作流暗示瀑布，但真实过程是迭代
3. **所有设计同等对待**——100 行 leaf module 和 1500 行子系统走相同的 8c 流程

### 改动

| # | 改动 | 文件 |
|---|------|------|
| 1 | **原则审查分散到三个检查点**：Step 2a（合约后，P4+P6）→ Step 5a（迹线后，P1+P2）→ Step 8c（RTL 后，P3+P5） | `SKILL.md` |
| 2 | **复杂度闸门**：leaf module（≤300 行）做快速审查（1-2 问/原则），子系统做完整审查（3-5 问/原则） | `SKILL.md` Step 8c |
| 3 | **新增 Step 8d**："仿真失败后，对照原则审查文档定位根因"——8c 从前置门变为 debug 工具 | `SKILL.md` |
| 4 | `design-principles.md` "How to use" 更新为三检查点表 | `references/design/design-principles.md` |

### 审查时机设计

| 检查点 | 原则 | 时机理由 |
|--------|------|---------|
| Step 2a | P4 独立性, P6 边界 | 架构耦合和边界不匹配在写代码前修复成本最低 |
| Step 5a | P1 时序合约, P2 FSM 安全 | 周期迹线是验证信号时序和 FSM 行为的最佳时机 |
| Step 8c | P3 已知值, P5 物理世界 | 需要实际 RTL 代码才能审查：寄存器初始化、物理约束 |

### SKILL.md 行数

~305 / 500 行

### 实验依据

- R1: Agent A 的 tready 隔离 bug（P4）——如果在 Step 2a 审查 P4 就能预防
- R3: Agent B 的 4 个 8c 发现中 2 个是 P1/P2 问题——如果在 Step 5a 审查就能更早发现
- R4: Agent B 的 8c 发现全部是 P1/P3/P5——分散到三个检查点后每步只需审查 2 个原则
- R1-R4 汇总：有原则审查文档的 Agent debug 快 34%

### R5 A/B 验证实验 (2026-05-30)

对上述三点改动进行对照实验验证。项目：**AXI4-Stream Switch (2-in, 2-out) + APB Routing Config**（4 模块，~500 行 RTL）。

| | Agent A (对照组) | Agent B (实验组) |
|------|------|------|
| 工作流 | 旧：全部 6 原则堆在 Step 8c | 新：2a(P4+P6) → 5a(P1+P2) → 8c(P3+P5) |
| 复杂度闸门 | 无（全模块同样审查深度） | 有（4 个 leaf module 快速审查，1 个 top 完整审查） |

#### 实验数据

| 指标 | Agent A (旧) | Agent B (新) | 差异 |
|------|:---:|:---:|------|
| 仿真结果 | 12/12 PASS | 8/8 PASS | — |
| **RTL 功能 bug** | **3** | **0** | 新工作流零 RTL bug 🏆 |
| **合约阶段发现** | 0 (跳过 2a) | 0 bug, 1 设计决策固化 | P4 审查驱动了 dest_port_q 寄存器设计 |
| **迹线阶段发现** | 0 (跳过 5a) | **1 个中等 bug** | P2 审查发现 arbiter grant 无 abort 路径 |
| **8c 阶段发现** | 0 (原则疲劳) | 0 bug, 4 项 fix discipline 优化 | P3 全寄存器扫描 + P5 PH1 验证确认干净 |
| 仿真迭代 | 3 | 6 | — (B 的迭代全是 testbench 竞态，非 RTL 问题) |
| Token 消耗 | 185K | 261K (+41%) | B 多产出 3 份原则审查文档 |

#### Agent A 的 3 个 RTL bug 详情

| # | Bug | 发现阶段 | 根因 | 对应原则 |
|---|-----|---------|------|---------|
| 1 | Router IDLE 状态 `tready=1` 但无转发逻辑，首 beat 丢失 | Step 7 设计审查 | FSM 在 IDLE 接受数据但未连接到输出 | **P2**（FSM 路径不完整） |
| 2 | Arbiter 单 beat packet 完成后 rr_ptr 未更新，公平性被破坏 | Step 7 设计审查 | 单 beat 快速路径绕过了 rr_ptr 更新逻辑 | **P2**（状态转换遗漏） |
| 3 | APB 地址解码 `paddr_i[4:2]`，0x40 别名到 0x00 | 仿真迭代 3 | 参数化解码覆盖了无效地址 | **P6**（边界匹配不精确） |

**关键洞察：** Agent A 的 3 个 RTL bug 全部属于 P2 (FSM) 和 P6 (Boundary) 范畴——这正是新工作流在 Step 2a 和 Step 5a 就审查的原则。如果 Agent A 在合约/迹线阶段执行了 P2+P6 审查，这 3 个 bug 在写 RTL 之前就会被发现。

#### Agent B 的 Step 5a 发现的 bug 详情

**P2 FSM Safety — Arbiter grant abort path（中等严重度）：**

P2 Q4（"如果 winner 的 tvalid 在 tready 之前 deassert 怎么办？"）发现：一旦 arbiter 授予 grant，如果被选中输入端在未发送 TLAST 的情况下 deassert valid，arbiter 会永久卡在 ACTIVE 状态。修复：新增 abort 条件——`if grant_q != 0 && selected_in_valid == 0 && !seen_tlast → clear grant, return IDLE`。

这个问题 Agent A 的设计中同样存在（其 arbiter 也用 grant 状态机），但 Agent A 的 Step 8c P2 审查标记为 "PASS: All FSMs have IDLE, default case, abort paths"——被"原则疲劳"漏掉了。

#### Agent B 的 8c fix discipline（P3+P5 确认干净后的优化）

虽然 8c 未发现新 bug，但通过 fix discipline 做了 4 项优化：

| 优先级 | 策略 | 操作 |
|:---:|------|------|
| 1 | Delete | 删除 arbiter 中未使用的 `grant_sel_r` 寄存器 |
| 2 | Retime | 将 router 的 `s_axis_tready_o` 从组合逻辑改为寄存器输出 |
| 3 | Constrain | `arb_ready_o` 增加 grant match + slot_free 门控条件 |
| 4 | Add | 增加 `other_req` 检查防止 TLAST 完成时的竞争条件 |

#### 复杂度闸门验证

Agent B 的 8c 对所有 4 个 leaf module（apb_regs 96 行、router 106 行、arbiter 130 行、top 143 行——均 ≤300 行）使用了快速审查（1-2 问/原则），2 分钟内完成。Agent A 对同样模块做了全套 6 原则 18-30 个问题的大审查——反而一个 bug 都没检出来。证明了"少而深 > 多而浅"。

#### 核心结论

1. **分散检查点有效**：Agent B 在迹线阶段（Step 5a）发现了 Agent A 漏掉的 FSM abort bug。Agent A 的 3 个 RTL bug 全部属于 P2/P6 范畴——如果执行了 Step 2a 和 5a 审查就能预防。
2. **原则疲劳是真实的**：Agent A 的 8c 全 6 原则审查检出 0 个 bug，而同一设计在 Step 7 设计审查中发现了 2 个真实 bug。当一次性面对 6 个原则时，审查变成勾选框而不是深度思考。
3. **8c 的新角色验证有效**：Agent B 的 8c 不再是"最后的防线"，而是效率型质量确认——P3 全寄存器扫描 + P5 物理约束检查，2 分钟确认干净，然后用 fix discipline 做优化。
4. **复杂度闸门减少浪费**：leaf module 不需要 5 问/原则的深度审查。2 问够用。多出来的精力应该投入子系统级集成审查。
5. **成本换质量**：+41% token 换来 RTL 零 bug + 3 份可复用审查文档 + 干净的架构。这个 tradeoff 是可接受的。

---

## 2026-05-29 — SKILL.md 索引优化 + Step 8c 修复纪律

### SKILL.md 瘦身

SKILL.md 从 ~467 行减至 ~330 行。策略：offload 详细规则到 references/，SKILL.md 保留目录式入口。

| 改动 | offload 到 | 节省 |
|------|-----------|:--:|
| Step 8 自审清单（65 项） | `references/verification/self-review-checklist.md`（新建） | ~95 行 |
| Step 12 子代理 prompt 模板 | `references/architecture/sub-agent-delegation.md`（新建） | ~32 行 |
| Step 9 仿真循环+综合步骤 | 已有 references（simulation-loop.md, synthesis-feedback-guide.md） | ~25 行 |

### Step 8c 修复纪律

基于 R3 实验：Agent B 用 8c 发现 4 个 bug 但倾向"加硬件"修复（如新增 4 个锁存寄存器），引入复杂度反噬→3 个残留问题。Agent A 用 FSM 级门控自然规避。新增修复优先级：**1.删 → 2.改时序 → 3.FSM级约束 → 4.加硬件（最后手段）**。

### 改动文件

| 文件 | 改动 |
|------|------|
| `SKILL.md` | Step 8→routing table; Step 9/12 压缩; Step 8c+修复纪律 |
| `references/verification/self-review-checklist.md` | **新建** |
| `references/architecture/sub-agent-delegation.md` | **新建** |

### SKILL.md 行数

~330 / 500 行

---

## 2026-05-29 — Step 8c 自审化 + A/B 实验驱动改进

### A/B 对比实验

验证 Step 8c（设计原则审查）的"主动搜索"效果：两个子代理并行实现 Pattern Generator (APB+AXI-Stream)，Agent A 用旧流程（Step 8 only）、Agent B 用新流程（Step 8c→Step 8→Step 9）。

**核心发现：**
- 两者均 10/10 仿真通过，Yosys 0 latch
- 8c checklist 式审查（预编写 YES/NO 表）**未主动预防任何 bug**——所有 bug 均为仿真发现后回溯映射到原则
- 但 Agent B（有 8c）的架构质量更优：FSM 作为唯一控制源、纯 datapath core、无 P4 架构缺陷
- Agent A（无 8c）出现了关键 P4 独立性 bug：APB 事务期间 AXI-Stream beat 被意外消耗，需 testbench workaround
- 8c 作为 **架构 mindset**（设计前阅读原则）可能比作为 **形式化审查工具**（填表）更有价值

### 据此改进（4 项）

| # | 改动 | 文件 |
|---|------|------|
| P0 | Step 8 Integration 新增 P4 独立性检查：APB/配置路径与数据路径不得共享状态，APB 事务不得意外消耗 AXI-Stream 数据 | `SKILL.md` Step 8 |
| P2 | Step 7 新增模块边界 discipline段落：推荐 registered I/O，解释 combinational 跨层次输出的风险（时序、glitch、testbench 时序复杂性） | `SKILL.md` Step 7 |
| P3 | 新增 E1b 反模式：`output reg` + `assign` 混用 — 含 Yosys warning、Bug 4 案例、正确/错误代码对比 | `references/rtl/correctness-rules.md` |
| — | **Step 8c 从 checklist 式重写为自审式**：不再用预编写 YES/NO 表格，改为要求 Agent 针对自己的具体 RTL 动态生成审查问题，引用实际信号名、FSM 状态、模块边界，追踪周期级行为。含 good/bad 示例对比 | `SKILL.md` Step 8c |
| — | `design-principles.md` "How to use" 更新：明确 active-search questions 是生成自审问题的**提示**，不是预制 checklist | `references/design/design-principles.md` |

### Step 8c 核心变化

```
旧：读原则 → 填预制 YES/NO 表 → 交差
新：读原则 → 看自己的 RTL → 自问自答具体问题（"done_o 在 S_DONE→S_GENERATE 转换时脉冲多宽？"）→ 追踪信号路径 → 修复 → 记录
```

这一步的关键洞察来自用户：**如果在原则之上再套一层 checklist，那为什么还需要凝练出六大原则？** 原则的价值在于思维方式的变化——从"逐条匹配"变为"原则驱动自审"——而不是把 checklist 从 57 项压缩成 6 项。

### SKILL.md 行数

~467 / 500 行

---

## 2026-05-29 — 设计原则驱动重构（缺陷 #4：单点经验 → 原则体系）

### 问题背景

Skill 的 57 个 bug pattern 是"单点经验"——每个 pattern 来自一个项目的一个 bug，pattern 之间独立，agent 只能逐条匹配。有经验的工程师不靠逐条匹配，他们应用 6-8 个核心设计原则，从原则推导出潜在问题。

**核心洞察：** 单点经验 = pattern 是 bug 的镜像，不是原则的特例。要修缺陷 #4（"规则 vs 经验"），应该从"补更多 pattern"转向"提炼更少但更深的原则"。

### 改动文件

| 文件 | 改动 |
|------|------|
| `references/design/design-principles.md` | **新建** (~200 行)：6 个核心设计原则，每个原则有：核心洞察、为什么重要、6-7 个主动搜索问题、覆盖的 pattern 列表、原则→pattern 映射表 |
| `references/debug/bug-pattern-library.md` | 新增"Design Principles"章节（顶部）：原则速查表 + 使用流程 |
| `SKILL.md` Step 8c | 新增"Design principle review"步骤：6 个原则的 YES/NO/NA 审查表，强制 agent 在仿真前做主动搜索 |
| `references/reference-index.md` | 新增 design-principles.md 索引条目 |

### 6 个核心设计原则

| # | 原则 | 一句话 | 覆盖 pattern 数 |
|---|------|-------|----------------|
| P1 | Every Signal Has a Timing Contract | 每个信号必须分类为 pulse/level/registered | 10 |
| P2 | Every State Machine Must Find Its Way Home | 每个 FSM 状态必须能回到 IDLE | 8 |
| P3 | Every Register Has a Known Value | 每个寄存器在任何时刻的值都必须可知 | 10 |
| P4 | Independent Things Must Stay Independent | AXI 通道/时钟域/读写路径必须解耦 | 7 |
| P5 | The Physical World Always Wins | RTL 必须尊重功耗/时序/面积约束 | 10 |
| P6 | Boundaries Are Where Bugs Hide | 每个模块边界必须有显式合约 | 5 |

### 自审流程变化

```
旧流程: Step 7 (RTL生成) → Step 8 (57项逐条匹配) → Step 9 (仿真)
新流程: Step 7 (RTL生成) → Step 8c (6原则主动搜索) → Step 8 (57项逐条匹配) → Step 9 (仿真)
```

Step 8c 不是为了替代 Step 8，而是作为**前置透镜**——先用原则发现"可能有问题的地方"，再用 pattern 确认具体是什么问题。

### SKILL.md 行数

415 / 500 行

### 设计决策

- **原则放在 references/ 而非 SKILL.md 内联**：原则文档 ~200 行，放 SKILL.md 会突破 500 行限制。Step 8c 在 SKILL.md 中只有审查表（~30 行），详细内容按需加载。
- **原则不是替代 pattern，是增强**：pattern 仍然存在且有用。原则帮助发现"没有 pattern 覆盖的新 bug"，pattern 提供"已知 bug 的修复模板"。
- **主动搜索 > 被动匹配**：旧方法是被动等 pattern 匹配（"这个设计有没有 H1"），新方法是主动搜索（"这个设计的 pulse 信号有没有用状态比较"）。

---

## 2026-05-29 — Low-Power SoC 子系统端到端验证 + Debug 闭环

### 项目概要

构建 6 模块 Low-Power SoC 子系统（psm + dvfs_ctrl + clk_gate_ctrl + phys_aware_datapath + apb_regs + soc_top），~1500 行 RTL，5 子代理并行生成，28 项测试。

**结果：28/28 ALL_TESTS_PASS，Yosys 综合 0 latch，9,384 cells。**

### 发现的 7 个 RTL Bug

| ID | 模块 | Bug | 根因 | 类型 |
|----|------|-----|------|------|
| BUG-1 | psm | wake_ack_o 复位后错误触发 | 状态比较而非转换检测 | 功能 |
| BUG-2 | dvfs | freq_req 是 level 不是 pulse | 接口合约未指定信号类型 | 接口 |
| BUG-3 | dvfs | S_CHECK_IDLE 无 abort 路径 | FSM 缺少请求撤销处理 | 结构 |
| BUG-4 | datapath | SRAM 未初始化→'x' 传播 | 未处理存储器上电状态 | 功能 |
| BUG-5 | clk_gate | output reg + assign 混合驱动 | 端口声明类型错误 | 语法 |
| BUG-6 | apb_regs | 寄存器 PRDATA 延迟未记录 | 验证指导缺少时序说明 | 验证 |
| BUG-7 | CG | gate_en 位映射含义反直觉 | 寄存器位极性未文档化 | 接口 |

### Debug 过程中的额外发现（3 个）

| ID | 发现 | 影响 |
|----|------|------|
| D1 | SRAM 地址指针递增导致读取未初始化槽位 | BUG-4 的第二层根因 |
| D2 | dp_start level 信号导致流水线无限重触发 | 需要 pulse 信号或忙锁存 |
| D3 | dp_done pulse 无法被 polling 方式检测 | 需要 sticky status 或 result latch |

### Skill 文件改动

| 文件 | 改动 |
|------|------|
| `bug-pattern-library.md` | 新增 SM3（FSM abort path）+ LP7（pulse transition detection）|
| `low-power-guidelines.md` §4 | 新增 LP7 模式：脉冲输出必须用转换检测 |
| `SKILL.md` Step 8 | 新增 4 项自审检查：LP6、LP7、SM3、PH-init |

### Pattern 验证状态

| Pattern | 验证结果 |
|---------|---------|
| LP1-LP3 | PASS — PSM 隔离/保持/状态机正确 |
| LP4 | PASS — CDC 脉冲同步器 + ASYNC_REG |
| LP5 | PASS — DVFS bus idle gate + abort path |
| LP6 | PASS — 操作数隔离覆盖完整 DVFS 窗口 |
| PH1-PH4 | PASS — 注册 I/O、max_fanout、SRAM 同层、总线分组 |

### 核心教训

**所有 5 个子代理自审 PASS 但 5/6 模块有真实 bug** — 第三次验证 P18（结构审查 ≠ 功能正确）。自审清单必须持续强化。

### SKILL.md 行数

~410 / 500 行

---

## 2026-05-29 — 低功耗与物理感知增强（L1→L2+）

### 问题背景

Skill 能力审计发现低功耗（89 行，L1）和物理感知（117 行，L1）是两个最薄弱的领域。现有内容仅停留在概念介绍层面，无法指导实际 RTL 设计。需要提升到可执行的 RTL 模式指导（L2+）。

### 改动文件

| 文件 | 改动 |
|------|------|
| `references/advanced/low-power-guidelines.md` | 89→~350 行：新增 PSM、retention flop、isolation cell、level shifter、power-aware CDC、DVFS 控制器、低功耗存储器设计 |
| `references/advanced/physical-awareness-guidelines.md` | 117→~350 行：新增 floorplan-aware RTL、macro placement、congestion-aware coding、wire delay pipeline、IR drop 缓解、CTS-aware、面积优化、Yosys 物理代理 |
| `references/debug/bug-pattern-library.md` | 新增 10 个 pattern：LP1-LP6（低功耗）、PH1-PH4（物理感知） |
| `SKILL.md` Step 8 | 新增低功耗检查项（7 项）+ 物理感知检查项（4 项） |
| `references/reference-index.md` | 更新低功耗和物理感知条目描述 |
| `evals/evals.json` | 新增 4 个 eval（60-63）：电源门控模块、DVFS 控制器、floorplan 审查、时钟门控数据通路 |

### 新增 Bug Pattern 详情

| ID | Pattern | 类别 | 核心要点 |
|----|---------|------|---------|
| LP1 | 隔离使能时序违规 | 低功耗 | isolation enable 必须在 power-off 前使能 |
| LP2 | Retention save/restore 握手竞争 | 低功耗 | save 和 power-off 必须在不同 FSM 状态 |
| LP3 | 电源状态机非法状态转换 | 低功耗 | PSM 不得跳过必要中间状态 |
| LP4 | 门控时钟域穿越无同步器 | 低功耗/CDC | 门控域→非门控域必须用脉冲同步器 |
| LP5 | DVFS 频率切换期间有活跃传输 | 低功耗 | 频率切换必须在总线空闲时进行 |
| LP6 | 宽组合逻辑未应用操作数隔离 | 低功耗 | >32-bit 组合逻辑需要操作数隔离 |
| PH1 | 层次边界落在关键路径 | 物理 | 模块边界必须有寄存器 I/O |
| PH2 | 高扇出网络无寄存器复制 | 物理 | >50 扇出需要 max_fanout 属性 |
| PH3 | 存储器宏单元远离消费者 | 物理 | SRAM 和数据通路在同一层次 |
| PH4 | 总线信号未分组 | 物理 | 按通道分组端口声明 |

### 设计决策

- **纯 RTL 模式**：不涉及 UPF/CPF 命令，保持 Verilog-first 哲学
- **Yosys 作为物理代理**：用综合报告（cell count、critical path）替代后端工具
- **代码审查 + 仿真验证**：物理感知通过审查清单和 Yosys 综合验证，不需要 ICC2/Innovus

### SKILL.md 行数

~400 / 500 行

---

## 2026-05-28 — Golden Reference 方法论（解决"结构 PASS 功能 FAIL"系统性缺陷）

### 问题背景

19 个 trial 项目中，3 个出现了"结构审查 PASS 但功能错误"：
- CRC P18: 66 项自审全部 PASS，单 beat CRC 输出 = 0
- Crossbar: 路由逻辑完全不工作
- DMA: 传输从未完成

根因：Step 8 自审清单只检查结构正确性（命名、FSM 风格、协议、复位），不检查输出值是否正确。

### 新增文件

| 文件 | 行数 | 用途 |
|------|------|------|
| `references/verification/golden-reference-guide.md` | 122 | 6 种 golden reference 策略（A-F）+ 常见错误 |

### 策略体系

| 策略 | 适用模块 | 方法 |
|------|---------|------|
| A: 已知 I/O 对 | CRC、ECC、ALU | 从标准文档获取预计算的输入→输出对 |
| B: 软件参考模型 | 变长输入算法 | testbench 中独立实现的 Verilog function |
| C: 写回读记分板 | APB/AXI-Lite 寄存器块 | 写入值，读回，对比 |
| D: 数据完整性记分板 | DMA、FIFO、位宽转换器 | 输入入队，输出出队+对比 |
| E: 不变量检查 | 仲裁器、信用计数器 | 每周期连续检查属性 |
| F: 延迟检查器 | 流水线、寄存器切片 | 输入周期 vs 输出周期对比 |

### 修改文件

| 文件 | 改动 |
|------|------|
| `SKILL.md` Step 8b | 将窄范围 "Golden reference: for computation modules" 替换为 6 模块类型→策略映射表 |
| `references/verification/tb-examples.md` | 新增 section 9: 4 个 golden reference testbench 模板（9a-9d）|
| `references/verification/simulation-loop.md` | Phase 4 新增 Step 0（故障分类）+ 功能故障签名 + Step 6（功能回归）+ 2 项 checklist |
| `references/verification/verification-guidance.md` | 新增 5 层验证体系（T1-T5）|
| `references/debug/bug-pattern-library.md` | 新增 V1 pattern（结构 PASS 功能 FAIL）+ 更新自审限制规则 |
| `references/reference-index.md` | 新增 golden-reference-guide.md 索引条目 |

### SKILL.md 行数

371 / 500 行

### 关键设计决策

- Golden reference 不是 formal verification，也不是 UVM，而是在两者之间用最低成本抓住最常见的功能错误
- 策略 B 的核心约束：参考函数必须从规格独立推导，不能从 DUT 代码复制
- 所有模板兼容 iverilog（无 SVA、无 UVM class）

### 端到端验证（3 个项目并行验证）

| 项目 | 策略 | 原有测试 | Golden Reference | 开发中发现的问题 |
|------|------|---------|-----------------|----------------|
| pipeline_reg | F: 延迟检查器 | 3/3 PASS | 4/4 PASS | always 块竞态条件 |
| apb_regs | C: 写回读记分板 | 1/1 PASS | 9/9 PASS | prdata_o stale after idle_bus() |
| rr_arbiter | E: 不变量检查 | 1/1 PASS | 0 违规 | INV2 每周期检查产生 86 个误报 |

### 验证中发现的 Skill 缺陷（3 个）

| ID | 缺陷 | 根因 | 修复 |
|----|------|------|------|
| GAP-GR1 | Strategy E: 每周期检查 registered output + combinational input 的关系产生误报 | registered output 保持期间 combinational input 可以变化 | 只在事件边界（grant time）检查，用 pre-edge 采样 |
| GAP-GR2 | Strategy F: 输入捕获和输出检查分在不同 always 块产生竞态 | 同一 posedge 两个块的执行顺序不确定 | 合并为单个块，check-before-capture 顺序 |
| GAP-GR3 | Strategy C: 总线 idle 后采样 combinational output 得到 stale 值 | idle_bus() 清除地址，combinational output 反射地址 0x0 的值 | 在 idle_bus() 前采样，或直接检查寄存器输出引脚 |

### Skill 改进

| 文件 | 改动 |
|------|------|
| `references/verification/golden-reference-guide.md` | 策略 C/E/F 新增 "Known pitfall" 段落 + 2 条 Common mistakes |
| `references/verification/tb-examples.md` | 模板 9b 新增 stale output 警告，模板 9d 重写为 pre-edge + grant-time-only 检查 |
| `references/debug/bug-pattern-library.md` | V1 pattern 已包含 golden reference 检测方法 |

### 关键结论

**Golden reference 方法论验证有效：** 三个项目全部通过，且开发过程中 golden reference 检查器本身帮助发现了 3 个真实的 testbench 设计问题（竞态条件、stale output、registered output 语义）。这证明 golden reference 不仅能检测 RTL bug，其实施过程本身也能暴露验证环境的缺陷。

**策略复杂度排序已验证：** C（写回读）最简单，9/9 一次通过；F（延迟检查）中等，需要 careful block ordering；E（不变量检查）最复杂，需要理解 registered vs combinational 语义。

### 第二轮验证（策略 A/B/D，全策略覆盖）

| 项目 | 策略 | 原有测试 | Golden Reference | 发现 |
|------|------|---------|-----------------|------|
| test-fuzzy-spec | A: 已知 I/O 对 | 10/10 PASS | 1/1 PASS | IEEE 802.3 check value 匹配 |
| test-fuzzy-spec | B: 参考模型 | 10/10 PASS | 1/1 PASS | SW CRC = 0x53ac1f7e = DUT CRC |
| test-fuzzy-spec | P18 回归 | 10/10 PASS | 1/1 PASS | 单 beat CRC = 0x2144df1c，无 P18 bug |
| **test-cdc-capture** | **D: 数据完整性** | **5/5 PASS** | **2/2 FAIL** | **packer sample 1 = 0x000，应为 0x001** |

### 关键发现：golden reference 检出真实 RTL bug

cdc_capture 项目：原有 5 个测试全部 PASS（包括数据完整性对比），但 golden reference 记分板通过独立监控 FIFO 写入端口（`dut.u_fifo.wr_do`）发现 ADC packer 写入的第二个 sample 是 `0x000` 而不是 `0x001`。

根因分析：packer 使用移位寄存器 `{pack_buf_q[179:0], adc_data_i}`，但第二个 sample 在 packer 还未准备好时被写入，导致数据丢失。原有测试的 `expected_word` 函数和 DUT 使用了相同的移位逻辑，所以两者"一致"地错误——golden reference 的独立参考路径才是关键。

### 全策略验证完成

| 策略 | 项目 | 结果 | 真实 bug 检出 |
|------|------|------|-------------|
| A: 已知 I/O 对 | CRC packet processor | PASS | — |
| B: 软件参考模型 | CRC packet processor | PASS | — |
| C: 写回读记分板 | APB register block | PASS | — |
| D: 数据完整性 | CDC capture | **FAIL** | **packer 数据丢失** |
| E: 不变量检查 | RR arbiter | PASS | — |
| F: 延迟检查器 | Pipeline register | PASS | — |

**结论：6 种策略全部验证通过。策略 D 检出了唯一的真实 RTL bug，证明数据完整性记分板是最有效的 golden reference 策略。**

### 第三轮验证（AXI/DMA 协议场景）

| 项目 | 策略 | 原有测试 | Golden Reference | AXI 特有检查 |
|------|------|---------|-----------------|-------------|
| axi_lite_regs | C: 写回读 | 1/1 PASS | **37/37 PASS** | AW/W/B 握手、WSTRB、SLVERR |
| axi_write_tracker | E: 不变量 | 1/1 PASS | **5/5 PASS** | outstanding 计数、WVALID 稳定性 |
| dma_burst_planner | C: 写回读(适配) | 1/1 PASS | **285/285 PASS** | burst 拆分、地址对齐、错误路径 |
| **DMA 数据通路** | **D: 端到端** | — | **16/16 PASS** | 源→DMA→目标 数据完整性 |

### 关键发现

1. **Strategy C 在 AXI-Lite 上的适配**：agent 正确处理了 AXI-Lite 的 AW→W→B 和 AR→R 握手序列，在 RVALID&RREADY 握手期间采样 RDATA（不是之后），37 个检查覆盖 full write、byte-strobe partial write、walking-ones、SLVERR。

2. **Strategy E 在 AXI tracker 上的适配**：agent 用 pre-edge 采样避免了 AXI 信号竞态，INV4（WVALID 稳定性）只在 `pre_wvalid && !pre_wready` 时检查，避免了误报。

3. **Strategy C 在 DMA burst planner 上的创造性适配**：burst planner 不是寄存器映射模块，agent 将描述符输入视为"写"，将命令输出视为"回读"，独立计算期望值。285 个检查覆盖 single-beat、multi-burst split、walking-ones、zero-length、misalignment 等场景。

4. **DMA 端到端数据通路验证**：构建了最小 DMA 系统（simple_mem + dma_engine + dma_top），16 个已知数据从源地址搬到目标地址，0 mismatch。验证过程中发现并修复了 `done_q` 双驱动 bug（combinational 和 sequential 块同时赋值）。

### 全策略+全场景验证完成

| 策略 | 简单模块 | AXI 协议 | DMA 数据通路 |
|------|---------|---------|-------------|
| A: 已知 I/O | CRC ✅ | — | — |
| B: 参考模型 | CRC ✅ | — | — |
| C: 写回读 | APB ✅ | AXI-Lite ✅, DMA planner ✅ | — |
| D: 数据完整性 | CDC ✅ (bug) | — | DMA ✅ |
| E: 不变量 | Arbiter ✅ | AXI tracker ✅ | — |
| F: 延迟检查 | Pipeline ✅ | — | — |

---

## 2026-05-28 — 工程直觉自动化（checklist + 脚本 + Yosys 集成）

### 问题背景

Skill 的工程直觉能力是"初级偏上"——有 `design-heuristics.md` 和 `power-timing-area.md` 作为参考，但这些是被动文档，agent 在生成 RTL 和自审时不会主动应用。需要将工程直觉转化为可执行的检查规则。

### 新增文件

| 文件 | 行数 | 用途 |
|------|------|------|
| `references/design/engineering-intuition-checklist.md` | ~150 | 5 类检查（A-E），每项有阈值、权威来源、修复建议 |
| `scripts/rtl_complexity_check.py` | ~250 | 自动化复杂度检查 + Yosys 集成 |

### 检查体系

| 类别 | 检查项 | 阈值 | 权威来源 |
|------|--------|------|---------|
| A: 代码复杂度 | always 块行数、嵌套深度、模块大小、扇出 | 50行/3层/300行/50ref | RMM §7.2-7.4 |
| B: 组合深度 | 路径级数、宽比较器、优先级链 | 7级/32bit/8级 | Synopsys DC, UG901 |
| C: 面积红旗 | 寄存器数组、重复实例、硬编码常量 | 64 entries/4 instances | RMM §6.2, UG901 |
| D: 时序红旗 | 跨模块路径、高扇出、异步复位 | 50 fanout | Cummings SNUG, UG949 |
| E: 可复用性 | 固定宽度、硬编码地址、协议耦合 | — | RMM §3.3-4.2 |

### SKILL.md 改动

Step 8 自审清单新增 "Engineering intuition" 段落（7 项检查），引用 `engineering-intuition-checklist.md` 和 `rtl_complexity_check.py`。

### SKILL.md 行数

380 / 500 行

### 脚本验证

在 `vfs_sw_hw_axi_handlers_trial` 上测试通过：
- 检测到 54 行的 `always @(*)` 块（超过 50 行阈值）
- 正确报告 C1 WARNING 级别
- 输出格式：`[C1] filename:line: message + fix`

---

## 2026-05-27 — 端到端能力验证（H1 bug 注入→debug→修复→综合）

### 验证方案

注入 H1 bug（payload 在 stall 时变化）到 pipeline_reg.v，让 agent 用 skill 新能力端到端 debug。

### 验证结果

| 阶段 | 能力 | 结果 | 证据 |
|------|------|------|------|
| 仿真失败 | simulation-loop.md | ✅ | `H1_VIOLATION at cycle 13` |
| VCD 信号提取 | vcd_extract.py | ✅ | 找到 m_data_o 在 t=125000 变化 |
| VCD 违规检测 | --find-violation stall-data-change | ✅ | 新增 H1 检测器 |
| Bug Pattern 匹配 | bug-pattern-library H1 | ✅ | 正确代码模式直接可用 |
| RTL 修复 | accept_input 模式 | ✅ | 38 行修复后代码 |
| 重跑仿真 | ALL_TESTS_PASS | ✅ | 3/3 PASS |
| Yosys 综合 | yosys_extract.py | ✅ | 0 latch, 36 cells, 5 门临界路径 |

### 发现并修复的 Gap

| Gap | 说明 | 修复 |
|-----|------|------|
| vcd_extract.py 无 H1 检测 | `--find-violation valid-drop` 只能找 valid 下降，不能找 stall 时 data 变化 | 新增 `--find-violation stall-data-change` |
| testbench check 时序 | test_2 的 check 在 violation 计数之前执行 | 记录为 testbench 已知问题 |

### 关键结论

**Skill 新增能力全部验证有效：**
- VCD 分析：agent 成功用脚本从波形中定位了 H1 违规的确切时间戳和信号值
- Bug Pattern：H1 的正确代码模式被 agent 直接引用修复
- Yosys 综合：agent 成功运行综合确认无 latch/loop
- 端到端流程：仿真→VCD→修复→再仿真→综合 全部跑通

---

## 2026-05-27 — Yosys 综合反馈闭环（仿真→综合→修复→再仿真）

### 新增文件

| 文件 | 行数 | 用途 |
|------|------|------|
| `references/verification/synthesis-feedback-guide.md` | ~200 | 综合报告解读、问题映射、工作流 |
| `scripts/yosys_extract.py` | ~200 | 自动化综合报告提取（cell count/latch/loop/ltp）|

### 综合反馈工作流

```
仿真通过 (Step 9) → yosys 综合 → 提取报告 → 修复问题 → 再仿真确认
```

**yosys 可检测的问题：**

| 检查项 | yosys 输出 | RTL 问题 | Bug Pattern |
|--------|-----------|---------|-------------|
| Latch 推断 | `$_DLATCH_*` in cells | 组合块缺 default | E2 |
| 组合环路 | `Detected loop` in ltp | 组合反馈 | E7 |
| 临界路径 | ltp length > 25 | 组合深度过大 | — |
| 未使用信号 | warning: unused | 死代码 | E8 |
| 多驱动 | check: multi-driven | 信号多源驱动 | E1 |

### SKILL.md 改动

Step 9（仿真循环）新增"综合反馈"子节：
- 仿真通过后运行 yosys
- 检查 latch/loop/critical path/cell count
- 修复后重跑仿真确认功能不变

### 脚本验证

`yosys_extract.py` 在 rr_arbiter_trial 上测试通过：
- 正确提取 cell counts（104 cells: 31 AND, 22 NOR, 12 SDFFE...）
- 正确检测 ltp（length=22, 临界路径 22 门）
- 正确报告 check（0 problems）
- 注意：ltp 的 "loop" 警告有误报（寄存器反馈路径被误判为组合环路）

---

## 2026-05-27 — VCD 波形分析能力（仿真闭环最后一块拼图）

### 新增文件

| 文件 | 行数 | 用途 |
|------|------|------|
| `references/verification/vcd-analysis-guide.md` | ~200 | VCD 格式解释、信号提取、协议重建、第一分叉周期定位 |
| `scripts/vcd_extract.py` | ~280 | VCD 解析脚本：信号提取、转换检测、违规查找、AXI 协议重建 |

### VCD 脚本功能

```bash
# 列出所有信号
python scripts/vcd_extract.py dump.vcd --list-signals

# 提取特定信号时间线
python scripts/vcd_extract.py dump.vcd --signals WVALID,WLAST,WDATA --range 0:50000

# 查找信号转换
python scripts/vcd_extract.py dump.vcd --transitions WVALID

# 重建 AXI 写通道序列
python scripts/vcd_extract.py dump.vcd --protocol axi-write

# 查找 valid-drop 协议违规
python scripts/vcd_extract.py dump.vcd --find-violation valid-drop --signals valid,ready
```

### Bug Pattern 更新（6 个 pattern 新增 VCD 检测方法）

| Pattern | VCD 检测方法 |
|---------|-------------|
| H1 (payload stall) | 提取 valid/ready/data，找 valid=1,ready=0 时 data 变化 |
| H8 (valid gated) | find-violation valid-drop + 检查 can_send 信号 |
| P4 (completion timing) | 提取 wlast/bvalid/done，检查 done 是否在 bvalid 之前 |
| P11 (B response hold) | find-violation valid-drop --signals bvalid,bready |
| P12 (WVALID mid-burst) | 提取 wvalid 转换，检查 wlast 是否为 0 |
| P13 (AW/W/B coupling) | protocol axi-write，检查 AW 是否被 B 阻塞 |

### Skill 改进

| 文件 | 改动 |
|------|------|
| `references/verification/vcd-analysis-guide.md` | 新建：VCD 格式、信号提取、协议重建、debug 场景 |
| `scripts/vcd_extract.py` | 新建：VCD 解析工具（list-signals, transitions, protocol, violation）|
| `references/debug/bug-pattern-library.md` | 6 个 pattern 新增 VCD detection 段落 |
| `references/verification/simulation-loop.md` | Step 3 引用 vcd-analysis-guide.md 和 vcd_extract.py |

### 关键意义

**波形分析能力 = 仿真闭环的最后一块拼图。** 之前 agent 只能看文本输出的 PASS/FAIL，无法定位"为什么失败"。现在 agent 可以：
1. 从 VCD 提取信号时间线
2. 重建 AXI/APB 协议序列
3. 自动检测协议违规（valid-drop, mid-burst gap）
4. 定位第一分叉周期

这使得 debug 从"看 $display 输出猜原因"升级为"从波形中精确定位违规周期"。

---

## 2026-05-27 — Simulation Loop 端到端验证（首次真实执行）

**项目**: rr_arbiter_trial（round-robin arbiter, 130 行 RTL + 491 行 TB）
**方式**: 子 agent 严格按 simulation-loop.md 5 阶段执行
**结果**: 功能仿真 PASS，发现 6 个 simulation-loop.md 缺陷

### 执行结果

| 阶段 | 工具 | 结果 | 发现 |
|------|------|------|------|
| Phase 1 Lint | yosys check -assert | PASS | yosys 可替代 verilator，但覆盖更弱 |
| Phase 2 Compile | iverilog -g2012 | PASS | 零警告零错误 |
| Phase 3 Simulate | vvp | PASS | 功能正确，2986ps |
| Phase 3.5 协议分析 | — | **GAP** | 6 个标准标记全部缺失 |
| Phase 4/5 | — | SKIPPED | 无失败无超时 |

### 发现的 Skill 缺陷 (6 个)

| ID | 缺陷 | 根因 | 影响 |
|----|------|------|------|
| GAP-S1 | 无 yosys lint 替代方案 | simulation-loop.md 只写了 verilator | verilator 不可用时 agent 无法 lint |
| GAP-S2 | 无 PATH 环境配置指导 | yosys oss-cad-suite 需要 environment.bat | yosys 启动失败（DLL_NOT_FOUND）|
| GAP-S3 | 无路径编码警告 | 中文路径可能导致工具失败 | 文件找不到或编码错误 |
| GAP-S4 | 结果分类表有重叠 | COMPILE_ONLY vs FATAL 判定冲突 | 通过的仿真被误判为 FATAL |
| GAP-S5 | 无非标 testbench 回退解析 | 假设所有 TB 遵循协议 | 现有 23 个 trial 全部不合规 |
| GAP-S6 | 无 immediate-$finish 处理 | fail task 直接 $finish 阻止后续测试 | SIMULATION_DONE 永远不出现 |

### Skill 改进

| 文件 | 改动 |
|------|------|
| `references/verification/simulation-loop.md` | Prerequisites: 新增 yosys 环境配置、路径编码警告 |
| `references/verification/simulation-loop.md` | Phase 1: 新增 yosys fallback（含覆盖对比表）|
| `references/verification/simulation-loop.md` | Phase 3: 结果分类改为优先级排序 + 非标 TB 回退解析 |
| `references/verification/simulation-loop.md` | Checklist: 更新为 verilator/yosys 双路径 |

### 关键发现

**simulation-loop.md 首次端到端验证**: 子 agent 能完整执行 5 阶段流程，但遇到两个实际障碍：
1. yosys 需要手动配置 PATH（文档未说明）
2. 现有 testbench 无一遵循输出协议（文档假设全部合规）

**回退解析策略验证**: 对 rr_arbiter_trial 的输出 `"PASS round robin arbiter"` + `$finish`，回退逻辑正确分类为 PASS（non-compliant）。这证明回退策略对现有 trial 有效。

---

## 2026-05-24 — SPI Master（复杂 FSM）+ Yosys 综合验证

### SPI Master

**项目**: APB SPI Master（6 状态 FSM, CPOL/CPHA, 可配置位宽/分频）
**结果**: 5/5 测试通过，335 行，复杂 FSM 验证成功

### Yosys 综合验证（首次真实综合）

安装 Yosys 0.45，对 4 个项目运行综合：

| 项目 | 综合结果 | 发现 |
|------|---------|------|
| SPI Master | 0 问题, 496 cells | 清洁综合 |
| Arbiter | **1 latch 推断** | `mask_update.j` 循环变量产生 latch |
| Timer | 0 问题, 445 cells | 清洁综合 |
| Clock Gate | 待检查 | — |

**关键发现**: 仲裁器的循环变量 `j` 在组合 always 块中被 Yosys 推断为 latch。这是综合感知的真实 gap — 仿真正确但综合有问题。

### Skill 改进

无文件改动。Yosys 已安装可用（`D:\cadence\Cadence\SPB_Data\oss-cad\oss-cad-suite\bin\yosys.exe`），后续项目可直接运行综合验证。

---

## 2026-05-24 — Clock Gating Controller（低功耗设计验证）

**项目**: APB 时钟门控控制器（4 域、自动空闲检测、手动覆盖、P1 规则验证）
**结果**: 8/8 测试通过，0 个设计缺陷，低功耗设计模式验证成功

### 关键发现

- **P1 规则验证**: gate_en_o 输出用于下游 ICG clock-enable 模式，clk_gated_o 仅用于监控
- **自动门控**: 空闲计数器 ≥ 阈值时自动门控，activity 恢复时自动解门控
- **手动覆盖**: manual_override_en + manual_gate 强制门控，优先于 activity
- **子代理质量**: 首次零设计缺陷通过（205 行，自审 PASS，功能测试 PASS）

### Skill 改进

无文件改动。P1 规则（clock-enable over gating）已验证有效。

---

## 2026-05-24 — P0+P1: 功能测试规则 + 综合感知仲裁器

### P0: 功能测试不可替代规则

**改动**: SKILL.md Step 8b 新增 "Functional verification (mandatory)" 独立步骤。

**内容**:
- 明确声明结构审查 ≠ 功能正确
- 要求 golden reference、协议合规、边界条件、确定性测试
- 引用 CRC P18 和 Crossbar 项目作为反面案例

### P1: 参数化仲裁器（综合感知验证）

**项目**: 8 请求者 round-robin + 固定优先级仲裁器
**结果**: 6/6 测试通过，发现 1 个设计 bug

**设计 bug**: round-robin mask 授予 req[0] 后变为 0xFE，屏蔽了唯一的活跃请求，仲裁器空转。修复：当 masked_req==0 时重置 mask 为全 1。

**综合感知模式验证**:
- casez 优先级编码器（A1: 平衡解码树）
- $clog2 用于 ID 宽度（A3: 位宽纪律）
- clock-enable 模式（P1: 无手动 clock gating）
- 资源共享：编码器在两种模式间共享

### Skill 改进

| 文件 | 改动 |
|------|------|
| `SKILL.md` Step 8b | 新增功能验证独立步骤（mandatory） |

---

## 2026-05-24 — AXI-Lite Crossbar（参数化多模块）项目迭代

**项目**: 2×3 AXI-Lite 交叉开关（地址路由 + 固定优先级仲裁 + 错误响应）
**方式**: 子代理生成 + 编译 + 仿真
**结果**: 编译通过，4/4 功能测试失败，发现 2 个 skill 缺陷

### 发现的 Skill 缺陷 (2 个)

| ID | 缺陷 | 根因 | 影响 |
|----|------|------|------|
| GAP-X1 | 自审 PASS 但功能全失败 | 结构检查不覆盖功能正确性（与 CRC P18 同类问题） | 交叉开关未路由任何请求 |
| GAP-X2 | APB 组合输出测试规则已添加 | 方向 1 完成 — 写入 apb-guidelines.md 和 SKILL.md | 解决 3 次重复出现的问题 |

### Skill 改进

| 文件 | 改动 |
|------|------|
| `references/bus/apb-guidelines.md` | 添加 "Combinational output test timing" 规则（含正确/错误模式） |
| `SKILL.md` Step 9 | 添加组合输出测试时序警告 |

### 教训

- **自审清单的根本局限再次验证**: 子代理声称 PASS，但交叉开关完全不工作。与 CRC 项目的 P18 发现一致 — 结构检查无法替代功能测试。
- **复杂参数化设计的子代理质量**: 491 行的交叉开关，自审通过，但路由逻辑有 bug。参数化 + generate 块的组合逻辑比简单模块更容易出错。

---

## 2026-05-24 — UART 控制器（多模块集成验证）项目迭代

**项目**: UART 控制器（uart_regs + uart_tx + uart_rx + uart_baudgen + uart_top）
**方式**: 4 个子代理并行生成 + 接口合约强制 + 集成编译 + 仿真
**结果**: 6/6 测试通过，零编译错误，发现 1 个 skill 缺陷

### 关键成果

**接口合约模式验证成功**: 写了 interface_contract.md 明确定义端口宽度和信号语义，4 个子代理全部遵循，零编译错误。对比昨天 DMA 子系统的 4 个编译错误，接口合约显著提升了多模块集成质量。

### 发现的 Skill 缺陷 (1 个)

| ID | 缺陷 | 根因 | 影响 |
|----|------|------|------|
| GAP-U1 | APB 组合输出测试时序（第三次出现） | skill testbench 指导无"检查组合输出"规则 | PSLVERR 在事务结束后检查 |

### 子代理自审质量

| 模块 | 自审结果 | 发现 |
|------|---------|------|
| uart_regs | PASS | 自审中发现 irq_o 使用了错误控制位并修复 |
| uart_tx | PASS | 无额外发现 |
| uart_rx | PASS | 识别 rxd_i 无同步器为残余风险 |
| uart_baudgen | PASS | 无额外发现 |

### Skill 改进

无文件改动。接口合约模式已验证有效，可作为多模块项目的标准模式。

---

## 2026-05-23 — DMA 子系统（多模块集成）项目迭代

**项目**: DMA 子系统（dma_regs + dma_rd_engine + dma_wr_engine + dma_fifo + dma_top）
**方式**: 4 个子代理并行生成 + 集成编译 + 仿真
**结果**: 编译通过，功能仿真部分通过（寄存器读写 PASS，DMA 传输未完成），发现 4 个 skill 缺陷

### 发现的 Skill 缺陷 (4 个)

| ID | 缺陷 | 根因 | 影响 |
|----|------|------|------|
| GAP-D1 | 子代理参数不一致 | dma_wr_engine 无参数，dma_top 期望参数 — 接口合约未强制 | 编译错误需手动修复 |
| GAP-D2 | 多模块集成无指导 | skill 无"如何写 AXI slave model testbench"pattern | 测试台无法验证 DMA 传输 |
| GAP-D3 | 子代理间接口未验证 | 4 个子代理独立生成，端口/参数不匹配 | 需要人工协调接口 |
| GAP-D4 | SVA 不可用 | iverilog 不支持 SVA，子代理生成的断言需删除 | 编译错误 |

### Skill 改进

无文件改动。需要新增"多模块集成测试"模式。

### 教训

- **接口合约是多模块项目的关键**：子代理各自遵循 SKILL.md，但接口合约（参数名、端口宽度）没有强制执行机制
- **AXI slave model testbench 是必需的**：DMA 类项目需要模拟 AXI slave 响应，skill 没有这个 pattern
- **SVA 兼容性**：iverilog 不支持 SVA，子代理应使用 `$display`/`$fatal` 而非 `assert property`

---

## 2026-05-23 — AHB-Lite Slave + 仿真循环验证 项目迭代

**项目**: AHB-Lite Slave（可配置寄存器文件 + wait state + FSM + 错误响应）
**方式**: 子代理生成 RTL + simulation-loop.md 端到端验证（lint→compile→sim→fix）
**结果**: 11/11 测试通过，9 次迭代修复，发现 3 个 skill 缺陷

### 发现的 Skill 缺陷 (3 个)

| ID | 缺陷 | 根因 | 影响 |
|----|------|------|------|
| GAP-A1 | AHB 读数据时序未定义 | guidelines 无 "combinational vs registered read data" 规则 | hrdata 在 hready=0 时有效，不符合 AHB-Lite |
| GAP-A2 | FSM 控制信号遗漏 | 自审未检查所有 FSM 输出是否在所有状态赋值 | update_ctrl 未赋值，CTRL 寄存器写入失败 |
| GAP-A3 | 测试台 AHB 时序 | 无"测试台 AHB 信号赋值时序"指导 | htrans 覆盖、hready 采样时机错误 |

### Skill 改进

| 文件 | 改动 |
|------|------|
| `references/bus/ahb-lite-guidelines.md` | 添加 "Read data timing" 规则：combinational from current address, valid when hready=1 |
| `SKILL_CHANGELOG.md` | 追加 AHB-Lite 项目条目 |

### 仿真循环端到端验证

**simulation-loop.md 首次完整验证**: 9 次迭代
- Phase 1 (Lint): verilator 不可用，跳过
- Phase 2 (Compile): iverilog 成功
- Phase 3 (Simulate): vvp 运行，输出协议 TEST_START/PASS/FAIL
- Phase 4 (Failure Analysis): 9 次分析→修复→重跑
- Phase 5 (Hang Detection): 未触发

**结论**: simulation-loop.md 框架可用，但 verilator lint 阶段无法验证。

---

## 2026-05-23 — Async FIFO with CDC 项目迭代

**项目**: 参数化异步 FIFO（gray code 指针 + 2FF 同步器 + ASYNC_REG + reset sync）
**方式**: 子代理生成 RTL + 独立 review + iverilog 仿真（不相关时钟 100MHz/143MHz）
**结果**: 10/10 测试通过，零设计缺陷

### 关键发现

**CDC guidelines 已经足够可靠**: 子代理首次生成的代码就通过了全部测试（包括 wrap-around 数据完整性、simultaneous wr/rd、count 准确性）。这验证了 `references/synthesis/cdc-guidelines.md` 的质量。

### 发现的 Skill 缺陷 (2 个)

| ID | 缺陷 | 根因 | 影响 |
|----|------|------|------|
| GAP-A1 | 仿真循环框架未使用 | 手动跑 compile→sim→check，simulation-loop.md 未被调用 | 框架仍是死文档 |
| GAP-A2 | CDC 测试覆盖不足 | 测试台只有基本功能测试，无随机时钟、metastability 注入、长时间压力测试 | CDC 正确性未充分验证 |

### Skill 改进

无文件改动。CDC guidelines 质量已验证。

### 教训

- skill 的 CDC pattern 文档质量足够高，子代理能正确遵循
- 真正的 CDC 验证需要：随机时钟频率/相位、metastability 注入、长时间压力测试、ASYNC_REG 综合验证
- 这些超出了 iverilog 的能力，需要专业 CDC 工具（Synopsys VC CDC, Cadence Conformal CDC）

---

## 2026-05-23 — CRC AXI-Stream Generator 项目迭代

**项目**: 参数化 CRC 生成器 + AXI-Stream 接口（CRC-32, LFSR, tkeep masking）
**方式**: 子代理生成 RTL + 独立 review + iverilog 仿真
**结果**: 7/7 测试通过，发现 3 个 skill 缺陷

### 发现的 Skill 缺陷 (3 个)

| ID | 缺陷 | 根因 | 影响 |
|----|------|------|------|
| GAP-C1 | 组合输出读取旧寄存器值（管道延迟） | skill 无 "combinational output reads stale registered value" pattern | 单 beat CRC 全为 0 |
| GAP-C2 | 子代理自审不验证功能正确性 | 自审清单只检查结构，不检查输出值 | 设计功能完全错误但自审 PASS |
| GAP-C3 | 测试台管道延迟 | 无"管道延迟"测试指导 | 测试在输出出现前检查 |

### Skill 改进

| 文件 | 改动 | 权威来源 |
|------|------|---------|
| `bug-pattern-library.md` | 新增 P14 (counter+trigger race) | Wakerly "Digital Design" §7.3 + IEEE 1364 §5.4 |
| `bug-pattern-library.md` | 新增 P15 (dedicated clear) | ARM Cortex-M NVIC, RISC-V CLINT 寄存器设计 |
| `bug-pattern-library.md` | 新增 P16 (status release) | ARM GIC ICPENDR/ICACTIVER 寄存器设计 |
| `bug-pattern-library.md` | 新增 P17 (capture vs clear) | ARM GIC Arch Spec §3.3, RISC-V PLIC §6 |
| `bug-pattern-library.md` | 新增 P18 (pipeline latency) | IEEE 1364-2005 §5.4.4 (NBA scheduling) |
| `bug-pattern-library.md` | 新增 Sources 表 + Self-review limitation rule | — |
| `SKILL.md` Step 8 | 添加功能验证警告 | 验证方法论基本原则 |

### 核心发现

**P18 是最有价值的发现**: 子代理生成的 CRC 设计在结构上完全正确（通过所有 66 个自审检查项），但功能完全错误（单 beat CRC 输出为 0）。根因是组合输出在同一周期读取还未更新的寄存器值。这暴露了 skill 自审清单的根本局限：**结构正确 ≠ 功能正确**。

### 权威性审计

本轮所有 pattern 改动均添加了权威来源引用：
- P18 直接来自 IEEE 1364-2005 §5.4.4 的非阻塞赋值语义
- P14-P17 虽然发现于项目，但其理论根基来自同步设计教科书和 ARM/RISC-V 中断架构规范
- bug-pattern-library.md 新增 Sources 表，列出所有引用的权威文档

---

## 2026-05-23 — Interrupt Controller 项目迭代

**项目**: APB 中断控制器（N 源、优先级编码、mask/enable/status、边沿/电平检测、EOI）
**方式**: 子代理生成 RTL + 独立 review + iverilog 仿真
**结果**: 12/12 测试通过，发现 3 个 skill 缺陷

### 发现的 Skill 缺陷 (3 个)

| ID | 缺陷 | 根因 | 影响 |
|----|------|------|------|
| GAP-I1 | PSLVERR 只检查读不检查写 | APB checklist "PSLVERR on invalid address" 没明确"读写都要" | 子代理只实现 read PSLVERR |
| GAP-I2 | 测试台检查组合输出时序错误 | skill 无"APB 事务期间检查组合信号"的时序指导 | pslverr 在事务结束后检查，永远=0 |
| GAP-I3 | 参数化寄存器宽度 vs 总线宽度 | 4bit×16源=64bit，APB 总线只有 32bit | 高优先级源不可配置 |

### Skill 改进

| 文件 | 改动 |
|------|------|
| `references/bus/apb-guidelines.md` | PSLVERR 检查项改为 "asserted on BOTH invalid read AND invalid write addresses" |

### 子代理自审质量评估

子代理声称全部 PASS，但独立 review 发现：
- PSLVERR 只检查 reads（apb_read & ~addr_valid），遗漏了 writes
- 子代理的自审清单说 "PSLVERR on invalid address (line 68)" 并标记 PASS，但没有验证 writes 也覆盖

**结论**: 子代理的自审有"确认偏误" — 看到 PSLVERR 存在就标记 PASS，没有验证其完整性。

---

## 2026-05-23 — Timer Subsystem 项目迭代

**项目**: APB 可配置定时器子系统（count-down + watchdog + PWM + IRQ + DMA trigger + clock gating）
**方式**: 使用 skill 12 步工作流，contract-first，iverilog 仿真验证
**结果**: 3 RTL 模块 + 1 testbench，16/16 测试通过

### 发现的 Skill 缺陷 (5 个)

| ID | 缺陷 | 根因 | 影响 |
|----|------|------|------|
| GAP-T1 | DMA trigger + auto-reload 在 count=0 竞争 | skill 无 "count-down with event trigger + auto-reload" pattern | trigger 永远不触发 |
| GAP-T2 | dedicated clear register 不直接清除 status bit | skill 无 "dedicated clear vs W1C" 优先级规则 | INT_CLEAR 无效 |
| GAP-T3 | core output 1→0 不释放 status register | skill 只有 capture（0→1）没有 release（1→0）pattern | WDT feed 后 status 仍锁定 |
| GAP-T4 | 测试台 APB 写入时序 + counter load 条件 | skill testbench 指导无 APB 时序 + 使能条件说明 | 测试序列设计错误 |
| GAP-T5 | capture vs clear 竞争条件 | skill 无 "先关源头再清状态" 设计规则 | clear 后立刻被重新 capture |

### Skill 改进 (3 个文件)

| 文件 | 改动 |
|------|------|
| `references/debug/bug-pattern-library.md` | 新增 P14 (counter+trigger race), P15 (dedicated clear), P16 (status release), P17 (capture vs clear) |
| `SKILL.md` Step 8 自审清单 | 新增 "Counter/timer" 和 "Status registers" 检查项 |
| `SKILL.md` | 保持 324 行（≤500 限制） |

### 新增 Pattern 详情

**P14: Auto-reload and event trigger race at count=0** (counter 类)
- 现象: DMA trigger 永远不触发
- 根因: auto-reload 在同一时钟沿恢复 count，trigger 条件不满足
- 修复: `dma_fired_q` 标志 + count hold until handshake
- 预防: SVA assertion 检查 trigger 在 count=0 后 1 周期内断言

**P15: Dedicated clear register does not directly clear status bit** (register 类)
- 现象: INT_CLEAR 写入后 STATUS 位不变
- 根因: 间接清除路径（core → irq_o → irq_i）不可靠
- 修复: `int_clear_fire` 直接清除 `irq_status_q`

**P16: Core output deassert does not release status register** (register 类)
- 现象: WDT feed 后 wdt_timeout status 位不变
- 根因: 只实现 capture（0→1），未实现 release（1→0）
- 修复: 检测 `wdt_timeout_i` 下降沿，自动清除 `wdt_timeout_q`

**P17: Status capture re-sets immediately after clear** (register 类)
- 现象: clear 后 status 立刻被重新置位
- 根因: capture 和 clear 在同一 always 块，capture 条件仍为真
- 修复: "先关源头再清状态"原则

---

## 2026-05-23 — 一天 7 个项目批量迭代

**项目**: CDMA Round 6, AXI-Lite APB Bridge, Async FIFO, Arbiter, AXI-Stream, DMA Subsystem, Single-Agent CDMA
**结果**: 28 个缺陷修复，11 个文件改动

### 发现的 Skill 缺陷

| 项目 | 缺陷数 | 关键发现 |
|------|--------|---------|
| CDMA Round 6 | 3 | FIFO registered output data shift (F1), WVALID P12 violation, insufficient FIFO data check |
| AXI-Lite APB | 5 | SM1 state_d exemption, registered output sampling (F2), APB checklist, self-review rigor, bridge patterns |
| Async FIFO+Arbiter+AXI-Stream | 8 | CDC naming (_2q), ASYNC_REG, reset synchronizer, SM1 scope, AXI-Stream checklist, ready tradeoff |
| DMA Subsystem | 4 | inter-module handshake, port width derivation, byte-to-beats conversion, Step 12 prompt template |
| Single-Agent CDMA | 3 | completion FIFO pattern, generate-block dual-mode FIFO, wire forward reference |

### Skill 改进

| 文件 | 改动 |
|------|------|
| `SKILL.md` | FWFT 引用、APB/AXI-Stream/CDC 清单、自审严格性、Step 12 prompt、SM1 澄清 |
| `fifo-examples.md` | FWFT 标准模式、registered 输出时序分析、generate 块双模式 |
| `axi-dma-channel-guidelines.md` | WVALID/FIFO burst-ready gate、completion FIFO 模式 |
| `bug-pattern-library.md` | F1 (FIFO data shift), F2 (registered output race), SM1 scope clarification |
| `timing-contract-template.md` | DMA FIFO pipeline、burst timing、completion signal style、registered output sampling |
| `naming-guidelines.md` | CDC 命名 (_2q)、复位命名 (_ni)、参数验证模式 |
| `cdc-guidelines.md` | ASYNC_REG 属性、复位同步器电路 |
| `apb-guidelines.md` | APB master 规则、自审清单 |
| `axi-stream-guidelines.md` | AXI-Stream 自审清单、combinational vs registered ready |
| `coding-guidelines.md` | wire 前向引用规则 |
| `interface-contract-template.md` | 模块间握手规则、端口宽度推导、字节→beats 转换清单 |

---

## 2026-05-19~22 — CDMA 项目 6 轮迭代

**项目**: AXI Central DMA (CDMA)
**方式**: 用 skill 生成 CDMA RTL → 人工 review → 发现 skill gap → 迭代 skill → 重新生成

### 轮次摘要

| 轮次 | 关键发现 | Skill 改进 |
|------|---------|-----------|
| Round 1 | 8 个偏差: 单进程 FSM、push/pop 命名、缺时序合同、未读 reference | reference 读取门控、命名规范、bug pattern 扫描前置 |
| Round 2 | 通道分离修复了，但 burst 流控和 completion tracker 仍有 gap | 规则需要更细粒度 |
| Round 3 | `_d` 后缀漏洞 + shadow datapath 反模式 + 子代理不加载 skill | SM1/SM2 bug pattern、Step 12 子代理委托规则 |
| Round 4 | 所有 skill 约束通过! 暴露 3 个规则 gap: WVALID mid-burst、死端口、FIFO 深度 | P12 + AXI A3.3 硬规则 |
| Round 5 | AW/W/B FSM 耦合第 5 次出现、WSTRB last_offset==0 bug、4KB 边界公式错误 | 写引擎模块模板、P13 |
| Round 6 | 3 个关键数据通路 bug (FIFO 寄存器输出、WVALID P12、FIFO 数据检查不足) | FWFT 标准、burst-ready gate、F1 pattern |

### 反复出现的核心问题

AW/W/B 通道耦合 — LLM 倾向用单 FSM 顺序管理写通道，而 AXI 协议要求独立管理。根因是 LLM 训练数据中的常见写法覆盖了 skill 规则。Round 5 通过添加完整写引擎模块模板彻底解决。

---

## Skill 当前状态 (2026-05-23 — 6 个项目迭代后)

### 今日项目迭代总览

| 项目 | 测试 | 缺陷 | 关键发现 |
|------|------|------|---------|
| Timer Subsystem | 16/16 PASS | 5 | DMA trigger 竞争, status register clear/sync |
| Interrupt Controller | 12/12 PASS | 3 | PSLVERR 范围, 组合输出测试时序 |
| CRC AXI-Stream | 7/7 PASS | 3 | P18 pipeline latency, 自审功能局限 |
| Async FIFO CDC | 10/10 PASS | 0 | CDC guidelines 质量已验证 |
| AHB-Lite Slave | 11/11 PASS | 3 | 读数据时序, 仿真循环验证 |
| DMA Subsystem | 1/2 PASS | 4 | 多模块集成, 接口合约, SVA 兼容性 |

### 覆盖的 Pattern 类别

| 类别 | Pattern 数量 | 来源 |
|------|-------------|------|
| Handshake (H) | H1-H8 | CDMA, APB, AXI-Stream |
| Protocol (P) | P1-P13 | CDMA, APB, AHB, AXI |
| Counter (P14) | 1 | Timer |
| Status Register (P15-P17) | 3 | Timer |
| Pipeline (P18) | 1 | CRC |
| State Machine (SM) | SM1-SM2 | CDMA |
| Data Path (DP) | DP1-DP5 | CDMA, DMA |
| FIFO (F) | F1-F2 | CDMA, APB Bridge |
| CDC (D) | D1-D2 | Async FIFO |

### 权威来源覆盖

| 来源 | 覆盖的 Pattern |
|------|---------------|
| IEEE 1364-2005 (Verilog) | P18, SM1, E1-E8 |
| IEEE 1800-2017 (SystemVerilog) | SVA assertions |
| AMBA AXI (IHI 0022E) | P4-P13, H8 |
| AMBA APB (IHI 0024) | APB checklist |
| AMBA AXI-Stream (IHI 0051) | AXI-Stream checklist |
| ARM GIC Architecture | P15, P17 |
| RISC-V PLIC/CLINT | P15, P17 |
| Wakerly "Digital Design" | P14 |
| Sunburst Design (Cummings) | P18, CDC patterns |
| 项目经验 (verified by sim) | P14-P17, Timer/INTC/CRC bugs |

### 自审清单检查项

| 检查类别 | 检查项数 |
|---------|---------|
| Handshake | 4 |
| Data path | 4 |
| Naming | 4 |
| RTL correctness | 8 |
| FSM | 6 |
| Protocol (AXI) | 11 |
| APB | 6 |
| AXI-Stream | 6 |
| CDC | 4 |
| Counter/timer | 3 |
| Status registers | 4 |
| Integration | 6 |
| **功能验证警告** | **1** ← NEW |

### SKILL.md 行数

326 / 500 行

### 已验证的领域

- ✅ AXI Full/Lite/Stream 协议
- ✅ APB 协议
- ✅ CDC (async FIFO, reset synchronizer)
- ✅ FSM (two-process, single-bit control)
- ✅ FIFO (sync, FWFT)
- ✅ 计数器/定时器
- ✅ 中断控制器
- ✅ CRC 生成器

### 待验证

- 仿真循环框架已写（simulation-loop.md, 373 行）但未用真实项目跑过
- 综合感知能力（synthesis-awareness）尚未开发
- 低功耗设计（clock gating）、DFT 尚未通过项目验证
