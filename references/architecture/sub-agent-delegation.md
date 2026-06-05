# Sub-Agent Delegation Rules

When delegating RTL work to sub-agents (parallel module generation, testbench writing, etc.), the sub-agent does not automatically load this skill. Without explicit rules, the sub-agent falls back to its training data -- which produces the exact anti-patterns this skill exists to prevent (single-process FSMs, multi-bit values in FSM combinational blocks, mixed AW/W/B channels, wrong naming conventions).

## Delegation Decision Matrix

| Level | Default | Delegation triggers | Required record |
|:-----:|---------|---------------------|-----------------|
| **L0** | No delegation | None. Single executor. Exception: user requests parallel review. | None. |
| **L1** | No delegation | TB/review lane fully independent per-module. User explicitly requests parallel. | If delegating: yes/no + roles. |
| **L2** | Mandatory decision | Any of: total RTL >800 lines; sub-modules >3; any module >400 lines; protocols naturally separable (AXI+NVMe+CDC/FIFO); independent verification lane; protocol authority audit separable; user requests parallel. | Yes/no + roles (if yes) or waiver (if no). |

**L2 without delegation = waiver required.** The waiver must state: reason for single executor, residual risk, and compensation gates. "Modules are tightly coupled" is not sufficient by itself; it must explain why separate architecture, verification, protocol-authority, or integration review lanes cannot proceed independently. Compensation gates must include per-module standalone compile, RSP1-RSP7 structural purity, module-boundary review, contract-to-test trace review, false-pass simulation-log audit, no unwaived `rtl_style_check.py` findings, and at least one negative/mutation test that proves the TB can fail on a real bug.

## Contract-Freeze Precondition

**Sub-agent execution must NOT start before per-module interface contracts are frozen.** The delegation decision can be made early (Step 1.1); RTL execution begins only after Step 1.5 produces frozen per-module interface contracts.

## Delegation Record Template

Insert into the project dev log after classification:

```
Delegation Decision:
- Level: L2
- Delegate: yes / no
- Roles assigned:
  - [role]: [agent name / single executor]
- Contracts frozen: yes / pending
- Reason: (1-2 sentences)

If no delegation:
- Waiver reason:
- Residual risk:
- Compensation gates:
  - [ ] per-module standalone compile
  - [ ] RSP1-RSP7 structural purity
  - [ ] module-boundary review
  - [ ] contract-to-test trace review
  - [ ] false-pass simulation-log audit
  - [ ] no unwaived rtl_style_check.py findings
  - [ ] at least one negative/mutation test proves the TB catches injected bugs
```

## Recommended Roles

When delegating, assign at minimum:

| Role | Responsibility | When to use |
|------|---------------|-------------|
| **Architecture / interface owner** | Per-module contracts, integration invariants, boundary cross-check | Always for L2 |
| **Module RTL executor** | One module per agent: FSMs, datapaths, FIFOs | 1 agent per module >200 lines |
| **Verification executor** | Testbench, scoreboard, protocol assertions, simulation | Separate agent when TB has independent contracts |
| **Protocol authority reviewer** | Verify every must/shall/violation has normative/project label. Audit PRP, AXI response, opcode validation. | Delegatable when protocol work is separable from RTL |
| **Integration reviewer** | Boundary review (P6), per-module compile, signal tracing | After all modules delivered, before system sim |

## Prompt Template

When spawning a sub-agent for RTL tasks, the prompt must include:

```
You are writing RTL for module <module_name>. Before writing code:
1. Load and follow the digital-front-end-skill from <skill_path>/SKILL.md.
2. Read the interface contract at <contract_path>.
   Verify port widths, signal semantics, and handshake rules match.
3. Read references/rtl/rtl-structural-purity.md -- enforce RSP1-RSP7.
4. Read references/rtl/rtl-coding-standards.md -- enforce all M-grade rules.
5. Read the relevant pattern reference:
   - FSM -> references/rtl/fsm-examples.md
   - FIFO -> references/rtl/fifo-examples.md (use FWFT for data-path FIFOs)
   - AXI -> references/axi-dma/axi-dma-channel-guidelines.md
   - DMA -> references/axi-dma/dma-cdma-examples.md
6. Read references/debug/bug-pattern-library.md -- scan applicable patterns.
7. For protocol claims, read references/timing/protocol-authority-map.md.
   Label every must/shall as Normative, Project policy, Conservative pattern,
   Heuristic, or Unverified.
8. After writing RTL, self-review against SKILL.md Step 8 checklist.
9. Verify port widths and signal semantics match the interface contract.
```

## Inline Critical Rules (fallback when skill cannot be loaded)

If the sub-agent cannot load the skill, include these minimum constraints directly:

- Two-process FSM: state register in `always @(posedge clk)`, nstate+single-bit controls in `always @(*)`
- FSM combinational block: ONLY nstate and single-bit controls (`*_en`, `*_fire`, `*_load`). No multi-bit `_n`/`_addr`/`_bytes`/`_count` assignments.
- Datapath sequential blocks: NO `cstate`, `nstate`, or `S_*` references. Gated by named control signals.
- Naming: `*_i`/`*_o` ports, `*_q` registered state, `wr_do`/`rd_do` for FIFO ops, `*_fire` for handshake
- AXI channel separation: AW/W/B independent valid/ready, RD/WR command paths independent
- Bytes/beats/entries/AxLEN units named explicitly; parameter-dependent structures not hardcoded

