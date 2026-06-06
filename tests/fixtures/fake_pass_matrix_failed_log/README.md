# Fixture: fake_pass_matrix_failed_log

## Purpose
Tests that pre_integration_gate FAILs when module_verification_matrix.md
claims PASS for a sub-module but the referenced sim log contains
ALL_TESTS_FAIL/TEST_FAIL evidence.

## Expected behavior
- `pre_integration_gate.py <dir>` exits 1 (FAIL)
- Finding: "claims PASS but sim log contains FAIL/FATAL/timeout evidence"
