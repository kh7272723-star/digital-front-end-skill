# Skill 迭代日志

## 2026-06-05 - v2026.06.05 发布：证据绑定与存储门禁加固

### 发布摘要

本版本将 2026-06-04 NAND/DMA/NVMe 三项目复盘中形成的门禁加固正式整理为发布版本 `v2026.06.05`。目标是减少 agent 的“合规表演”：最终 PASS、protocol claim、verification matrix、delegation decision 必须绑定到真实工程证据，而不是只出现在开发日志或总结文字中。

### 主要能力

| 能力 | 位置 | 说明 |
|------|------|------|
| L1/L2 fail-closed 门禁 | `project_preflight_gate.py`, `project_artifact_gate.py`, `pre_integration_gate.py`, `final_delivery_gate.py` | 缺少必要文档、模块级验证、委派证据、compile/sim log 时拒绝 final PASS |
| Protocol Claim Ledger Evidence Gate | `project_artifact_gate.py` | 项目声称 PASS 时，`protocol_claim_ledger.md` 中 Evidence 为空/TBD/占位符的条目会 FAIL |
| Storage Mover Evidence Gate | `project_artifact_gate.py` | 检查 WSTRB/unaligned、RRESP/RD error、`cpl_bytes`、PRP list 公共接口、invalid-command completion |
| Pre-Integration Gate | `pre_integration_gate.py` | L2 项目在缺少逐模块证据时不允许直接进入集成仿真；支持识别 extensionless Icarus 输出 |
| Windows `.vvp` 修复 | `run_sim_guarded.py` | Windows 下自动通过 `vvp <file>` 执行 `.vvp` |
| README 发布说明 | `README.md`, `README_CN.md` | 中英文 README 均新增 `v2026.06.05` 发布说明 |

### 验收

| 命令 | 结果 |
|------|------|
| `python -B scripts/skill_static_check.py` | PASS |
| `python -m py_compile scripts/project_artifact_gate.py scripts/pre_integration_gate.py scripts/run_sim_guarded.py scripts/final_delivery_gate.py scripts/sim_log_gate.py scripts/project_preflight_gate.py` | PASS |
| `project_artifact_gate.py nvme-io-path` | FAIL as expected：捕获 protocol ledger TBD、PRP list backdoor、invalid-command completion 缺口、WSTRB/shape/T10/T11 缺口 |
| `project_artifact_gate.py Descriptor-Based AXI DMA Mover` | FAIL as expected：捕获 RRESP/shape/T10/doc-only/模块级证据缺口 |
| `pre_integration_gate.py NAND Flash page controller` | FAIL as expected：捕获 extensionless integration sim artifact 早于模块级 evidence |

## 2026-06-04 - 存储项目证据绑定 + 门禁加固（第三轮）

### 背景

基于 NAND/DMA/NVMe 三个存储项目复盘发现的持续绕过门禁问题：verification matrix 行声称 PASS 但无 TB 执行证据、protocol claim ledger 的 Evidence 列为 TBD/blank、存储 mover 特定功能（WSTRB/RRESP/cpl_bytes/PRP list 公共接口）缺乏 TB 检查、extensionless Icarus 输出未被 pre-integration gate 识别、Windows 上 .vvp 文件无法直接执行。

### P0 改动

| 改动 | 位置 | 说明 |
|------|------|------|
| Protocol Claim Ledger Evidence Gate | `project_artifact_gate.py` `check_protocol_claim_ledger_evidence()` | L1/L2 项目声称 PASS 时，claim ledger 每行 Evidence 必须非空、非 TBD、非占位符 |
| Storage Mover Evidence Gate | `project_artifact_gate.py` `check_storage_mover_evidence()` | WSTRB/unaligned 需 TB 比对 expected_wstrb；RRESP/RD error 需 TB 检查非仅 BRESP；cpl_bytes 需检查；PRP list 需公共接口 exercise 非 hierarchical dut.* 写入；T10/T11/WSTRB/shape 声称需对应 TB markers |
| Extensionless Icarus Artifact Detection | `pre_integration_gate.py` `_find_integration_sim_artifacts()` | 识别 `sim/tb_*`、`sim/top_*`、`sim/integration_*` 无扩展名 Icarus 输出为集成仿真产物 |
| Windows .vvp Execution Fix | `run_sim_guarded.py` | Windows 上 `.vvp` 文件自动通过 `vvp <file>` 调用，不再尝试直接执行 |

### 验收结果

| 检查项 | 结果 |
|------|:----:|
| `python -B -m py_compile` 关键脚本 | PASS |
| `python -B scripts/skill_static_check.py` | PASS |
| `python -B scripts/project_preflight_gate.py` nvme-io-path | PASS |
| `python -B scripts/project_artifact_gate.py` nvme-io-path | FAIL as expected: evidence tokens only in docs (C1-C5, T10, T11), missing module matrix/delegation, scoreboard substance (AWADDR/AWLEN/WSTRB/WLAST/BRESP), storage mover evidence (WSTRB, T10/T11/shape) |
| `python -B scripts/pre_integration_gate.py` nvme-io-path | FAIL as expected: integration sim artifacts (.vvp, .log) before 6 modules lack per-module evidence |
| `python -B scripts/final_delivery_gate.py` nvme-io-path | FAIL as expected: artifact + pre-integration + rtl_style (RSP2/RSP4/TB_COMPLETION_ONLY1/TB_TIMEOUT_FATAL1) + missing compile log |
| `python -B scripts/project_artifact_gate.py` DMA Mover | FAIL as expected: evidence tokens only in docs (T5/T6/T8/T10/cpl), missing module matrix/delegation, scoreboard substance, storage mover evidence (RRESP, T10/T11/shape) |
| `python -B scripts/rtl_style_check.py` prp_walker.v | FAIL as expected: C17_ARR1 + RSP4 x2 |
| `python -B scripts/rtl_style_check.py --level L2` prp_walker.v | FAIL as expected: same findings, RSP4 stays E-level |

---

## 2026-06-04 - 断线恢复后的 Codex 补强验收

### 背景

本轮原计划继续采用“Codex 制定方案和验收标准 -> Claude 执行修改 -> 自动门禁 -> Codex 审计关键 diff”的流程。Claude Code 在执行过程中因本机网络中断/API 连接失败退出，未能形成可确认的完整执行结果。断线恢复后由 Codex 直接接管补强，并完成自动门禁与三个真实项目回归。

### Codex 补强点

| 项目 | 位置 | 说明 |
|------|------|------|
| PRP list 假加载误判修正 | `scripts/project_artifact_gate.py` | `list_mem[idx]` 声明或读取不再被当作 load/fetch 证据；必须看到 list memory 写入、list load/write/fetch 接口或 AR fetch 通道 |
| PRP1 non-zero offset claim 收紧 | `scripts/project_artifact_gate.py` | 文档声称 PRP1 offset 支持时，RTL 缺少 offset/mask/base 逻辑或直接拒绝 non-zero offset 都会 FAIL |
| L2 推断一致化 | `scripts/final_delivery_gate.py` | final gate 的 level 推断与 artifact/preflight gate 对齐，rtl >=3、多协议、top+>=2 leaf 都会触发 L2，从而传递 `--level L2` 给 `rtl_style_check.py` |
| pre-integration 多协议补齐 | `scripts/pre_integration_gate.py` | 不再只识别 NVMe+AXI；DMA/NAND+AXI 同样作为 L2 多协议信号处理 |
| pre-integration 噪音收窄 | `scripts/pre_integration_gate.py` | `compile.log`/build/vlog/iverilog 日志不再被当作 integration sim artifact；抢跑判断聚焦仿真运行产物 |
| top+leaf 推断修正 | `scripts/project_artifact_gate.py`, `scripts/project_preflight_gate.py`, `scripts/final_delivery_gate.py`, `scripts/pre_integration_gate.py` | 识别一个 top module 实例化 >=2 个不同 leaf module 的结构，避免只统计同一模块实例次数 |

### 验收结果

| 检查项 | 结果 |
|------|:----:|
| `python -B -m py_compile` 关键脚本 | PASS |
| `python -B -m json.tool` evals/benchmark | PASS |
| `python -B scripts/skill_static_check.py` | PASS |
| `python -B scripts/eval_benchmark_check.py` | PASS, TOTAL_EVALS=114, EXECUTABLE_TRIALS=23 |
| `sim_log_gate.py` expected timeout smoke | PASS |
| `sim_log_gate.py` real wrapper timeout smoke | FAIL as expected |
| `nvme-io-path` 回归 | FAIL as expected: false delegation, missing module matrix, pre-integration violation, RSP2/RSP3, weak scoreboard, PRP claim |
| `Descriptor-Based AXI DMA Mover` 回归 | FAIL as expected: artifact-based L2, missing module matrix/delegation decision, integration artifact before module evidence, weak scoreboard, no standard logs |
| `NAND Flash page controller` 回归 | FAIL as expected: artifact-based L2, missing protocol ledger/module matrix/delegation decision, missing compile/sim logs |

### 流程记录

本轮属于 Claude 执行阶段被网络中断后的 Codex 兜底修改。后续如果继续按双 agent 流程执行，应在 Claude 断线/API 失败后明确记录“Claude 未完成”，再由 Codex 补丁或重新调用 Claude，避免开发日志误认为修改由 Claude 完整落地。

## 2026-06-04 – L2 存储项目复盘第二轮：五项 P0 + 五项 P1 门禁加固

### 背景

Codex 审计三个 L2 存储项目（nvme-io-path、NAND Flash page controller、Descriptor-Based AXI DMA Mover），发现 agent 仍能绕过现有门禁：跳过逐模块仿真直接跑集成、伪造 delegation provenance、dev_log 缺 Level 导致 L2 被误判为 L1、RSP2 在 L2 项目仍是 W-level、verification matrix 只检查 doc 提及不检查 TB/sim 执行证据。

### P0 改动

| 改动 | 位置 | 说明 |
|------|------|------|
| Pre-Integration Simulation Lock | `scripts/pre_integration_gate.py` (新), `final_delivery_gate.py` Step 1b | L2 项目 integration TB 或 sim artifact 存在但逐模块证据缺失时 FAIL |
| False Delegation Provenance Gate | `project_artifact_gate.py` `_check_role_report_provenance()` | Delegate: yes 的 role report 必须包含 Role/Scope/Input contract/Evidence source/Acceptance commands/Findings 六个 provenance 字段 |
| L2 Auto-Classification Hardening | `project_artifact_gate.py`, `project_preflight_gate.py` | rtl >=3 文件、top+>=2 leaf、multi-protocol 信号 -> L2；dev_log 无 Level 不覆盖 artifact 推断 |
| RSP2 L2 Hard Error | `rtl_style_check.py` `--level L2`, `final_delivery_gate.py` | L2 项目 FSM comb block 分配 multi-bit datapath/sideband 信号升级为 E-level |
| Verification Matrix Evidence Closure | `project_artifact_gate.py` `check_verification_matrix_evidence()` | 矩阵条目必须绑定 TB 文件或 sim log 执行证据；仅 doc 提及不算证据；planned-only 需 NOT_RUN/WAIVED |

### P1 改动

| 改动 | 位置 | 说明 |
|------|------|------|
| Empty Compile Log Gate | `compile_log_gate.py` | 空白/纯 whitespace compile log 直接 FAIL |
| Expected Timeout Allowance | `sim_log_gate.py` `is_expected_timeout_context()` | ALL_TESTS_PASS + SIMULATION_DONE 存在时，TEST_PASS.*timeout/status=TIMEOUT 类文本允许通过 |
| Standard Log Artifact Requirement | `final_delivery_gate.py` Step 5 | .vvp 无 .log 不可接受；必须有 run_sim_guarded.py 产生的 .log 证据 |
| Scoreboard Substance Gate | `project_artifact_gate.py` `check_scoreboard_substance()` | DMA/NVMe TB 提及 AWADDR/AWLEN/WLAST/WSTRB/BRESP 但无 expected comparison 逻辑则 FAIL |
| PRP Feature Claim Gate | `project_artifact_gate.py` `check_prp_feature_claims()` | list_mem 无 load/fetch 接口、PRP1 non-zero offset 无 RTL 逻辑则 FAIL |

