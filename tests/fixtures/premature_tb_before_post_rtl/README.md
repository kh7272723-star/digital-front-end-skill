# Fixture: premature_tb_before_post_rtl

## Purpose
Tests that workflow_gate.py post-rtl FAILs when TB files exist before
post-rtl PASS. The TB files belong in Step 9A/9B, not before post-rtl.

## Expected behavior
- `workflow_gate.py --phase post-rtl <dir>` exits 1 with finding about TB files
- Finding message includes "TB files found but post-rtl validates RTL only"
