# Claude Code Development Memory

This workspace develops `digital-front-end-skill`.

Keep this file short. Detailed iteration history belongs in
`SKILL_CHANGELOG.md`; do not duplicate changelog entries here.

## Current Invariants

- Design workflow:
  `pre-rtl -> RTL-only Step 7 -> post-rtl -> self-review/principle review ->
  verification plan -> L2 per-module verification -> pre-integration ->
  integration verification -> post-sim -> final`.
- Step 7 is RTL-only. Do not create TB files or non-compile simulation
  artifacts before the first post-rtl PASS.
- `post-rtl` validates only `rtl/*.v` / `rtl/*.sv`. It requires a compile log
  with `# COMPILE_RTL_ONLY` or `# COMPILE_STANDALONE` plus explicit compile
  success evidence. Success text without a marker is not enough.
- Re-running `post-rtl` after a prior PASS is allowed for RTL debug even when
  old TB/log artifacts exist. The gate must still check only RTL evidence.
- L2 integration is forbidden until `pre-integration` passes. Per-module matrix
  rows must bind to real in-project sim/proof logs; text PASS is not evidence.
- `workflow_state.json` PASS stamps include artifact snapshots. Later phases
  must reject stale predecessor evidence.
- Final delivery must not claim PASS when any workflow phase is missing, FAIL,
  stale, or inconsistent with `docs/dev_log.md`.

## Development Rules

- Codex owns planning, diff audit, and final acceptance. Claude Code may execute
  implementation tasks, but its textual success summary is not acceptance
  evidence.
- Do not commit, push, install globally, or sync to Codex/Claude global skill
  directories unless the user explicitly requests it.
- After skill edits, run at minimum:
  - `python scripts/skill_static_check.py --root .`
  - `python tests/run_workflow_gate_regression.py`
  - `python -m py_compile` on changed Python scripts
- For workflow-gate changes, also run the relevant gate on at least one real
  failing project fixture or returned project, and confirm the expected FAIL is
  caused by the intended evidence issue.

## Reference Pointers

- Current workflow source: `SKILL.md`
- Full iteration history: `SKILL_CHANGELOG.md`
- Regression runner: `tests/run_workflow_gate_regression.py`