### Reference 更新

| 文件 | 说明 |
|------|------|
| `references/verification/per-module-simulation-gate.md` | 新增 Pre-Integration Lock 段落，明确集成仿真禁令 |
| `SKILL.md` Step 9/10 | 新增 pre_integration_gate、delegation provenance、RSP2 L2、scoreboard substance、standard log artifact 等 finalization gates |

### Evals

新增 eval 106-114，覆盖 pre-integration lock、delegation provenance、L2 inference hardening、RSP2 hard error、empty compile log、expected timeout allowance、standard log artifact、scoreboard substance、PRP feature claim gate。新增 benchmark 维度 `pre_integration_lock`、`delegation_provenance`、`l2_classification_hardening`、`rsp2_level_escalation`、`empty_compile_log`、`expected_timeout_allowance`、`standard_log_artifact`、`scoreboard_substance`、`prp_feature_claim`。

### 验收要求

| 检查项 | 预期 |
|------|:----:|
| `python -m py_compile` 全部脚本 | PASS |
| `python -m json.tool` evals/benchmark | PASS |
| `python scripts/skill_static_check.py` | PASS |
| `python scripts/eval_benchmark_check.py` | PASS，eval 总数 >= 114 |
| nvme-io-path 回归 | FAIL (false delegation, missing module matrix, RSP2, PRP claim) |
| NAND Flash 回归 | FAIL (missing protocol ledger/module matrix/standard logs) |
| DMA Mover 回归 | FAIL (L2 classification, missing module matrix, RSP4, scoreboard) |

---

## 2026-06-04 — Codex 审计补漏：逐模块仿真硬门禁与门禁误报回归

### 背景

Claude Code 已完成本轮主体修改，但 Codex 复核后发现仍有三个会影响验收可信度的缺口：L2 逐模块仿真没有形成独立 reference 与最终矩阵门禁；`sim_log_gate.py` 会把真实的 `RUN_SIM_GUARDED: TIMEOUT` 当作 wrapper 元数据跳过；`rtl_style_check.py` 的 RSP 结构规则仍可能作用到 TB 层级调试代码。

### Codex 补漏改动

| 改动 | 位置 | 说明 |
|------|------|------|
| L2 逐模块仿真硬门禁 | `references/verification/per-module-simulation-gate.md`, `SKILL.md`, `reference-index.md` | 新增独立 reference，要求 `docs/module_verification_matrix.md` 记录每个 RTL module 的 TB/formal 证据，集成仿真不能替代模块级证据 |
| module verification matrix 自动检查 | `scripts/project_artifact_gate.py` | L2 项目缺少 `docs/module_verification_matrix.md`、module 未列入矩阵、证据日志缺失或无 PASS marker 时拒绝 final PASS |
| verification matrix 证据闭环加强 | `scripts/project_artifact_gate.py` | final PASS 时拒绝 Pending/TBD/空白矩阵行，并把矩阵测试 ID 与 TB/sim log 交叉验证 |
| guarded wrapper 日志误判修复 | `scripts/sim_log_gate.py` | 仅忽略 `RUN_SIM_GUARDED: command=... timeout=30s` 等良性元数据；真实 `RUN_SIM_GUARDED: TIMEOUT/FAIL` 仍然 FAIL |
| TB 与 RTL RSP 分层 | `scripts/rtl_style_check.py` | TB 继续执行 false-pass 检查，但 RSP FSM/datapath purity 只作用于设计 RTL；TB 层级读取 `cstate` 不再误报 |
| gate false-positive eval 回归 | `evals/evals.json`, `evals/benchmark.json` | 新增 eval 100-105，覆盖逐模块仿真、wrapper timeout、`$display` 字符串、多层级 TB debug、矩阵 ID 证据闭环 |

### 验收要求

| 检查项 | 预期 |
|------|:----:|
| `python -m py_compile` 关键脚本 | PASS |
| `python -m json.tool` evals/benchmark | PASS |
| `python scripts/skill_static_check.py` | PASS |
| `python scripts/eval_benchmark_check.py` | PASS，eval 总数应 >= 105 |
| smoke: `sim_log_gate.py` wrapper metadata | PASS |
| smoke: `sim_log_gate.py` real `RUN_SIM_GUARDED: TIMEOUT` | FAIL |
| smoke: L2 缺少 `module_verification_matrix.md` | FAIL |

---

## 2026-06-04 — L2 存储项目复盘：逐模块仿真 + 工具误报修复

### 背景

Codex 审计两个 L2 存储项目，发现五个反复出现的问题：跳过逐模块仿真直接跑集成、FSM/datapath purity 在集成时才暴露、verification_matrix 与 TB 测试名不匹配、sim_log_gate 误拒 wrapper 元数据、rtl_style_check 误报 $display 格式字符串。

### 改动

| 改动 | 位置 | 说明 |
|------|------|------|
| L2 逐模块仿真门禁 | `SKILL.md` Step 7/9/10, `simulation-loop.md` | L2 每个子模块必须先通过独立 TB 仿真，才能进入集成 TB |
| verification_matrix 测试名交叉检查 | `project_artifact_gate.py`, `contract-to-test-trace-gate.md` | 解析 verification_matrix.md 中的 TEST_PASS/check_/test_ 引用，与 TB 文件交叉验证 |
| sim_log_gate RUN_SIM_GUARDED 误报修复 | `sim_log_gate.py` | FAIL_PATTERNS 匹配时跳过 `RUN_SIM_GUARDED:` 等良性元数据行 |
| rtl_style_check $display 格式串误报修复 | `rtl_style_check.py` | 新增 `_strip_string_contents()` 辅助函数，LHS 赋值正则匹配前移除字符串内容 |
| TB_FPASS1 正则收窄 | `rtl_style_check.py` | 仅匹配 `mismatch`（强误报指标），不再匹配 `exp`/`expected`（良性格式标签）|
| _collect_tb_content 重构 | `project_artifact_gate.py` | 提取公共 TB 内容收集函数，供 evidence_cross_ref 和 verification_matrix 共用 |

### 验证

| 检查项 | 结果 |
|------|:----:|
| `python -m py_compile` 修改脚本 | PASS |
| `python scripts/skill_static_check.py` | PASS |
| SKILL.md 行数 | 456 / 460 |

---

## 2026-06-04 — 工作流入口前置 + 项目骨架预检 + 受控仿真包装器

### 背景

上一轮门禁已经能拦住坏交付，但流程仍有顺序问题：review/debug/protocol-audit 容易被完整 RTL pipeline 拖慢；No-SPEC 项目的 docs/matrix 常被最后补；仿真跑飞只能事后发现；contract implementation matrix 仍有 final-time reconstruction 风险。

### P0 改动

| 改动 | 位置 | 说明 |
|------|------|------|
| Step 0 Workflow Entry Routing | `SKILL.md`, `references/workflow/task-mode-routing.md` | routing 前置到 Standard Workflow 之前；review/debug/protocol-audit/skill-maintenance 不进入完整 design pipeline |
| Review gate-first 顺序 | `task-mode-routing.md`, eval 97 | review 先看 artifact/style/compile/sim/runtime evidence，再做 manual hotspot review |
| Project Skeleton / Preflight Gate | `SKILL.md` Step 1.2, `scripts/project_preflight_gate.py` | RTL 前检查 `docs/`, `rtl/`, `tb/`, `sim/` 和 7 个 canonical docs skeleton |
| Contract matrix 前移 | `SKILL.md` Step 3, `contract-implementation-gate.md` | contract freeze 后立即创建 `contract_implementation_matrix.md` skeleton，开发过程中逐项填 evidence |
| Guarded simulation wrapper | `scripts/run_sim_guarded.py`, `simulation-loop.md`, `SKILL.md` Step 9 | 替代裸 `vvp`；捕获 log、限制 timeout、限制 VCD/log 大小、UTF-8 安全输出 |
| Final/preflight 关系明确 | `SKILL.md` Step 10 | preflight 是 RTL 前骨架门，final_delivery 是交付前聚合门 |

### Codex 审计补漏

| 补漏 | 位置 | 说明 |
|------|------|------|
| VCD/log 超限硬失败 | `run_sim_guarded.py` | size limit exceeded 返回 RC=3，不再打印 wrapper 伪造的 `ALL_TESTS_PASS` |
| Wrapper 失败写回 log | `run_sim_guarded.py` | size 超限时写入 `RUN_SIM_GUARDED_FAIL`，即使 child 已打印 `ALL_TESTS_PASS`，`sim_log_gate.py` 仍会拒绝 |
| L1/L2 skeleton 一致 | `project_preflight_gate.py` | L1/L2 No-SPEC 均要求 `tb/`，保证 TB 不是后补品 |
| Eval 可追踪维度 | `benchmark.json` | 新增 `workflow_routing_gate_first_review`, `project_skeleton_preflight_no_spec`, `guarded_sim_wrapper_timeout_vcd_limit` |

### 验证

| 检查项 | 结果 |
|------|:----:|
| `python -m py_compile` 新增/关键脚本 | PASS |
| `python -m json.tool` evals/benchmark | PASS |
| `python scripts/skill_static_check.py` | PASS |
| `python scripts/eval_benchmark_check.py` | PASS，99 evals |
| `project_preflight_gate.py` 空项目 | FAIL，符合预期 |
| `project_preflight_gate.py` 完整 skeleton | PASS |
| `run_sim_guarded.py` 正常命令 | RC=0，log 保留 testbench markers |
| `run_sim_guarded.py` timeout | RC=1，打印 TIMEOUT |
| `run_sim_guarded.py` VCD 超限 | RC=3，不打印 wrapper 伪造 PASS |
| VCD 超限 log 复核 | `sim_log_gate.py` RC=1，符合预期 |

---

## 2026-06-04 — Codex 审计补漏：RSP1 升级与 UTF-8 门禁输出

### 背景

Claude Code 在本轮修改过程中因本机断电/连接中断未能完整返回最终报告，但工作区已有部分写入。Codex 接管验收后执行补漏，重点处理两个问题：中文路径在 gate 聚合输出中乱码，以及 RSP1 仍以 W 级报告，严重度不足以体现“状态寄存器块只更新 cstate”的硬边界。

### 补漏改动

| 改动 | 位置 | 说明 |
|------|------|------|
| UTF-8 安全输出 | `compile_log_gate.py`, `final_delivery_gate.py`, `project_artifact_gate.py`, `rtl_style_check.py`, `sim_log_gate.py` | stdout/stderr 统一 UTF-8 + replace，`final_delivery_gate.py` 子进程强制 `PYTHONIOENCODING=utf-8`，中文路径不再乱码 |
| RSP1 升级 | `rtl_style_check.py` | `cstate` state-register block 中出现任何其他寄存器赋值由 W 升级为 E |
| TB 自动发现补强 | `final_delivery_gate.py` | style gate 自动扫描 `sim/tb_*.v`，即使 artifact gate 另行报告非规范 TB 位置，也不会漏掉 false-pass TB 检查 |
| 验证记录补齐 | 本日志 + `CLAUDE.md` | 记录断点恢复、Codex 补漏和真实项目回归结果 |

### 验证

| 检查项 | 结果 |
|------|:----:|
| `python -m py_compile` 关键脚本 | PASS |
| `python scripts/skill_static_check.py` | PASS |
| `python scripts/compile_log_gate.py` smoke test | PASS |
| `python scripts/eval_benchmark_check.py` | PASS |
| DMA artifact gate | FAIL，符合预期：不再误报 delegation 缺失，改为要求 compensation gates |
| NAND artifact gate | FAIL，符合预期：识别非规范 delegation，仍拒绝缺失 docs 与 compensation gates |
| NAND compile log gate | FAIL，符合预期：拦截 `24'd16777216` numeric truncation |
| NVMe final delivery gate | FAIL，符合预期：拦截缺 docs、非规范 TB 位置、RSP1/RSP4、compile x 注入、缺 sim log、102MB VCD |

