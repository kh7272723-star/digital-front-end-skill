# Fixture: parameterized_integration_tb

## Purpose
Tests that pre_integration_gate detects integration TB via parameterized
instantiation pattern: `dma_top #(.WIDTH(32)) inst_dut (.clk_i(clk))`.

## Expected behavior
- `pre_integration_gate.py <dir>` exits 1 (FAIL)
- Finding identifies tb/tb_dma_top.v as integration TB
- Finding mentions module_verification_matrix.md needed for sub-modules
