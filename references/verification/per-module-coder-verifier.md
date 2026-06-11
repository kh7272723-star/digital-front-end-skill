# Per-Module Coder+Verifier Loop

For L2 multi-module projects, each sub-module must pass standalone verification
before the next sub-module is written. This prevents upstream bugs from
propagating to downstream modules.

## Loop Structure

For each sub-module (sequentially, one at a time):

### STEP A — Coder

Generate RTL for this sub-module only.

- Use the module function dict (`docs/module-<name>-func-dict.md`) as spec
  reference
- Follow all RTL coding standards from SKILL.md Step 7
- Output exactly one `.v` file in `rtl/`
- Do NOT write any testbench during this loop

### STEP B — Verifier

Immediately verify this sub-module standalone.

1. **Standalone compile** (just this `.v`, no TB):
   ```bash
   iverilog -g2012 -o nul rtl/<module>.v
   ```
   Must produce: `# COMPILE_STANDALONE: <module> PASS`

2. **Style check**:
   ```bash
   python scripts/rtl_style_check.py rtl/<module>.v
   ```
   No E-level violations allowed.

### STEP C — Decision

| Result | Action |
|--------|--------|
| Both PASS | Record "Per-Module Verify: `<module>` PASS" in `docs/dev_log.md`, move to next sub-module |
| Either FAIL | Return to STEP A, fix the RTL, repeat |
| 4th failure on same module | STOP — escalate to human per `references/workflow/human-escalation-protocol.md` |

## Key Rules

- Do NOT write RTL for module B until module A passes standalone verification
- Do NOT write any testbench during this loop
- This loop prevents upstream bugs from propagating to downstream modules
- After ALL sub-modules pass this loop, proceed to Step 8 (self-review)

## Termination

- Normal: all sub-modules recorded PASS in dev_log.md → proceed to Step 8
- Escalation: 4th failure on any single module → structured report per
  `references/workflow/human-escalation-protocol.md`

## Record Format in dev_log.md

```
## Per-Module Coder+Verifier Loop

| Module | Compile | Style | Status | Iterations |
|--------|---------|-------|--------|------------|
| mod_a  | PASS    | PASS  | PASS   | 1          |
| mod_b  | PASS    | PASS  | PASS   | 2          |
```
