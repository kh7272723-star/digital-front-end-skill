# Fixture: clean_l2_per_module_then_integration

## Purpose
Tests that pre_integration_gate PASSes when each sub-module has real PASS
evidence (sim logs with ALL_TESTS_PASS + SIMULATION_DONE) before integration.

## Expected behavior
- `pre_integration_gate.py <dir>` exits 0 (PASS)
- No PRE_INTEGRATION_STRICT or PRE_INTEGRATION_LOCK findings
