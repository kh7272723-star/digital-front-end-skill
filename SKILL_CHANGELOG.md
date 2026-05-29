# Skill Iteration Changelog

记录 digital-front-end-skill 的迭代历史：每次项目 review 发现的 skill 缺陷、改进措施、当前状态。

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