## Post-Generation Review

After the sub-agent delivers RTL, run the full Step 8 self-review checklist against its output before accepting. Fix violations before integrating. Common sub-agent regressions:

- Multi-bit `_n` signals computed in FSM combinational block (SM1 violation)
- Datapath registers gated on `case(cstate)` instead of control signals (SM2 violation)
- Port widths hardcoded instead of derived from parameters

## Acceptance Commands

Before accepting sub-agent output, run:

```bash
python scripts/rtl_style_check.py <delivered_module>.v
iverilog -g2012 -o /dev/null <delivered_module>.v
```

## L2 Release Gate

After Step 1.1 (yes, delegate) and Step 1.5 (contracts frozen), do NOT start
sub-agents until every item in this checklist is confirmed:

### Release Gate Checklist

- [ ] **Contracts frozen:** All per-module interface contracts written and frozen (port widths, handshake protocols, completion signal types, parameter values).
- [ ] **Roles/owners assigned:** Architect/interface owner, RTL executor per module, verification executor, protocol authority reviewer, integration reviewer.
- [ ] **Per-module acceptance commands defined:** `iverilog -g2012 -o /dev/null <module>.v` for each module.
- [ ] **Integration reviewer assigned:** Briefed on boundary cross-check (P6), signal type cross-check, port width matching.
- [ ] **Prompt contents verified:** Each sub-agent prompt includes skill path + module interface contract + RSP1-RSP7 + protocol authority labels + acceptance commands.
- [ ] **Contract-freeze status:** Recorded in delegation decision record.

### Release Gate Record Template

Insert into project dev log after delegation decision and contract freeze:

```
Release Gate:
- [ ] Contracts frozen: (date / verifier)
- [ ] Roles assigned:
  - Architect / interface owner: (name)
  - Module RTL executor(s): (name per module)
  - Verification executor: (name)
  - Protocol authority reviewer: (name)
  - Integration reviewer: (name)
- [ ] Per-module acceptance commands: (list per module)
- [ ] Integration reviewer briefed: (date)
- [ ] Prompt contents verified: (each sub-agent checked)
- [ ] Contract-freeze status: (recorded / pending)

Status: RELEASED / BLOCKED

If BLOCKED: list unchecked items. Do NOT start sub-agents until all items are
checked and status is RELEASED.
```

### Release Gate Rule

If any item is unchecked, status is BLOCKED. Do not start sub-agents. Fix the
blockers, update the record, and re-check before proceeding.

## L2 Delegation Execution Evidence (mandatory for Delegate: yes)

When L2 Delegate: yes, the following artifacts are mandatory and must be checked
by `project_artifact_gate.py` before the project can claim PASS:

### Required Artifacts

| Artifact | Content | Minimum |
|----------|---------|:---:|
| `docs/delegation_plan.md` | Work package breakdown, per-agent scope, expected deliverables per agent | 1 file |
| `docs/subagents/architect.md` | Architecture decisions, per-module contract review, integration invariants | 1 file |
| `docs/subagents/protocol_reviewer.md` | Protocol claim audit (Normative/Policy/Pattern/Heuristic labels), PRP/response/opcode review | 1 file |
| `docs/subagents/axi_transaction_reviewer.md` | AWADDR/AWLEN/WLAST/WSTRB/BRESP transaction-shape review | 1 file |
| `docs/subagents/rtl_structural_reviewer.md` | RSP1-RSP7 per-module audit, comment-claim false-compliance detection | 1 file |
| `docs/subagents/verification_reviewer.md` | TB scoreboard review, false-pass audit, transaction-shape vs payload checking | 1 file |
| `docs/subagents/integration_reviewer.md` | Boundary cross-check (P6), per-module compile results, signal type matching | 1 file |

### Evidence Rule

Without ALL of the above artifacts, `project_artifact_gate.py` MUST report FAIL.
The dev log writing `Delegate: yes` without these artifacts is a process
violation — the delegation decision must be backed by execution evidence.

### Waiver for Missing Subagent Artifacts

If any subagent artifact is missing, the only valid recovery is:
1. Document the missing artifact as a Blocking Gap (R1) in residual risks
2. Change Status to BLOCKED (not PASS)
3. Complete the missing artifact before re-checking

A dev log that writes both `Delegate: yes` and `Status: PASS` while missing
subagent artifacts is rejected unconditionally.

## Expected Output Formats

**Design request:** Assumptions, Design contract, State elements, Cycle trace, RTL, Verification notes, Risks/corner cases, Review status.

**Review/debug request:** Observed evidence, Likely contract violation, Minimal fix, What to recheck, Residual uncertainty.

**Subsystem/full system:** Assumptions, System contract, Submodule decomposition, Interface contracts, Integration invariants, Local cycle traces, Implementation sequence, Verification strategy, Residual risks.

## Critical Multi-Module Integration Rules

- Sub-agents MUST read the interface contract file -- not just the skill
- Port widths must be derived from the SAME parameters as the driving module
- Byte-to-beats conversions must use the ceiling division formula, not bit extraction
- Document whether `cmd_len_i` (or similar) is in bytes or beats -- ambiguity causes integration bugs
