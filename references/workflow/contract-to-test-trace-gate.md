# Contract-to-Test Trace Gate

## Purpose

Prevent a common L2 failure mode: the interface contract names useful
sideband/status fields, the RTL wires or stubs them, and the testbench still
passes because it never checks them.

Apply this gate for L1/L2 designs, protocol adapters, DMA/NVMe paths, and any
review that sees `ALL_TESTS_PASS` on a subsystem.

## Required Trace Table

Before writing or accepting the testbench, create a small trace table in
`docs/verification_matrix.md` or the review report:

| Contract field | RTL producer | RTL consumer | TB check | Waiver |
| --- | --- | --- | --- | --- |
| `cpl_status` | completion engine | host-facing CPL | success and error status compared | none |
| `cpl_bytes_written` | write engine | completion engine | expected bytes checked per command | none |
| `busy` | top-level status | integrator/software | asserted during active transfer, clear after CPL | none |
| `m_axi_awaddr` | write engine | AXI host | expected PRP page sequence checked | none |
| `m_axi_awlen` | write engine | AXI host | beats minus one checked | none |
| `m_axi_wstrb` | write engine | AXI host | all/full/last beat mask checked | none |
| `m_axi_bresp` | AXI host | completion/error logic | non-OKAY becomes error completion | none |

Add rows for every externally visible status, error, count, pointer, and
protocol response field. A field may be waived only when the project spec says
it is debug-only or unused; the waiver must state the residual risk.

## Hard Failures

Classify the result as FAIL until fixed or waived when any item applies:

- A top-level output is connected to `()` in the TB.
- A completion/status/count output is declared but never compared.
- A protocol response (`BRESP`, `RRESP`, error sideband) is consumed in RTL but
  no negative test checks propagation.
- A transaction-shape field (`AWADDR`, `AWLEN`, `WSTRB`, `WLAST`) is observed
  but only beat count is checked.
- The audit section only prints text such as `FALSE-PASS AUDIT` without adding
  assertions, error-count updates, or `$fatal` conditions.

## NVMe/PRP Minimum

For PRP-list tests, beat count is not enough. The TB must compare the expected
host destination sequence:

1. PRP1 first page address, including PRP1 offset when non-zero.
2. Each PRP list data entry used for remaining pages.
3. No use of PRP2 itself as a data page when PRP2 is a list pointer.

The 16KB/4-page PRP-list case requires PRP1 plus three PRP-list data entries.
If only two entries are preloaded, the test is incomplete even if all beat-count
checks pass.

## Evidence Cross-Check

Every evidence token (e.g. T1, T10, T3) cited in the protocol claim ledger
(`docs/protocol_claim_ledger.md`) must appear in a TB file under `tb/*.v` or
`tb/*.sv`. Ledger evidence that cites non-existent tests is a documentation
lie — the project cannot have verified that claim.

Run `scripts/project_artifact_gate.py <project_dir>` to automate this check.

## Verification Matrix Test-Name Cross-Check

In addition to T-number evidence tokens, the verification matrix references
specific test names (TEST_PASS <name>, check_<name>, test_<name>). Every such
name must exist in a TB file. A verification matrix that claims "TEST_PASS
test_page_read" but no TB contains `test_page_read` is a documentation lie.

`scripts/project_artifact_gate.py` extracts test-name references from
`docs/verification_matrix.md` and verifies each name appears in a TB file
under `tb/` or `sim/tb_*`.

**Common mismatch pattern:** The verification matrix uses T-number IDs (T1-T8)
while the TB uses descriptive names (test_reset, test_page_read). The matrix
must either:
1. Use the TB's actual test names in the "Expected log token" column, or
2. Include a mapping table from T-numbers to TB test names.

## verification_matrix.md Format

Each row in the verification matrix must include:

| Column | Required | Example |
|--------|----------|---------|
| Test ID | yes | T3 |
| Field/claim | yes | AWADDR sequence for PRP pages |
| TB line or checker location | yes | tb_nvme_io.v:380 or check_awaddr task |
| Expected log token | yes | TEST_PASS T3 or assertion message |
| Actual log evidence | yes | paste from sim log or VCD excerpt |

The matrix bridges the gap between "the claim ledger says T3 verified AWADDR"
and "the TB actually checks AWADDR and the sim log confirms it passed".