---

## 2026-06-03 — Runtime 失控门禁 + 编译强化 + 交付物完整性 + RTL 纯度修正

### 触发背景

Descriptor DMA Mover、NAND Flash Page Controller、nvme-io-path 三个项目审计发现：仿真 PASS 但 final gate FAIL；compile truncation 24'd16777216->0 未被门禁拦截；无 sim log/超大 VCD 时仍声称完成；delegation markdown 格式解析不全；TB 偏 completion-only；RTL 纯度检查有误报。

### P0 改动

| 改动 | 位置 | 说明 |
|------|------|------|
| Runtime/runaway guard | `final_delivery_gate.py` Step 5 | VCD>50MB、log>20MB、大量 VCD 文件、无 sim log -> FAIL |
| 编译门禁强化 | `compile_log_gate.py` | numeric truncation (24'd16777216)、out-of-bound/x注入、编码安全输出 |
| 交付物完整性 | `project_artifact_gate.py` | delegation 兼容 markdown bold + Delegation Decision 备选格式；evidence 兼容 sim/tb_*.v；TBD/空白/Summary 空 -> FAIL |
| RTL 纯度误报修正 | `rtl_style_check.py` | FSM comb single-bit enable 含 _cnt_ 不再误报；PRP_STUB/PRP_LIST_FAKE 仅扫 RTL 不扫 TB |
| AXI W 连续 burst | SKILL.md Step 2a | continuous 模式需 FIFO 有 AWLEN+1 beats，仅 !dfifo_empty 不够 |

### P1 改动

| 改动 | 位置 | 说明 |
|------|------|------|
| 回归 evals | `evals/evals.json` + `benchmark.json` | 新增 nvme_runaway_and_rsp_purity、nand_timeout_width_warning、dma_axi_w_burst_fifo_starvation |
| 开发记忆 | CLAUDE.md + SKILL_CHANGELOG.md | 本轮记录 |

### 验证

| 检查项 | 结果 |
|------|:----:|
| py_compile | PASS |
| json.tool + eval_benchmark_check | PASS |

---

## 2026-06-03 — 空 docs + PRP stub/简化 + 位宽越界编译警告硬化

### 触发原因

nvme-io-path 最新项目：`docs/` 空、无 dev_log、无 SPEC、无合约，仅产出 RTL + 仿真成功摘要。`project_artifact_gate` 因缺 dev_log 默认为 L1 未拒绝。编译日志有 Icarus warning `PAGE_SIZE[63:0] selecting after PAGE_SIZE[31:0]` 但未被门禁拒绝。RTL prp_walker 注释 `Simplified` 暴露假 PRP 实现。

### 改动

| 改动 | 位置 | 说明 |
|------|------|------|
| L2 自动推断 | `project_artifact_gate.py` | 无 dev_log 时从项目复杂度推断 L2：rtl/*.v >=3、NVMe+AXI 信号共存、tb/+rtl/ 目录结构 |
| PRP_STUB2 / PRP_LIST_FAKE1 | `rtl_style_check.py` | E 级：PRP 相关文件中检测 `Simplified`、`would fetch from PRP2 list`、`advance by PAGE_SIZE` 等假 PRP list 实现 |
| WIDTH_BOUND1 | `rtl_style_check.py` | W 级：检测窄参数做宽位选择（如 PAGE_SIZE[63:0]），Icarus 填充 'bx |
| AXI_WDATA_SOURCE1 | `rtl_style_check.py` | E 级：WVALID/WACTIVE 不能在 FIFO 数据可用性未证明时呈现 FIFO-backed WDATA |
| RSP3 升级 + RSP4 | `rtl_style_check.py` | E 级：datapath 时序块和输出/数据通路赋值不得直接解码 `cstate/S_*` |
| NVM_STRAY_DATA1 | `rtl_style_check.py` | W 级：NVM read data ready / FIFO write enable 不能脱离 collect/active 控制 |
| compile_log_gate | `scripts/compile_log_gate.py` | 新增：编译日志中的 out-of-bound select、`'bx` replacement、width/port mismatch、implicit net、latch 等硬拒绝 |
| final_delivery_gate | `scripts/final_delivery_gate.py` | 新增：聚合 artifact/style/compile/sim 四类门禁；缺 docs 或缺日志不能交付 PASS |
| eval 88-93 | `evals/evals.json`, `evals/benchmark.json` | 新增 fail-closed 交付、空 docs L2 推断、编译日志、PRP 假实现、AXI WDATA、FSM/datapath 纯度 eval |
| CLAUDE.md | CLAUDE.md | 记录本轮硬化教训 |

### 验证

| 检查项 | 结果 |
|------|:----:|
| py_compile（6 个脚本） | PASS |
| skill_static_check | PASS |
| json.tool + eval_benchmark_check | PASS（93 evals / 34+1 dimensions / 23 executable trials） |
| SKILL.md | PASS（462 行，ASCII） |
| compile_log_gate timescale-only 合成日志 | PASS（不误伤 inherited timescale） |
| nvme-io-path: project_artifact_gate | FAIL（预期：L2 推断 + 7 个 docs 缺失 + 无 delegation decision） |
| nvme-io-path: rtl_style_check | FAIL（预期：PRP_LIST_FAKE1、AXI_WDATA_SOURCE1、RSP3/RSP4、NVM_STRAY_DATA1、TB false-pass） |
| nvme-io-path: compile_log_gate | FAIL（预期：PAGE_SIZE 越界 part-select + `'bx` replacement） |
| nvme-io-path: sim_log_gate | FAIL（预期：缺 ALL_TESTS_PASS / SIMULATION_DONE） |
| nvme-io-path: final_delivery_gate | FAIL（预期：四类门禁聚合拒绝） |

---

## 2026-06-03 — L2 委派证据 + 合同实现闭环 + 残余风险分级门禁

### 触发原因

nvme-io-path 审计发现：dev_log `Delegate: yes` 但无 sub-agent work package / role reports / integration reviewer 证据；SPEC 写 PRP list fetch 但 RTL tie off AR/R、`prp_err_o` 恒 0、`slba` 未进入 NVM 源地址；TB completion-only 缺 transaction-shape scoreboard；PASS 同时 residual risks 含 `No .*testing`/`NOT supported` 等阻塞语义；No-SPEC artifact 路径不一致。

### P0 改动

| 改动 | 位置 | 说明 |
|------|------|------|
| L2 委派执行证据门禁 | SKILL.md Step 1.1 | Delegate: yes 必须产出 `docs/delegation_plan.md` + subagent role reports |
| 委派 artifact schema | sub-agent-delegation.md | 7 个强制交付物：delegation plan + 6 个 role reports；缺任何一项 `project_artifact_gate.py` 拒绝 PASS |
| 合同实现矩阵 | NEW `references/workflow/contract-implementation-gate.md` | 每个 contract item -> RTL producer/consumer + TB check + waiver；NVMe/DMA 必须覆盖 6 类 |
| 合同矩阵门控 | SKILL.md Step 10 + `project_artifact_gate.py` | `docs/contract_implementation_matrix.md` 为 L1/L2 No-SPEC 必需交付物 |
| Transaction-shape 强制 | SKILL.md Step 8b | completion-only TB 不通过 PASS；`rtl_style_check.py` TB_COMPLETION_ONLY1 保持 E 级 |
| 残余风险分级 | `contract-implementation-gate.md` + `project_artifact_gate.py` | Blocking Gap / Accepted Limitation / Residual Risk 三级；PASS 时禁止无豁免阻塞项 |
| No-SPEC artifact 路径统一 | SKILL.md + `project_artifact_gate.py` | 规范路径 `docs/` 下 |

### P1 改动

| 改动 | 位置 | 说明 |
|------|------|------|
| RTL_MULTI_DRIVER1 误报修复 | `rtl_style_check.py` | 关系 `<=` 在条件中不再误报为过程赋值 |
| C17_ARR1 检测 | `rtl_style_check.py` | W 级：`reg [..] mem [..]` 非打包数组，需 BRAM 或 waiver |
| PRP_STUB1 检测 | `rtl_style_check.py` | E 级：AR 通道信号只被赋 0，PRP list fetch 疑似 stubbed |
| ERR_STUB1 检测 | `rtl_style_check.py` | W 级：error 输出只赋 0，错误传播路径疑似 stubbed |
| PRP_STUB1 降误报 | `rtl_style_check.py` | Codex 审计补漏：PRP_STUB1 只在 NVMe/PRP 上下文触发，普通 AXI AR tie-off 不误报 |
| Eval 文案补漏 | `evals/evals.json` | Codex 审计补漏：修复 eval 84-86 空 snippet，更新 No-SPEC canonical `docs/` 路径 |
| SKILL.md ASCII 静态门禁 | `skill_static_check.py` | 将 SKILL.md 非 ASCII 检查并入常规静态门禁，避免中英文/特殊符号回归 |
| CLAUDE.md | CLAUDE.md | 记录本轮回归教训 |

### 验证

| 检查项 | 结果 |
|------|:----:|
| skill_static_check.py | PASS |
| SKILL.md ASCII audit | PASS |
| py_compile（3 个脚本） | PASS |
| json.tool + eval_benchmark_check | PASS（34 dimensions, 87 evals） |
| project_artifact_gate on nvme-io-path | PASS：按预期 REJECT，缺 `docs/SPEC.md`、claim ledger、verification matrix、contract matrix、delegation evidence |
| rtl_style_check on nvme-io-path | PASS：按预期拒绝 `PRP_STUB1`、`ERR_STUB1`、`C17_ARR1`、`RTL_MULTI_DRIVER1`、`TB_TIMEOUT_FATAL1`、`TB_COMPLETION_ONLY1` |
| residual-risk synthetic gate | PASS：`Status: PASS` + 未豁免 `No multi-page transfer testing` 被拒绝 |
| generic AXI AR tie-off scope test | PASS：非 NVMe/PRP 上下文下不触发 `PRP_STUB1` |

---

## 2026-06-03 — SKILL.md 编码清理

### 触发原因

SKILL.md 编码规则章节包含中文 CJK 文本，且全文散布非 ASCII 符号（em dash、箭头、勾选、Unicode 不等号等）。部分终端渲染异常，且破坏仅限 ASCII 的工具链。

### 改动

| 改动 | 位置 | 说明 |
|------|------|------|
| 中译英 | SKILL.md 第 70-80 行 | 编码规则章节：中文全部替换为语义等价的英文 |
| 非 ASCII 符号替换 | SKILL.md 全文 | `—` -> `--`、`→` -> `->`、`✅` -> `[PASS]`、`≤` -> `<=`、`≥` -> `>=`、`§` -> `section` |
| 编码策略 | CLAUDE.md | 新增规则：SKILL.md 必须保持 English-only 且编码稳定 |

### 验证

| 检查项 | 结果 |
|------|:----:|
| skill_static_check.py | PASS |
| py_compile（3 个脚本） | PASS |
| json.tool evals.json / benchmark.json | PASS |
| eval_benchmark_check.py | PASS（33 维度，80 条 eval） |
| Select-String 审计（CJK/乱码/禁用符号） | CLEAN |

---

## 2026-06-03 — 低约束 NVMe 回归加固

### 触发原因

最新一次零 SPEC `nvme-io-path` 运行暴露了多类非协议特异性缺陷：FSM/数据通路职责混杂、`axi_wr_engine` 存在真实的多驱动寄存器、仅打印文本的假通过审计、缺少 X/Z 检测、侧信道未检查、宽度常量硬编码、以及 PRP 列表地址形状测试仅计数 beat 而未校验地址。

### 改动

| 改动 | 位置 | 说明 |
|------|------|------|
| No-SPEC 交付物 | `SKILL.md` | L1/L2 零 SPEC 工作必须创建 `SPEC.md`、`docs/interface-contracts.md`、`docs/protocol_claim_ledger.md`、`docs/verification_matrix.md`；`dev_log.md` 仅作证据链 |
| 合约到测试追溯 | `references/workflow/contract-to-test-trace-gate.md` | 每个可见的状态/错误/计数/地址侧信道必须映射到 RTL 生产者/消费者逻辑，并有 TB 检查或豁免 |
| PASS 门控收紧 | `references/verification/simulation-loop.md` | PASS 现在要求编译干净或警告豁免、`rtl_style_check.py` 干净、合约到测试追溯完成 |
| L2 委派豁免收紧 | `references/architecture/sub-agent-delegation.md` | "模块紧密耦合"不再足够；豁免必须说明为何架构/验证/协议/集成通道无法独立运行 |
| 检查器加固 | `scripts/rtl_style_check.py` | 新增/强化 `RTL_MULTI_DRIVER1`、`TB_FPASS_AUDIT1`、`TB_XZ1`、`TB_SIDEBAND1`、`PARAM_HARDCODE1`、`PARAM_PARTSEL1`、`TB_PRP_LIST1`、`TB_PRP_AWADDR1`、单行 `TB_WAIT1` |
| Eval 扩展 | `evals/evals.json`、`evals/benchmark.json` | 新增 eval 72-75，覆盖零 SPEC 交付物、PRP 列表地址形状、背靠背命令上下文、多驱动/假通过负面测试 |
| 执行器记忆 | `CLAUDE.md` | 记录低约束 NVMe 回归教训，供后续 Claude Code 执行参考 |

### 验证

| 检查项 | 结果 |
|------|:----:|
| py_compile `rtl_style_check.py` | PASS |
| json.tool `evals/evals.json` / `evals/benchmark.json` | PASS |
| eval_benchmark_check.py | PASS（33 维度，75 条 eval） |
| `rtl_style_check.py` 对 `nvme-io-path` | 命中全部预期回归：`b_error_q` 多驱动、RSP3 FSM/数据通路杂质、假审计、缺失 X/Z、未检查 `busy`/`cpl_bytes_written`、`BUS_BYTES[63:0]` 硬编码、缺失 PRP 列表数据条目地址检查、缺失 AWADDR 检查、无界单行 wait |

---

## 2026-06-03 — 仿真/证据加固

### 触发原因

nvme-io-path 项目编译通过但 T2 挂死。TB 超时块打印 TIMEOUT 后调用 `$finish`，进程退出码为 0，朴素门控误判为成功。协议 claim ledger 引用了 T3/T10 证据，但这些测试在 TB 文件中并不存在。`docs/verification_matrix.md` 缺失。RSP3 在有合规注释的情况下仍被违反。TB 仅检查完成状态/字节数，缺少事务形状计分板。

### 改动

| 改动 | 位置 | 说明 |
|------|------|------|
| `sim_log_gate.py` | `scripts/sim_log_gate.py`（新建） | CLI 门控：仅当日志包含 ALL_TESTS_PASS + SIMULATION_DONE 且无 TIMEOUT/FAIL/FATAL/mismatch/xxxx/X-Z 时 exit 0。拒绝 nvme-io-path 的 TIMEOUT 日志。 |
| `project_artifact_gate.py` | `scripts/project_artifact_gate.py`（新建） | CLI 门控：L1/L2 No-SPEC 要求 dev_log + SPEC + interface-contracts + protocol_claim_ledger + verification_matrix。证据交叉校验：解析 ledger 中的 T-number token，在 TB 文件中验证。因缺少 verification_matrix.md 和 T3/T10 证据而拒绝 nvme-io-path。 |
| TB_TIMEOUT_FATAL1 | `scripts/rtl_style_check.py` | E 级：超时块打印 TIMEOUT + 调用 `$finish` 但无 `$fatal` 或错误计数器。进程退出码 0 = 假通过。 |
| TB_COMPLETION_ONLY1 | `scripts/rtl_style_check.py` | E 级：DMA/NVMe TB 检查完成但从未比较 AWADDR/AWLEN/WSTRB/WLAST/BRESP。 |
| RSP3 注释声明升级 | `scripts/rtl_style_check.py` | 若文件注释声称 RSP3/RSP 合规但实际触发违规，升级为 E 级。仅注释合规无效。 |
| N1 ANSI 解析修复 | `scripts/rtl_style_check.py` | 修复：ANSI 声明中 `wire`/`reg`/`logic` 不再被误报为端口名。task/function 参数已排除。 |
| TB_SIDEBAND1 严格化 | `scripts/rtl_style_check.py` | `cpl_bytes_written` 现在要求与 `expected_bytes`/`expected_count` 比较，而非任意比较。 |
| 超时必须使用 `$fatal` | `references/verification/simulation-loop.md` | 模板超时看门狗从 `$finish` 改为 `$fatal` + `fail_cnt++` + `TESTS_FAILED`。TBR2 已更新。 |
| `sim_log_gate.py` 必须通过 | `references/verification/simulation-loop.md` | 检查项：`sim_log_gate.py` 必须在实际仿真日志上 exit 0 才能声称 PASS。 |
| `project_artifact_gate.py` 必须通过 | `references/verification/simulation-loop.md` | 检查项：L1/L2 No-SPEC 必须通过交付物门控。 |
| 证据交叉校验 | `references/workflow/contract-to-test-trace-gate.md` | Ledger 证据 token（T-number）必须出现在 TB 文件中。verification_matrix.md 格式已规定。 |
| RSP3a：数据通路 done/clear | `references/rtl/rtl-structural-purity.md` | 数据通路 done/clear 必须使用命名的 `*_clr_en`/`*_set_en`，不得使用 `cstate == S_DONE`。 |
| 仅注释合规 | `references/rtl/rtl-structural-purity.md` | 注释声称合规 + 代码违反 = E 级发现。需豁免格式。 |
| 终结门控 | `SKILL.md` Step 10 | 新增 `sim_log_gate.py`、`project_artifact_gate.py`、`rtl_style_check.py` 为必需终结门控。 |
| Eval 扩展 | `evals/evals.json` | 新增 eval 76-80，覆盖超时假通过、ledger 证据交叉引用、缺失 verification_matrix、RSP3 注释声明、N1 ANSI 解析器。 |
| Benchmark | `evals/benchmark.json` | 将 eval 76-80 加入 sim_false_pass_prevention、verification_closure、fsm_datapath_purity、tool_driven_verification 维度。 |
| Codex 审计修复：日志编码 | `scripts/sim_log_gate.py` | 按字节读取并规范化 UTF-8/UTF-16/NUL 混编的 PowerShell 日志，确保真正的 TIMEOUT 日志被拒绝。 |
| Codex 审计修复：No-SPEC 检测 | `scripts/project_artifact_gate.py` | `No user spec provided` 不再视为存在用户 SPEC 的肯定证据。 |

### 验证

| 检查项 | 结果 |
|------|:----:|
| py_compile 全部 3 个脚本 | PASS |
| json.tool evals.json / benchmark.json | PASS |
| eval_benchmark_check.py | PASS（33 维度，80 条 eval） |
| `rtl_style_check.py` 对 `nvme-io-path/tb/tb_nvme_io.v` | TB_TIMEOUT_FATAL1(E)、TB_COMPLETION_ONLY1(E)、TB_SIDEBAND1(W)、TB_XZ1(W) |
| `rtl_style_check.py` 对 `nvme-io-path/rtl/axi_write_master.v` | RSP3(E) 附注释声明升级 |
| `sim_log_gate.py` 对 TIMEOUT 日志 | REJECT（TIMEOUT，缺失 ALL_TESTS_PASS，缺失 SIMULATION_DONE） |
| `sim_log_gate.py` 对 PASS 日志 | PASS |
| `project_artifact_gate.py` 对 nvme-io-path | REJECT（缺失 verification_matrix.md，缺失 T3/T10 证据） |
| UTF-16/PowerShell TIMEOUT 日志 | REJECT，明确 TIMEOUT 标记 |

---

记录 digital-front-end-skill 的迭代历史：每次项目 review 发现的 skill 缺陷、改进措施、当前状态。

---

## 2026-06-02 — NVMe PRP 角色纠偏 + RTL_MULTI_DRIVER1 + 假通过审计强制

### 触发背景

最新 nvme-io-path 低约束产物暴露：PRP2 list pointer 误计为数据页 (`(1+1+64)*PAGE_SIZE` 反模式)；parser parsed_valid 被多 always 块驱动；TB 无界 wait；false-pass audit 沦为空 $display。

### 改动

| 改动 | 位置 | 说明 |
|------|------|------|
| PRP2 role 明确 | nvme-guidelines.md §11.3a | PRP2=data page vs PRP2=list pointer 互斥；list pointer 不是数据页；`total_data_pages = 1 + N_list_entries`；16KB/4页 example + AWADDR 检查 |
| S3/S4 修正 | spec-consistency-gate.md | PRP2 role 区分；chain pointer 不计入 data pages；`(1+1+N)` 反模式标注 |
| RTL_MULTI_DRIVER1 | rtl_style_check.py | 同一 reg/wire 在多个 always 块赋值 → E 级别报错 |
| TB_FPASS_AUDIT1 | rtl_style_check.py | 只有 $display audit/false-pass 文本无 error tracking → W 级别 false-pass 审计风险 |
| CLAUDE.md | CLAUDE.md | 提示执行者输出需独立审计 + 已知回归检查路径纠正 |

### 验证

| 检查 | 结果 |
|------|:----:|
| py_compile | PASS |
| skill_static_check | PASS |
| json.tool evals/benchmark | PASS |
| eval_benchmark_check | PASS (33 dims, 71 evals) |
| rtl_style_check on nvme-io-path | RTL_MULTI_DRIVER1(1E) + RSP3(3W) 全部命中 |

---

## 2026-06-02 — SPEC 一致性门控 + TB 可靠性门控 + NVMe 精度修正

### 触发背景

nvme-io-path tb_clean.v review 发现：unbounded while 无 timeout、cap_cnt 无 expected_beats 对照、m_b_resp 接但未检、cpl_status 未健壮验证。同时 SPEC 中 NLB byte count 公式和 PRP page count 公式存在潜在不一致风险。claim ledger 中的 Normative claim 缺少版本/章节/行号 trace。

### 改动

| 改动 | 位置 | 说明 |
|------|------|------|
| **SPEC Consistency Gate** | SKILL.md Step 1.7 + new `references/workflow/spec-consistency-gate.md` | 硬公式验证 (S1-S6, A1-A3, G1-G2) + 4 类 failure classification |
| **TB Reliability Gate** | `simulation-loop.md` TBR1-TBR5 | 无界 wait 保护、PASS 证据要求、双 scoreboard、cap_cnt vs expected、response 消费 |
| **NVMe Accuracy Correction** | `nvme-guidelines.md` §15 | NLB byte count、PRP1 offset、PRP list chain/waiver、completion/error 传播、AXI response 消费 |
| **Claim Ledger 强化** | `protocol-claim-ledger.md` | Normative 必须有版本+章节+行号；Unverified 不得写 must/shall；waiver 必须 multi-location 同步 |
| **TB_WAIT1** | `rtl_style_check.py` | 无界 while/wait 无 cycle timeout/$fatal |
| **TB_CAPCNT1** | `rtl_style_check.py` | cap_cnt 无 expected_beats 对照 |
| **TB_STATUS1** | `rtl_style_check.py` | cpl_status 连接但从未比较 |
| **PRESP1 强化** | `rtl_style_check.py` | message 要求 propagation 或 waiver |
| **Eval 71** | `evals/evals.json` | SPEC consistency + TB reliability + response propagation 综合审查 |
| **spec_tb_reliability** | `evals/benchmark.json` | 新 benchmark 维度 |

### 验证

| 检查 | 结果 |
|------|:----:|
| skill_static_check.py | PASS (447 lines) |
| py_compile rtl_style_check.py | PASS |
| json.tool evals/benchmark | PASS |
| eval_benchmark_check.py | PASS (33 dimensions, 71 evals) |
| rtl_style_check on nvme-io-path | TB_WAIT1(4) + TB_CAPCNT1(2) + TB_STATUS1(2) + TB_FPASS1(3) + PRESP1(1) all hit |

### 审计补漏

- 修复新的引用错误：`16'h0F` 是十进制 15，不是 21。
- 收紧 PRP list 措辞：若需要下一个 list page，当前页的最后一个 entry 是 chain pointer，不是 data PRP。
- 扩展 `TB_WAIT1` 以捕获多行循环，如 `while (!_done) begin ... @(posedge clk); ... end`。
- 扩展 `TB_CAPCNT1` 以捕获 `cap_cnt <= cap_cnt + 1` / `cap_cnt = cap_cnt + 1`，不仅限于 `cap_cnt++`。

---

## 2026-06-02 — 工作流路由 + 验证排序 + 发布门控 + 协议声明账本 + SKILL.md 余量

### 触发背景

SKILL.md 正好 500 行，维护余量为 0。Step 8b 同时包含 functional test 规划和执行，与 Step 9 职责冲突。L2 sub-agent 只有 Decision Gate 没有执行前 Release Gate。协议 claim 缺少结构化追踪。Review/debug 模式被迫走完整 RTL 生成流程。

### 改动

| 改动 | 位置 | 说明 |
|------|------|------|
| **Task Mode Routing** | SKILL.md + new `references/workflow/task-mode-routing.md` | 6 种模式路由：design/review/debug/protocol-audit/skill-maintenance/L2-orchestration。Review/debug 不走完整 RTL 流程 |
| **Step 8b/9 职责重排** | SKILL.md | 8b = 验证计划（golden strategy + scoreboard plan + false-pass audit plan）。9 = TB 生成 + 仿真执行 + false-pass audit |
| **Step 1.6 Release Gate** | SKILL.md | L2 委派后必须通过：contracts frozen、roles assigned、acceptance commands defined、integration reviewer、prompt 包含 RSP1-RSP7 + authority labels |
| **弱词替换** | SKILL.md Step 1.5 | "consider further decomposition" → "must split further OR assign dedicated owner OR write waiver" |
| **Protocol Claim Ledger** | new `references/timing/protocol-claim-ledger.md` | 结构化表格：claim/label/source/section/applied-in/evidence。每个 must/shall/violation 必须入账 |
| **SKILL.md 瘦身** | SKILL.md | 500 → 443 行 (-57)。冗长说明下沉到 references |
| **Reference index 更新** | reference-index.md | 新增 task-mode-routing + protocol-claim-ledger 索引 |
| **CLAUDE.md** | CLAUDE.md | Release Gate + SKILL.md headroom 维护规则 |
| **Eval 69, 70** | evals/evals.json | mode routing + release gate; claim ledger + verification sequencing |
| **Benchmark 维度** | evals/benchmark.json | workflow_routing_release_gate + protocol_claim_ledger |

### 验证

| 检查 | 结果 |
|------|:----:|
| skill_static_check.py | PASS (443 lines) |
| py_compile rtl_style_check.py | PASS |
| json.tool evals/benchmark | PASS |
| eval_benchmark_check.py | PASS (32 dimensions, 70 evals) |
| git diff --check | clean (LF/CRLF only) |

---

## 2026-06-02 — 委派决策门控：L2 强制委派决策

### 触发背景

之前 L2 表格的 Agent strategy 为 "Consider decomposing into 2-3 sub-agents" -- 弱提示，在多轮 review (CDMA R1-R6, NVMe Phase 3) 中从未真正触发 sub-agent 委派。L2 项目持续由 single agent 执行，导致超时/遗漏/质量下降。

### 改动

| 改动 | 位置 | 说明 |
|------|------|------|
| L0/L1/L2 表格 Agent strategy 重写 | SKILL.md Step 1 | L2 从 "Consider" 改为 "Mandatory delegation decision" |
| Step 1.1 Delegation Decision Gate | SKILL.md (新增) | 7 个 hard triggers; yes/no 强制; waiver 模板 |
| sub-agent-delegation.md 全面重写 | references/architecture/ | Decision Matrix + Record 模板 + 5 种推荐 roles + contract-freeze 前置 + acceptance commands |
| eval 68 | evals/evals.json | L2 AXI/NVMe 委派决策任务 |
| delegation_decision_gate 维度 | evals/benchmark.json | 新 benchmark 维度 |
| CLAUDE.md 更新 | CLAUDE.md | 追加 delegation decision gate 为 top-priority |

### 核心规则

- L0: 禁止委派（除非用户要求 parallel review）
- L1: 默认不委派（除非 TB/review 完全独立 per-module）
- L2: 强制 decision record (yes/no)。7 个 hard triggers 触发 yes；不委派写 waiver。
- Sub-agent 执行不得早于 per-module interface contract freeze

---

## 2026-06-02 — RTL 结构纯度门禁 + FSM 静态检查 + NVMe 协议完备性 + 双 Scoreboard

### 触发背景

nvme-io-path review + CDMA R1-R6 反复出现 FSM-datapath 混写，是最高频且最难在仿真中暴露的结构性缺陷。同一 session 也发现 NVMe PRP offset/list/chain/alignment/response 验证盲区。

### 改动内容

| 改动 | 位置 | 说明 |
|------|------|------|
| **RTL Structural Purity Gate** | SKILL.md Step 6a (新增) | 7 步 gate (RSP1-RSP7) 在 RTL 编写前拦截 FSM/datapath 混写 |
| **Step 7 强化** | SKILL.md | 强制阅读 rtl-structural-purity.md + rtl-coding-standards.md |
| **Step 8 增加 FSM Purity 类别** | SKILL.md | self-review checklist 新增 FSM-Datapath Purity 7 项 (RSP1-RSP7) |
| **Step 10 纯度复检** | SKILL.md | finalization 增加 purity gate re-check |
| **rtl-structural-purity.md** | NEW references/rtl/ | 纯二段式 FSM 模板、三大 block type 边界、禁止示例与修正、waiver 规则 |
| **C22-C26** | rtl-coding-standards.md §2.5 | M 级硬规则：FSM seq 单赋值、FSM comb 单比特输出、datapath 无 cstate、datapath 归属清单 |
| **C27-C28** | rtl-coding-standards.md §2.6 | M/S 级 accepted-operation discipline |
| **C29-C31** | rtl-coding-standards.md §2.7 | S/M 级 unit/width discipline |
| **C32** | rtl-coding-standards.md §2.8 | M 级 no fake parameterization |
| **RTL_FSM1** | rtl_style_check.py | FSM combinational block 中出现多比特 `=` 赋值检测 |
| **RTL_FSM2** | rtl_style_check.py | Datapath sequential block 中出现 `case(cstate)` 或 `S_*` 检测 |
| **RTL_FSM3** | rtl_style_check.py | FSM sequential block 中 cstate `<= nstate` 之外的数据通路寄存器检测 |
| **协议权威审计强化** | protocol-authority-audit.md | 增加 step 6：must/shall 必须标注 label + 验证 section number 准确性 |
| **NVMe §14.7-14.10** | nvme-guidelines.md | PRP offset/boundary/alignment/chain/BRESP/opcode/nsid/dual-scoreboard 完备检查项 |
| **双 Scoreboard** | golden-reference-guide.md | L2 DMA/NVMe 必须同时有 payload + transaction-shape 两个独立 scoreboard |
| **全局 error counter** | golden-reference-guide.md + simulation-loop.md | L1/L2 必须 total_error_cnt，禁止 per-test 局部 counter |
| **Backpressure 最小测试** | golden-reference-guide.md + simulation-loop.md | 至少一个 WREADY 回压 + NVM 多周期延迟测试 |
| **Eval 66** | evals/evals.json | FSM-datapath purity 违规识别任务 |
| **Eval 67** | evals/evals.json | NVMe PRP completeness (offset/list/chain/alignment/scoreboard) 审查任务 |
| **fsm_datapath_purity + nvme_prp_completeness** | evals/benchmark.json | 两个新 benchmark 维度 |

### 修复

- SKILL.md "**If the specification..." 未闭合粗体修复
- SKILL.md NVMe/DMA 段落规范化

### 验证

| 检查 | 结果 |
|------|:----:|
| py_compile rtl_style_check.py | PASS |
| json.tool evals.json | PASS |
| json.tool benchmark.json | PASS |
| skill_static_check.py | PASS (SKILL.md 487 lines, under 500) |
| eval_benchmark_check.py | PASS (67 evals, new fsm_datapath_purity + nvme_prp_completeness dimensions covered) |
| rtl_style_check on nvme-io-path prp_walker | PASS as detector: 19 expected warnings (RTL_PRP1 + RTL_STRUCTURAL_PURITY_RSP2/RSP3) |

---

## 2026-06-02 — False-Pass 防御体系：仿真日志审计 + NVMe 多页数据连续性 + PRP 缓冲区匹配

### 触发项目

nvme-io-path（NVMe IO Datapath）review 发现 4 类 false-pass 漏洞：

| 类型 | 证据 | 影响 |
|------|------|------|
| **测试台 false-pass** | T2/T3 数据 mismatch 只用 `$display`，未增加 `error_cnt`；log 显示 `ALL_TESTS_PASS` | 错误数据被标记为通过 |
| **NVM 源偏移每页重置** | `nvme_read_engine.v` 中 `nvm_offset_q <= 32'b0` on page_valid，导致多页读取重复第一页数据 | 多页传输数据 silently corrupt |
| **PRP list buffer 不匹配** | `LIST_ENTRIES=512` 但 `list_buf [0:63]` (64 entries)，`ARLEN=63` | 无法容纳完整 PRP list |
| **未用 protocol 输入** | `axi_b_resp_i` 已连接但从未检查，`cmd_opcode_i`/`cmd_nsid_i` 未验证 | 协议错误和路由错误被 silently dropped |

### 改动内容

| 改动 | 位置 | 说明 |
|------|------|------|
| **Step 8b 仿真日志审计** | SKILL.md | 新增 false-pass 防御 checklist：扫描 `exp`/`mismatch`/`xxxx` 无 error tracking 时判 FAIL |
| **Step 9 日志审计强制** | SKILL.md | `ALL_TESTS_PASS` 后必须先做 Step 8b 审计才能声称通过 |
| **Step 10 最终化防护** | SKILL.md | 新增 4 项 false-pass finalization 检查 |
| **L2 NVMe/DMA 合同要求** | SKILL.md | 全局源字节游标不能每页重置；目标 vs 源游标分离；多页测试用非均匀数据 |
| **False-Pass 日志分类器** | `simulation-loop.md` | 分类表中新增 Priority 0 FALSE_PASS；fallback 分类器扩展 `exp`/`expected`/`xxxx` |
| **NVMe 多页连续性** | `golden-reference-guide.md` | DMA 扩展项 8：NVM source offset = global cursor，不随 PRP 页重置 |
| **NVMe PRP 数据路径检查项** | `nvme-guidelines.md` | 新增 §14：6 个子章节 (14.1-14.6) 覆盖 source address 连续性、PRP buffer 匹配、W 通道数据可用性、testbench false-pass 模式、未用输入、最小多页测试 |
| **TB_FPASS1 checker** | `rtl_style_check.py` | `$display.*exp` 无 `error_cnt++` 检测 |
| **RTL_NVM1 checker** | `rtl_style_check.py` | NVM offset 在 page_valid 时清 0 + nvm_addr = slba + offset 检测 |
| **RTL_PRP1 checker** | `rtl_style_check.py` | LIST_ENTRIES ≠ list_buf depth / ARLEN mismatch 检测 |
| **RTL_WEMPTY1 checker** | `rtl_style_check.py` | WVALID set on AW handshake 无 fifo_empty/have_next 检测 |
| **Eval 65** | `evals/evals.json` | NVMe multi-page PRP false-pass review 任务 |
| **nvme_dma_false_pass 维度** | `evals/benchmark.json` | 新 benchmark 维度，eval 65 覆盖 |

### 验证结果

| 检查 | 结果 |
|------|:----:|
| `py_compile rtl_style_check.py` | PASS |
| `json.tool evals.json` | PASS |
| `json.tool benchmark.json` | PASS |
| `skill_static_check.py` | PASS |
| `eval_benchmark_check.py` | PASS |
| rtl_style_check 扫 nvme-io-path RTL | Warning 符合预期 (见下方) |

### 残余风险

- `rtl_style_check.py` 的 RTL_WEMPTY1 和 RTL_NVM1 是启发式检测，可能漏报复杂 case（如 offset reset 在间接位置）
- 新 checker 尚未在大规模 RTL 上做误报率测试
- 仿真日志审计依赖 agent 实际执行 Step 8b checklist，不能只用 skill 文本命令保证

---

## 2026-06-02 — 协议权威蒸馏纠偏：P12/WVALID + NVMe 队列/PRP + DMA 验证盲区

### 触发背景

NVMe IO datapath review 发现：P12 把 AXI continuous WVALID 实现策略误写成 IHI0022 协议硬规则，导致 reference 可能出现“声称遵循权威手册，但实际规则不准确”的问题。

### 修复内容

| 改进 | 说明 |
|------|------|
| Protocol authority labels | `protocol-authority-map.md` 增加 Normative / Project policy / Conservative pattern / Heuristic / Unverified 分类 |
| P12 重写 | AXI WVALID 改为 per-beat hold 是规范要求；continuous WVALID through WLAST 是本地策略 |
| DMA scoreboard 扩展 | 数据比对之外，强制检查 transaction count、address、AWLEN/ARLEN、WLAST/RLAST、WSTRB、response、completion ordering |
| NVMe reference 修正 | QSIZE=entries-1、queue pointer modulo wrap、CQ Phase Tag 不等于 2*depth 指针、PRP List chain pointer 条件 |
| 静态检查增强 | 增加 AXI burst 8-bit 截断、未用 resp 输入、ready 恒 1 + FIFO full 丢数、valid 绑 0 stub、start 同拍旧寄存器读取启发式 |
| Eval 覆盖 | 新增 id 64，专门防止 agent 再把 AXI WVALID 连续 burst 策略误称为规范 |

### 新增/更新文件

- `references/timing/protocol-authority-audit.md`
- `references/timing/protocol-authority-map.md`
- `references/axi-dma/axi-dma-channel-guidelines.md`
- `references/debug/bug-pattern-library.md`
- `references/verification/self-review-checklist.md`
- `references/verification/axi-verification.md`
- `references/verification/golden-reference-guide.md`
- `references/bus/nvme-guidelines.md`
- `scripts/rtl_style_check.py`
- `evals/evals.json`, `evals/benchmark.json`

---

## 2026-06-01 — 工作流瘦身 + SPEC 重写 + S1-S6 全部闭环

### 工作流从 14 步精简到 11 步

删除/合并了 3 个冗余步骤 + 修复 7 处残留：

| 改动 | 说明 |
|------|------|
| 删除 Step 12 | 子代理委托已在 Step 1.5 触发，Step 12 只剩两行引用 |
| 合并 Step 11 | "验证时序" 已由 Step 8 signal type cross-check 覆盖 |
| 合并 Step 10 | "审查与迭代" 与 Step 9 迭代处理重叠，精华合入 Step 10 "Finalize" |
| 修复 7 处残留 | Step 1 表格引用 Step 12、流程图引用 Step 12、Step 1.5 委托段落重复、迭代图引用 Step 8d、Step 9 冗余 yosys 行 |

**工作流结构（11 步）：**
```
1. Parse → 1.5 L2 Fork → 2. Contract → 2a. P4+P6 → 3. Freeze
→ 4. State → 5. Trace → 5a. P1+P2 → 6. Pattern → 7. RTL
→ 7b. pre_sim_check → 8. Self-review → 8b. Functional
→ 8c. P3+P5a → 9. Sim Loop → 10. Finalize
```

### SPEC.md 重写

NVMe IO datapath 项目 SPEC：从 386 行技能指令型 → 250 行纯功能型。删除所有 NBA 陷阱、编码规范、工具链命令、bug 引用。只描述模块接口 + 时序 + 行为 + 测试用例。确保新 agent 交付物能真实反映 skill 有效性。

### S1-S6 全部闭环

本次会话中 6 项改进全部落地：

| # | 改进 | 最终状态 |
|:---:|------|:---:|
| S1 | yosys 可强制 | ✅ `pre_sim_check.sh` 解析 yosys 输出，latch 计数 > 0 → exit 1 |
| S2 | rtl_style_check 强制运行 | ✅ 集成到 Step 7b 的 `pre_sim_check.sh --all` |
| S3 | NBA 预检具体示例 | ✅ `nba-ordering-guide.md` L3 含 NVMe Phase 3 的具体 broken/fix 代码 |
| S4 | 合同-RTL 单位交叉检查 | ✅ `timing-contract-template.md` 新增 Signal units 表 + 转换规则 |
| S5 | 统一 pre_sim_check.sh | ✅ `scripts/pre_sim_check.sh` — yosys + style + compile 三合一 |
| S6 | 每模块独立编译检查 | ✅ Step 7 standalone compile gate + `pre_sim_check.sh --compile` |

### SKILL.md 行数

~360 / 500 行（净减 10 行：+W1-W6 增加, -Step 10/11/12 瘦身）

---

## 2026-06-01 — NVMe Phase 3 完整复盘：18 bugs + 6 个可操作 skill 改进

### 复盘核心结论

18 个 bug 全部是基础性错误——不需要 NVMe 领域知识。NBA 时序（33%）、代码完整性（28%）、架构设计（17%）覆盖了 78%。Skill 的问题不是缺知识，而是已有的知识没有被强制执行。

### 按预防阶段分类

| 阶段 | Bug 数 | 最大聚类 |
|------|:---:|------|
| Step 2 (Contract) | 2 | 架构设计错误 |
| Step 7 (RTL gen) | 6 | NBA + 基本 Verilog |
| Step 7b (Yosys) | 3 | 若运行可被捕获 |
| Step 8 (Self-rev) | 7 | 结构性但被漏掉 |

### 6 个可操作改进

| # | 改进 | 状态 |
|:---:|------|:---:|
| S1 | yosys 可强制（输出解析脚本） | 待实施 |
| S2 | rtl_style_check 在 Step 7b 强制运行 | ✅ 已实施 |
| S3 | NBA 预检需具体 NVMe 示例 | ✅ 已实施 |
| S4 | 合同-RTL 交叉检查扩展到物理单位 | 待实施 |
| S5 | 统一 pre_sim_check.sh | 待实施 |
| S6 | 每个模块独立编译后再集成 | 待实施 |

详见 `memory/nvme_phase3_retrospective.md`。

### SKILL.md 行数

~370 / 500 行

---

## 2026-06-01 — 工作流结构优化 + S1-S6 工具链落地（W1-W6 + 4 tooling items）

### 改动

**工作流结构（W1-W6）：**

| # | 改动 | 说明 |
|:---:|------|------|
| W1+W2 | Step 1 新增 L2 分叉（Step 1.5） | L2 子系统强制先做分解 + 每模块接口合约，然后逐模块走 Step 2-8。子代理委托从 Step 12 移到这里 |
| W3+S6 | Step 7 新增每模块独立编译门 | 每个 .v 文件需通过 `iverilog -g2012 -o /dev/null` standalone 编译。防止 NVMe B14（FSM 缺失）类问题 |
| W4 | Step 6 加强制 pattern 阅读 | 和 Step 7 的 coding standards 阅读同级——"不依赖记忆选模板" |
| W5 | Step 11 合并到 Step 8 | Signal type cross-check 已覆盖合同时序验证。删除独立 Step 11 避免幽灵步骤 |
| W6 | Step 9 新增迭代状态机 | 编译失败→Step 7, 仿真失败→8d→8→7, PASS→done。显式建模真实开发循环 |

**工具链（S1-S6 剩余 4 项）：**

| # | 改动 | 文件 |
|:---:|------|------|
| S1+S5 | `scripts/pre_sim_check.sh` 新建 | 统一预仿真门：yosys + rtl_style_check + standalone compile。单一命令，exit 0 才能进 Step 8 |
| S2 | rtl_style_check 集成 | Step 7b 强制运行（上次 commit 已添加） |
| S3 | NBA 预检示例 | nba-ordering-guide.md L3 已有具体 NVMe 示例 |
| S4 | timing-contract-template 新增单位列 | 每个多比特端口记录物理单位（bytes/beats/addr/offset/count/len）。防 B18 byte*8 混淆 |
| S6 | 独立编译检查 | 含在 Step 7（W3）和 pre_sim_check.sh 中 |

### S1-S6 全部落地

```
S1  ✅  pre_sim_check.sh (yosys 输出解析 + latch 计数)
S2  ✅  rtl_style_check.py 已集成到 Step 7b
S3  ✅  nba-ordering-guide.md L3 已添加 NVMe 示例
S4  ✅  timing-contract-template.md 新增 Signal units
S5  ✅  pre_sim_check.sh 统一入口
S6  ✅  Step 7 standalone compile + pre_sim_check.sh --compile
```

### SKILL.md 行数

~370 / 500 行（+23：L2 fork + 迭代状态机 + pre_sim_check 引用）

---

## 2026-06-01 — NVMe Phase 3 + 编码规范整合 + 流程缺陷修复 + NBA 预防策略

### NVMe Phase 3

7 模块 ~1900 行 RTL，ALL_TESTS_PASS。13 bugs 修复，其中 6 个是 NBA 时序问题。关键架构纠正：AW 与 FIFO count 解耦，FIFO 深度从 8192 降到 64。

### 编码规范整合

用户编码标准落实为 skill 首要规范（`rtl-coding-standards.md` 新建，C1-C20）：
- `naming-guidelines.md` 重写：`cstate`/`nstate`（两段式 FSM），`_r` 打拍后缀，`inst_` 前缀
- `fsm-examples.md` 51 处命名更新
- C19 (M): explicit else in sequential blocks
- C20 (S): group registers by function

### 流程缺陷修复 (G1-G6)

| Gap | 修复 | 文件 |
|-----|------|------|
| G1: 无 NBA 检查 | NBA Ordering Hazards (6 项) | self-review-checklist.md |
| G2: 无模块内耦合检查 | P4 Intra-Module Independence | SKILL.md Step 2a |
| G3: 无 always 块规模告警 | C5/C6: >8 regs or >50 lines → split | engineering-intuition-checklist.md |
| G4: 无前置综合 | Step 7b: yosys before self-review | SKILL.md |
| G5: 无诊断方法论 | Step 3.5: structured NBA diagnosis | simulation-loop.md |
| G6: 规范未强制执行 | Step 7: mandatory read of standards | SKILL.md |

### NBA 问题诊断与修复

NVMe Phase 3 的 13 bugs 中 6 个（46%）是 NBA 时序问题——在 G1/G5 已经入库后仍然高发。根因分析：

1. **碎片化：** NBA 知识分散在 6 个文件，没有统一的入口
2. **检查点错位：** G1 在 Step 8（仿真前检查），G5 在 Step 9（仿真失败后诊断）——但 NBA 错误发生在 Step 7（写 RTL 的那一刻）

**修复：** Step 7 新增 **NBA ordering pre-check**（所有 level 强制，不是可选项）。在写每个 `always @(posedge clk)` 块之前，agent 必须回答 3 个问题：
1. 谁读我的输出？（跨块 NBA → 不确定顺序）
2. 我读的寄存器刚被赋过值吗？（同块依赖 → 旧值）
3. 有组合逻辑消费我的输出吗？（active 区域先评估 → pre-NBA 值）

配合已有的 `nba-ordering-guide.md`（266 行，3 层 6 陷阱），形成从 Step 7（预防）→ Step 8（检测）→ Step 9 Phase 4（诊断）的完整 NBA 防护链。

### SKILL.md 行数

~355 / 500 行（+17：NBA pre-check + dev log 引用）

---

## 2026-06-01 — 开发日志标准化 + NBA 预防链

### 开发日志模板

新建 `references/project/development-log-template.md` — L1/L2 项目强制使用。标准化结构：
- **Bug Tracking Table：** 症状、发现检查点、违反原则、根因、修复、迭代编号——"Found at" 列是 skill 改进最重要的数据
- **Simulation Iteration Log：** 每次迭代的命令 + 输出 + 修复动作
- **Principle Review Findings：** 每个检查点（2a/5a/8c）的发现
- **Design Decision Log：** 每个非显然架构选择 + 替代方案 + 选择理由
- **Residual Risk Register：** 未修复的已知风险 + 不修复的理由

集成到 SKILL.md Step 7（强制要求）和 reference-index.md。

### NBA 预防链

Step 7 新增 NBA ordering pre-check — 写每个 `always @(posedge clk)` 之前回答 3 问。形成 Step 7（预防）→ Step 8（检测）→ Step 9 Phase 4（诊断）的完整防护链。

---

## 2026-06-01 — NVMe Phase 2 规范学习 + nvme-guidelines.md 扩展（NVM I/O 命令集 + PRP 遍历）

### 背景

NVMe Phase 2 需要 NVM Read/Write I/O 命令和 PRP 数据搬运能力。Phase 1 的 nvme-guidelines.md（298 行）仅覆盖 Admin 控制路径。规范也从 1.4c 升级到 2.3。

### 学习的规范

| 规范 | 版本 | 规模 |
|------|------|:---:|
| NVM Express Base Specification | 2.3 (2025-08-01) | ~700 页 |
| NVM Express NVM Command Set Specification | 1.2 (2025-08-01) | ~200 页 |

### 改动文件

| 文件 | 改动 | 行数变化 |
|------|------|:---:|
| `references/bus/nvme-guidelines.md` | 新增 §10-§14：NVM I/O 命令集、PRP 遍历算法、数据搬运流程、I/O 命令生命周期、扩展设计约束。更新 Authority 引用到 2.3/1.2。 | 298→683 (+385) |
| `references/reference-index.md` | 新增 NVMe 索引条目 | +1 |

### 新增 Section 详情

**§10 — NVM I/O Command Set (Read/Write/Flush):**
- Read (02h), Write (01h), Flush (00h) opcodes
- SQE DW10-DW15 精确字段映射：SLBA[63:0], NLB[15:0] (0-based), FUA, LR, PRINFO, CETYPE, STC, DTYPE/DSPEC
- 关键设计约束：NLB=0 意味着 1 个逻辑块（常见 off-by-one 陷阱）

**§11 — PRP Traversal Algorithm:**
- 64-bit PRP Entry 格式：Page Base Address + Offset
- PRP2 三种角色判定：Reserved / Second Page / PRP List Pointer
- PRP List 链式遍历算法（含硬件 Verilog 伪代码）
- 边界判定公式：`transfer_bytes <= first_page_capacity` vs `<= first_page_capacity + page_size`
- PRP 错误处理：Offset Invalid, Data Transfer Error

**§12 — I/O Data Transfer Flow:**
- Read flow (5 阶段)：Command Fetch → PRP Walk → NVM Read → AXI W to Host → CQE Post
- Write flow (4 阶段)：Command Fetch → PRP Walk → AXI R from Host → NVM Write → CQE Post
- Flush flow (3 阶段)：Command Fetch → NVM Commit → CQE Post
- AXI 事务映射表

**§13 — I/O Command Lifecycle:**
- 完整 Doorbell→CQE 流程（8 步）
- 多命令并发模型：控制器可乱序执行，CID+SQID 唯一标识
- Outstanding Command Tracker 设计模板（14 个状态字段）

**§14 — Updated Design Constraints:**
- P1-P6 原则的 I/O 数据通路扩展：PRP FSM 安全规则、读写通道独立、Outstanding tracker 复位、CQE 发布时序

### 沉淀的设计规则

| # | 规则 | 来源 |
|---|------|------|
| 1 | NLB 是 0-based（NLB=0 → 1 block） | NVM Cmd Set §3.3.1 |
| 2 | PRP1.offset 仅第一页有效，后续页 offset=0 | Base Spec §4.3 |
| 3 | PRP List 条目必须页对齐（offset=0），末条可指向下一个 List 页 | Base Spec §4.3 |
| 4 | PRP2 角色由 transfer_bytes 和 page_size 判定 | Base Spec §4.3 (derived algorithm) |
| 5 | I/O 命令可乱序执行，CQE 发布顺序无保证 | Base Spec §2.1 |
| 6 | Read 和 Write 到同一 LBA 无排序保证 | Base Spec §3.3.2.1.1 |
| 7 | FUA=1 要求非易失提交完成后才能发 CQE | NVM Cmd Set §3.3.1/§3.3.4 |
| 8 | CDW0.PSDT 选择 PRP(00b) 或 SGL(01b/10b)，单命令不可混用 | Base Spec Figure 91 |
| 9 | PRP List 页内条目必须紧凑排列（packed from entry 0） | Base Spec §4.3 |
| 10 | Flush 命令无数据搬运，仅 NSID + FB field | Base Spec §7.2 |

### SKILL.md 行数

~345 / 500 行（无变化——改动在 reference 文件）

---

## 2026-05-31 — 系统架构 Phase 3：Split-Merge Pipeline 验证项目 + 3 条模式修正

### 验证项目

Split-merge pipeline with feedback completion（AXI-Stream 2 级管道 + 分离器 + joiner + beat counter）。5/5 ALL_TESTS_PASS。

| 测试 | 验证内容 |
|------|---------|
| T1 单 beat | pkt_done sticky flag + 数据完整性 |
| T2 多 beat | 3 beats Golden Reference 数据比对 |
| T3 背靠背 | pkt_done 在包间正确取消断言 |
| T4 反压 | stall/release — 数据在反压下存活 |
| T5 Split-Merge 时序 | pkt_done 在管道延迟后才断言 |

### 验证中发现的 3 条可沉淀模式

1. **管道数据移动的 `valid_q <= valid_i` 盲区：** 标准单级模板直接串联为多级时，反压下会静默丢弃数据。修正为 `sN_to_next \|\| !sN_valid_q` 门控。已写入 `pipeline-design-patterns.md` §1 Common Errors + Corrected Multi-Stage Pattern。

2. **固定长度对齐延迟线反模式：** 移位寄存器用于跨路径时序对齐时，不受管道 stall 信号约束，反压下有效位丢失。直接观察管道输出 TLAST 更健壮。已写入 `pipeline-design-patterns.md` §4 Common Errors + Anti-pattern explained。

3. **合约-RTL 信号分类断裂：** Contract 约定 `pkt_done_o` 为 level flag，RTL 实现为 `assign pkt_done_o = (state_q == S_DONE)` 单周期脉冲。Step 5a P1 审查与 Step 8 RTL 验证之间无回验环节。新增 **Signal Type Cross-Check**（pulse/level/registered 逐类验证），写入 `SKILL.md` Step 8 + `self-review-checklist.md`。

### 术语修正

"Fork-Join" 更名为 "Split-Merge"——避免与 Verilog `fork...join` 行为语句混淆。6 个文件 11 处修改。

### 改动文件

| 文件 | 改动 |
|------|------|
| `references/architecture/pipeline-design-patterns.md` | §1: 新增 Corrected Multi-Stage Pattern + Common Error；§4: Fork-Join→Split-Merge + 新增 Common Errors（对齐延迟反模式 + pulse 完成反模式） |
| `SKILL.md` Step 8 | 新增 Signal Type Cross-Check（mandatory for L1/L2） |
| `references/verification/self-review-checklist.md` | 新增 Signal Type Cross-Check section |
| `projects/pipeline-fork-join/` | 验证项目（RTL + TB + contract），5/5 PASS |
| `SKILL_CHANGELOG.md` | 本条 changelog |

### SKILL.md 行数

~345 / 500 行（+7 行）

---

## 2026-05-31 — 系统架构 Phase 1：权威引用升级（精确章节号 + 来源诚实标注）

### 背景

三个系统架构 reference 文件（pipeline-design-patterns, memory-hierarchy, performance-analysis）的初始版本引用较粗糙——只有教科书章节号（"Ch.12-13"）缺乏精确的 § 定位。按照 skill 已建立的引用标准（icarus-pitfalls、cdc-guidelines 的 Tier 1-5 分层），需要升级。

### 改动文件

| 文件 | 改动 |
|------|------|
| `references/architecture/pipeline-design-patterns.md` | Authority section 重写：Dally & Towles §13.3.1 Eq.13.1, Carloni et al. 2001 (LID formalism), IETF RFC 1242 §3.8, ARM IHI 0022E §A3.5. 新增 pipeline 拓扑分类的 "our synthesis" 声明 + 反压公式的 Forward Register Slice 来源 |
| `references/architecture/memory-hierarchy.md` | Authority section 重写：ARM IHI 0022E §A5.3 → 0022K §A6.3-A6.6, Dally & Towles §18.1-18.6 (arbiters), NVMe 2.0e §4.1/§4.5, Åkesson CCSP 2008, Smith 1978 (prefetch), Arora 2012 (SKID), PCIe 3.0 §2.6 (credit flow control) |
| `references/architecture/performance-analysis.md` | Authority section 重写：H&P 6th ed §1.8/§1.9/App.C (精确到节号), Rabaey §10.3.1 (critical path), Dally & Towles §14.1-14.6 (deadlock), Gregg USE Method 2013 (utilization). 所有推导公式标注为 "derived engineering heuristic" |

### 新增权威引用（本阶段新增 15 个）

| 来源 | 章节 | 应用于 |
|------|------|------|
| Dally & Towles | §13.3.1 Eq.13.1 | Buffer sizing (pipeline + memory) |
| Dally & Towles | §18.1-18.6 | Arbitration strategies (memory) |
| Dally & Towles | §14.1-14.6 | Deadlock/livelock analysis (perf) |
| Carloni et al. 2001 | LID relay station | Valid/ready formalism (pipeline) |
| H&P 6th ed | §1.8, §1.9, App.C | Performance metrics, Amdahl, CPI (perf) |
| Rabaey 2nd ed | §10.3.1 | Critical path timing (perf) |
| Little 1961 | Operations Research 9(3) | Buffer sizing theorem (memory + perf) |
| NVMe 2.0e | §4.1, §4.5 | SQ/CQ model, WRR arbitration (memory) |
| Åkesson et al. 2008 | CCSP | Credit-aware arbitration (memory) |
| Smith 1978 | IEEE Computer 11(12) | Sequential prefetch (memory) |
| Falsafi & Wenisch 2014 | §3.1 | Stride/stream prefetcher (memory) |
| Arora 2012 | SKID/elastic buffer | Pipeline register slice (memory) |
| Cummings SNUG 2002 | — | Async FIFO pointer sync (memory) |
| PCIe 3.0 | §2.6 | Credit-based flow control (memory) |
| Gregg USE Method 2013 | — | Utilization thresholds (perf) |
| IETF RFC 1242 | §3.8 | Cut-through vs store-forward (pipeline) |

### 诚实声明

三个文件中首次明确区分了 "directly stated in source" vs "derived engineering heuristic"：

| 类型 | 示例 |
|------|------|
| **直接引用** | Dally & Towles Eq.13.1 缓冲公式, H&P §1.9 Amdahl's Law, Carloni LID 协议 |
| **工程推导** | "Effective Throughput = Theoretical × Utilization × (1-Overhead)", pipeline 5-pattern 分类法, 利用率 90%/50% 阈值 |

### SKILL.md 行数

~338 / 500 行（无变化）

---

## 2026-05-31 — 系统架构基础：Pipeline + Memory + Performance（三个新 reference）

### 背景

NVMe Phase 1 暴露了 skill 在系统架构层的空白——多模块数据路径路由、跨模块时序合同、吞吐量/延迟分析均无方法论支撑。这三个 topic 是存储/编解码/网络等领域的共享底层能力。

### 新增文件

| 文件 | 行 | 覆盖 |
|------|:---:|------|
| `references/architecture/pipeline-design-patterns.md` | ~350 | 5 种拓扑（feed-forward/feedback/multi-rate/split-merge/cut-through）、反压传播公式、RTL 模板、常见错误 |
| `references/architecture/memory-hierarchy.md` | ~250 | 缓冲深度公式（Little's Law）、SKID buffer、ping-pong、仲裁策略对比、预取策略、WSTRB 对齐 |
| `references/architecture/performance-analysis.md` | ~260 | 吞吐量计算、延迟预算表、反压死锁检测、利用率分析、Little's Law 硬件应用 |

### 验证项目

3 级 AXI-Stream feed-forward pipeline：5/5 beats 数据正确，3 周期延迟，零 mismatch。

### SKILL.md 改动

- `references/architecture/` section 增加 pipeline/memory/performance 索引
- Step 2a (P4+P6) 增加 L2 设计时查阅 pipeline/performance 分析的指引

### SKILL.md 行数

~338 / 500 行

---

## 2026-05-31 — NVMe 领域扩展 Phase 1：Admin Command Engine（首个领域项目）

### 背景

Skill v2 在通用 RTL 设计上成熟后，首次进入 NVMe 存储协议领域。利用现有 AXI/DMA/FIFO/credit 模式基础，从零构建 NVMe 控制器控制路径。

### 项目范围

NVMe Admin Command Engine — 5 模块 L2 子系统，~1492 行：
- BAR0 寄存器文件（CAP/VS/CC/CSTS/AQA/ASQ/ACQ + 门铃检测）
- SQ 抓取引擎（64-byte SQE 抓取 + 解析，基于信用的门铃→抓取流程）
- Admin 命令执行器（Identify/Create CQ/Create SQ）
- CQ 提交引擎（16-byte CQE 组装 + Phase Tag + AXI 写入）
- AXI 适配器（AR/AW/W 通道混排）

### 结果

**2/2 测试通过（控制器使能 + Identify Controller），零编译错误。**

CQE 字段验证全部正确：CID=1, SQID=0, SQHD=1, P=1, Status=0。

### 集成发现（6 个 bug）

| 类别 | Bug | 根因 |
|------|-----|------|
| 集成 | cpl_sqhd 多驱动 | admin_exec 输出 + assign 同时驱动 |
| Testbench | AXI R channel 只发 1 beat | 缺少流式 R channel FSM |
| 架构 | Identify 数据路径未连接 | 合同规定了输出但未规定如何到达 host memory |
| 时序 | cq_data_done 脉冲丢失 | admin_exec DATA_XFER 在 cq_post 到达 WAIT_DATA 之前已完成 |
| 协议 | Phase Tag 复位为 0 | NVMe 规范规定第一个 pass 写 P=1（从 host 初始值 0 toggle） |
| Testbench | CQE bit 索引错误 | DW3[16] vs DW2[16] 混淆 |

### 关键发现

1. **多 agent 子系统集成可行：** 5 个独立 agent 生成的模块零端口不匹配，iverilog 首次编译通过
2. **协议首次接触成功：** NVMe guidelines reference 在无现有 pattern 的情况下提供了足够的上下文
3. **现有 pattern 复用率高：** AXI 通道分离、FWFT、credit counter、two-process FSM 全部正确复用
4. **合同覆盖度不足：** 模块接口匹配，但数据路径路由（Identify data → host memory）和多模块时序合同（cq_data_done vs cpl_valid）缺失

### 新增 Skill 资产

| 文件 | 用途 |
|------|------|
| `references/bus/nvme-guidelines.md` | NVMe 协议 reference |
| `projects/nvme-admin-engine/` | 完整项目（RTL + TB + 报告） |

### 下一步

NVMe Phase 2 — NVM Read/Write I/O 命令 + PRP list 遍历 + 真实数据传输。

---

## 2026-05-31 — Step 8d 压力测试 R10：P3 寄存器初始化 bug（跨原则验证）

### 背景

R9 验证了 8d 对 P2（FSM）bug 有效——但只测了一种原则类型。需要跨原则验证。

### 实验设计

**Bug 类型：** P3（Known Values）——移除 `fifo_count_q` 复位，无 bug 标记
**效果：** fifo_count_q=X → fifo_empty=X → STATUS[2]=X → FSM condition 失败 → FSM 永远不启动

### 结果

| 指标 | R9 (P2) | R10 (P3) |
|------|:---:|:---:|
| Token | 32,290 | 30,459 |
| 耗时 | 44s | 55s |
| 原则映射 | P2 (FSM Safety) | P3 (Known Values) |
| Bug 定位 | ✅ STOP→IDLE 无条件 | ✅ fifo_count_q 无 reset |
| X 传播分析 | — | ✅ fifo_count_q→X→FSM 卡死 |
| 仿真迭代 | 1 | 1 |
| 修复 | 添加 fifo_empty 条件分支 | 添加 reset branch |

### 关键发现

1. **跨原则一致性：** P2 和 P3 两种不同类型的 bug 都通过 8d 正确路由到了正确的原则文档
2. **无标记定位：** RTL 无 `// BUG` 注释，agent 通过 X 传播路径追踪找到根因
3. **文档交叉验证：** Agent 发现原则审查文档将 fifo_count_q 标记为"有复位"，但 RTL 中没有——这是 doc-vs-code 交叉验证
4. **效率一致：** 两次实验均 ~30K tokens / ~50s，零 $display 撒网

### 结论

Step 8d 对 P2 和 P3 两种原则类型的 bug 均有效。P1/P4/P5a 尚未测试，但遵循相同机制——风险低。详见 `projects/test-workflow-round10/EXPERIMENT_REPORT.md`。

### SKILL.md 行数

~338 / 500 行（无文件改动）

---

## 2026-05-31 — Step 8d 压力测试（R9）：原则驱动 debug 闭环验证

### 背景

R5-R8 四轮 A/B 实验中，Step 8d（原则驱动 debug）从未被真实触发——所有项目在 1-4 次仿真迭代内通过。Step 8d 是整个工作流中**唯一未被验证的组件**。

### 实验设计

在 Agent B 的已验证 UART TX RTL（357 行，6/6 测试通过）中注入一个 P2 FSM bug：
- **Bug：** STOP 状态无条件返回 IDLE，忽略 FIFO 中待发送的 byte
- **效果：** 多字节 TX 只发送第一个 byte，剩余卡死在 FIFO 中
- **原则违反：** P2（FSM Safety）——"STOP 应在 FIFO 非空时链接到 START"

给 debug agent：buggy RTL + 原则审查文档（正确的行为记录）+ 失败的仿真输出 + Step 8d 指令。

### 结果

| 指标 | 值 |
|------|-----|
| 故障分类 | ✅ 正确：RTL 功能 bug |
| 原则映射 | ✅ P2 + 交叉 P4（start_q 自清除 + IDLE 无法重入） |
| 原则文档查阅 | ✅ `principle_review_5a.md` P2 Q3 |
| 找到 bug 位置 | ✅ STOP state `state_d = S_IDLE` 无条件 |
| 修复 | ✅ 1 行逻辑修复（fifo_empty 条件判断 + START 链接） |
| 修复后仿真 | ✅ ALL_TESTS_PASS |
| Token 消耗 | 32,290 |
| 耗时 | ~44 秒 |
| $display 撒网 | 0 个 |

### 关键发现

1. **Step 8d 工作流有效。** 原则审查文档作为"信号级地图"让 agent 直接从"多字节失败"跳转到"STOP→START 转换缺失"，零猜测、零 $display 撒网式 debug。

2. **设计特异的文档比通用 pattern 更有价值。** P2 review 记录了 THIS 设计的 STOP→START 转换，不是通用的"检查所有 FSM 转换"——这种特异性是 debug 效率的关键。

3. **跨原则交叉分析自然产生。** Agent 独立发现 start_q 自清除（P4 关注点）与 STOP→IDLE bug 交互导致永久卡死——这正是 8d 设计时预期的多原则推理能力。

4. **8d 缺数据不是因为不需要，而是未触发。** 之前 4 轮实验的零数据是因为项目在触发 8d 之前就通过了。当真实的 FSM bug 存在时，8d 证明了它的价值。

### Keeper Test 裁决

**Step 8d 应保留。** 32K token、44 秒定位真实 FSM bug 的效率是基准。没有 8d 的情况下，同样的 bug 需要多轮 $display 迭代或波形分析。

详见 `projects/test-workflow-round9/EXPERIMENT_REPORT.md`。

### SKILL.md 行数

~338 / 500 行（无文件改动——8d 已集成在 Step 9 Phase 4）

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

## 2026-05-30 — Testbench 基础设施：Icarus 陷阱 + 标准骨架 + APB/AXI-Stream BFM

### 背景

R5-R8 四轮 A/B 实验共发现 19 个 testbench 基础设施 bug，其中旧工作流 Agent A 贡献了 73%。R6 报告明确指出"skill 缺少常见 Icarus testbench 陷阱 reference"。这是 R5-R8 暴露的最大单一基础设施空白。

### 新增/改动文件

| 文件 | 改动 | 行数 |
|------|------|:---:|
| `references/verification/icarus-common-pitfalls.md` | **新建** — 16 个 Icarus 陷阱，分 5 类 (A-E)，全部含 broken/fix 代码、权威引用、实验来源 | 512 |
| `references/verification/tb-examples.md` | 新增 Section 0 标准骨架（含输出协议），APB BFM（write/read/check/PSLVERR），AXI-Stream BFM（send/recv/packet） | 491→822 |
| `references/verification/simulation-loop.md` | 新增 Authority 段落 | — |
| `references/reference-index.md` | 新增 pitfall 索引 | — |
| `SKILL.md` Step 9 | 新增 "Before writing testbench, read icarus-common-pitfalls.md" | +2 |

### Pitfall 分类

| 类别 | 数量 | 典型陷阱 |
|------|:---:|------|
| A: 语法兼容 | 5 | `return`/`break`/`ref` 不支持, `fork` 变量共享, 循环双计数 |
| B: 时序/Delta | 6 | APB delta-cycle race, 组合输出时序, #1 settling, NBA race, APB 写顺序, while(busy_o) |
| C: 协议标记 | 2 | $finish 无标记, 首失败即退出 |
| D: 结构 | 2 | 地址解码别名, 超时太短 |
| E: 多时钟/CDC | 1 | CDC 同步延迟 |

### 权威性验证

全部 12 个核心 claim 通过了三重验证：
1. **实证：** A1-A3 在本地 iverilog 直接编译测试确认
2. **权威：** IEEE 1364-2001 §5.3, Cummings SNUG 1999/2000/2002/2008, ARM IHI 0024C, ARM IHI 0051B
3. **实验：** R5-R8 各项目的 DEVELOPMENT_LOG.md 中的实际 bug 修复记录

详见 `references/verification/citation-verification-report.md`。

### E2E 验证发现

用 AXI-Stream to APB Write Bridge 项目跑端到端验证，agent 使用新 testbench 模板和 pitfalls 后：
- 36/36 测试一次通过，零 testbench bug
- 主动避开了 B4 (negedge drive) 和 B3 (#1 settling delay)
- 发现了新 pitfall B6 (`while(busy_o)` 在 NBA 之前求值)

### SKILL.md 行数

~340 / 500 行

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
