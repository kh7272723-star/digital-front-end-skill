# Skill Iteration Changelog

记录 digital-front-end-skill 的迭代历史：每次项目 review 发现的 skill 缺陷、改进措施、当前状态。

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
