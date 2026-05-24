# Assertion quality checklist

## Purpose

Use this file when generating or reviewing SystemVerilog assertions.
Assertions have timing semantics and can be wrong even when the RTL is right.

## Checks

- Clock domain: every assertion samples on the clock that owns the checked signal.
- Reset mask: `disable iff` covers only cycles where the assertion is meaningless; it must not hide the first meaningful post-reset cycle.
- Registered effects: use `|=>` for next-cycle registered behavior.
- Same-cycle effects: use `|->` only for combinational behavior that is visible in the same sampled cycle.
- History: use `$past` only when the sampled history is valid; gate or initialize history-dependent checks.
- Stability: use `$stable` across a `|=>` boundary for payload-hold checks.
- Vacuity: add a cover property or directed test for each important antecedent.
- Multi-bit transitions: avoid `$rose(bus)` for semantic value changes; compare explicit values.

## Common assertion bugs

| Bug | Risk | Fix |
| --- | --- | --- |
| Wrong assertion clock | samples unrelated domain | match the signal's clock |
| `|->` for registered output | expects too-early behavior | use `|=>` |
| broad `disable iff` | masks real failure | disable only reset or test-inactive cycles |
| ungated `$past` | reads invalid history | gate with a valid/history flag |
| no cover for antecedent | vacuous pass | cover the trigger scenario |

## Output rule

When assertions are included with RTL, state whether they are simulation-only, formal-ready, or illustrative.
Do not present unrun assertions as proof of correctness.
