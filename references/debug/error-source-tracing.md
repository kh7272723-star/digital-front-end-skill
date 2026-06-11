# Error Source Tracing — Decision Tree

When any compilation or simulation fails, classify the error BEFORE attempting
a fix. Misclassification wastes iterations.

## Step 1: Classify the Error

| Category | Indicator | Action |
|----------|-----------|--------|
| **1. Wrong Spec Understanding** | The generated RTL contradicts the spec/function-dict; the design approach itself is flawed | Return to Step 1-3. Revise the module function dict or planning artifacts. Then re-generate RTL. |
| **2. Upstream Module Error** | This module's interface receives bad data from a previous module; the bug is in a dependency | Trace back to the upstream module. Fix THAT module first. Re-verify the upstream module standalone. Then return to current module. |
| **3. Current Module Error** | The error is local: logic bug, timing issue, FSM flaw within this module only | Fix the current module. Re-run standalone verify (Step 7a Step B). Max 3 fix iterations. |
| **4. Unclear Cause** | Cannot determine which of 1-3 applies after 2 analysis attempts | ESCALATE to human per `references/workflow/human-escalation-protocol.md`. |

## Step 2: Apply the Action

For **Category 1**: Do NOT keep hacking RTL. Go back to planning.

For **Category 2**: Fix the root cause, not the symptom.

For **Category 3**: Use `bug-pattern-library.md` for known patterns. Apply fix
discipline: Delete -> Retime -> Constrain -> Add.

For **Category 4**: Do NOT guess. Escalate with structured report.

## Step 3: After Fix

- Re-run the verification that caught the error
- If the SAME error persists after 2 fix attempts for the same classification,
  re-classify (you may have misdiagnosed)
- If a NEW error appears, classify it fresh using Step 1
