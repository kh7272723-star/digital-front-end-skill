# Fixture: weak_compile_log_no_marker

## Purpose
Tests that workflow_gate.py post-rtl FAILs when a compile log exists
but lacks both the # COMPILE_RTL_ONLY marker and compile success evidence
(COMPILE_PASS / compilation successful / no errors / etc.).

## Expected behavior
- `workflow_gate.py --phase post-rtl <dir>` exits 1 (FAIL)
- Finding mentions "lacks both RTL-only marker" and "COMPILE_RTL_ONLY"
