# Task Mode Routing

Not every request needs the full RTL generation workflow. Route the task to the
appropriate mode before entering the standard pipeline.

## Mode Selection Table

| User intent | Mode | Entry point | Required gates | Output format |
|-------------|------|-------------|:---:|---------------|
| "write/generate/implement RTL" | **design** | Step 1 → full pipeline | All level-appropriate gates | Design contract, cycle trace, RTL, TB, verification plan |
| "review/audit/check this RTL" | **review** | Step 8 checklist directly | RSP1-RSP7, protocol authority hygiene, false-pass audit | Structured review with line citations |
| "debug/fix this simulation failure" | **debug** | simulation-loop.md Phase 4 | Principle-driven diagnosis (P1-P5a mapping), bug pattern match, fix discipline | Root cause, minimal fix, re-run evidence |
| "audit protocol claims in this code" | **protocol-audit** | `references/timing/protocol-claim-ledger.md` (template) | Label every must/shall/violation; verify against source; flag unverified claims | Claim ledger (project-local), gap report |
| "modify/improve this skill" | **skill-maintenance** | Read CLAUDE.md first | skill_static_check.py, eval_benchmark_check.py, json.tool, py_compile | Modified files, check results, residual risks |
| "plan/coordinate multi-module project" | **L2-orchestration** | Step 1 → 1.1 → 1.5 → 1.6 | Delegation Decision Gate + Release Gate; contracts frozen before execution | Decomposition, contracts, delegation record, release checklist |

## Design Mode (Full Pipeline)

```
0 (entry routing) → 1 (parse) → 1.1(if L2) → 1.2(preflight L1/L2) → 1.5(if L2)
→ 1.6(if L2+delegated) → 2 → 2a → 3(freeze + matrix skeleton) → 4 → 5 → 5a
→ 6 → 6a → pre-rtl gate → 7 → 7b → 8(self-review) → 8c(principle review)
→ 8b(verif plan) → 9A(per-module sim, L2) → pre-integration gate (L2)
→ 9B(integration sim) → post-sim gate → 10(finalize)

Step 3: create docs/contract_implementation_matrix.md skeleton immediately after contract freeze.
Step 9A/9B: use scripts/run_sim_guarded.py, not bare vvp.
Final: artifact_budget_gate must pass; logs are evidence, .vvp/build/archive files are not.
Pre-RTL gate: after contracts frozen, before any RTL generation.
```

### Phase-local gate commands

Use `workflow_gate.py` as the only normal gate entry during Design Mode. These
commands are stop-go boundaries, not finalization-only checks. Each PASS writes
`docs/workflow_state.json`; later phases require predecessor PASS. Sibling gate
scripts are wrapper internals or debug tools. Their direct output is not phase
evidence. `--force` is for human-directed recovery only; it is not a waiver for
final PASS.

| Boundary | Command | Predecessors (L1/L2) | If FAIL |
|----------|---------|---------------------|---------|
| After contracts frozen (before RTL) | `python scripts/workflow_gate.py --phase pre-rtl <project_dir>` | none | Do not write RTL |
| After RTL + compile log | `python scripts/workflow_gate.py --phase post-rtl <project_dir>` | pre-rtl | Do not write TB or integrate |
| Before L2 integration TB/sim | `python scripts/workflow_gate.py --phase pre-integration <project_dir>` | post-rtl (L2 only) | Do not create integration artifacts |
| After each simulation loop | `python scripts/workflow_gate.py --phase post-sim <project_dir>` | post-rtl; +pre-integration if L2 integration | Do not finalize |
| Final delivery | `python scripts/workflow_gate.py --phase final <project_dir>` | full chain | Do not claim PASS |

**Level-specific scope:**
- **L0:** pre-rtl predecessor not enforced. Single-module projects skip pre-integration.
- **L1:** pre-rtl required (timing-contract + verification_matrix). Pre-integration is not forced; classify real integration projects as L2.
- **L2:** full chain enforced. Pre-rtl checks contract readiness (5 docs non-empty). Per-module evidence required before integration.

`final_delivery_gate.py` is an aggregation safety net and independently checks
`docs/workflow_state.json`. It is not the normal final entry. Direct final-gate
calls without the applicable phase PASS stamps fail. If it fails, project status
must be BLOCKED, FAIL, or BLOCKED_BY_GATE_DISPUTE with evidence; never plain
PASS.

Hard gates enforce generic RTL/verif/delivery evidence, not project-specific
microarchitecture. Protocol-specific claims must remain labeled Normative /
Project policy / Conservative pattern / Heuristic / Unverified.

## Review Mode

Skip Steps 1-7 entirely. Start from Step 8 checklist and apply:
- RSP1-RSP7 structural purity
- Protocol authority hygiene (claim ledger)
- Signal type cross-check
- NBA ordering hazard check
- Step 8b golden reference strategy (but do not generate TB)
- Step 10 finalize: maturity level, residual risks

Output: per-item pass/fail with line citations, cited references, overall verdict.

## Debug Mode

Entry: simulation failure log + RTL files + principle review docs.
Follow simulation-loop.md Phase 4:
1. Categorize: compile / testbench infrastructure / RTL functional
2. Map symptom to principle doc (P1-P5a)
3. Match against bug-pattern-library.md
4. Apply minimal fix with fix discipline (Delete → Retime → Constrain → Add)
5. Re-run Step 8 checklist on changed files
6. Re-run Step 7b + Step 9 simulation

Do NOT generate new RTL from scratch unless the existing design is structurally
unfixable (document why).

## Protocol-Audit Mode

Entry: RTL files + contract documents.
Read `references/timing/protocol-authority-audit.md` and use the template at
`references/timing/protocol-claim-ledger.md` (project-local copy, not editing the reference).
For every hard claim in comments, assertions, and explanations:

1. Extract the claim text
2. Label: Normative / Project policy / Conservative pattern / Heuristic / Unverified
3. Cite source document and section number
4. Verify: does the assertion match the exact rule claimed?
5. Flag any unsupported must/shall/violation

Output: claim ledger table, gap report, labelled claims.

## Skill-Maintenance Mode

Entry: modify any file in this skill repository.
Before editing: read CLAUDE.md. After editing, run:

```bash
python scripts\skill_static_check.py
python -m json.tool evals\evals.json
python -m json.tool evals\benchmark.json
python scripts\eval_benchmark_check.py
python -m py_compile scripts\rtl_style_check.py
```

If SKILL.md is modified, keep it under 500 lines (current target: <=460). Move
verbatim details to references when approaching the limit.

## L2-Orchestration Mode

Entry: multi-module L2 project. Follow Steps 1 → 1.1 → 1.5 → 1.6, produce:
decomposition, frozen per-module contracts, delegation decision record, release
gate checklist. Sub-agents receive contracts + prompt template from
sub-agent-delegation.md. Integration reviewer validates boundary cross-check
before system simulation.
