# Contract-Implementation Gate

Purpose: Close the loop between design contract, RTL implementation, and TB
verification. Prevents "contract written but RTL ignores it" failures.

## When to Apply

Mandatory for L1/L2 and any protocol work (AXI/APB/AHB/AXI-Stream/NVMe).
L0 may skip formal recording but must still verify the hard items.

## Contract Implementation Matrix

Produce `docs/contract_implementation_matrix.md` in the project. Each row
maps one contract item to its RTL implementation and TB check.

| # | Contract item | RTL producer | RTL consumer | Error/status path | TB check / evidence | Waiver |
|---|--------------|-------------|-------------|-------------------|---------------------|--------|
| 1 | PRP list fetch via AR channel | prp_walker AR FSM | axi_adapter | prp_err_o | T3: AR handshake + R data captured | — |
| 2 | SLBA -> NVM source address | nvm_read_engine nvm_addr_o | NVM model | — | T2: multi-page data continuity | — |

### Required minimum coverage for NVMe/DMA/AXI work

| Category | Items requiring coverage or waiver |
|----------|-----------------------------------|
| PRP | PRP1 offset, PRP2 page/list decision, PRP list fetch (AR/R channel), PRP list entry count, chain pointer if applicable |
| NVM source | SLBA * LBA_SIZE + global byte offset, multi-page continuity |
| Host destination | PRP page addresses mapped to AXI AWADDR per page |
| AXI write | AWADDR sequence per page, AWLEN per burst, WLAST exact cycle, WSTRB on first/middle/last beat, BRESP value per burst, completion ordering |
| Completion | cpl_status (0=success, non-zero on error), cpl_bytes_written, completion only after all B responses |
| Response/error | BRESP error -> completion status; RRESP error if AR used; prp_err_o assertion; opcode/nsid validation |

Any row without TB check evidence requires a documented waiver in the matrix.

## Residual Risk Classification

Every residual risk in the dev log must be classified into one of three tiers:

| Tier | Name | Criteria | PASS allowed? |
|:----:|------|---------|:---:|
| **R1** | **Blocking Gap** | Contract item not implemented; core path not tested; protocol error not propagated; safety-critical signal tied off. | **NO** — cannot claim PASS |
| **R2** | **Accepted Limitation** | Scope reduction documented in SPEC; RTL has defined behavior; TB has negative test or explicit waiver in contract_implementation_matrix.md. | Yes, with evidence |
| **R3** | **Residual Risk** | Non-core, isolated, does not invalidate the delivery claim. No blocking impact. | Yes |

**Blocking keyword detection** (any of these in a residual risk = potential Blocking Gap):
`No .*testing`, `Not implemented`, `NOT implemented`, `tied off`, `simplified`,
`NOT supported`, `unverified`, `missing`, `stub`, `not supported`, `not fully`,
`not tested`, `not verified`.

If a residual risk contains any blocking keyword, it must be EXPLICITLY marked
as "Accepted Limitation" with waiver reason and evidence; otherwise the dev log
`Status: PASS` is rejected by `project_artifact_gate.py`.

## Dev Log PASS Gate

Before writing `Status: PASS`, the dev log must confirm:
- [ ] No unclassified Blocking Gaps in residual risks
- [ ] `contract_implementation_matrix.md` exists and every row has either TB evidence or waiver
- [ ] `rtl_style_check.py` clean (all findings waived in writing)
- [ ] `sim_log_gate.py` PASS on actual simulation log
- [ ] `project_artifact_gate.py` PASS on project directory
- [ ] `artifact_budget_gate.py` PASS on project directory
- [ ] If L2 + Delegate yes: all subagent role reports exist under `docs/subagents/`
- [ ] No-SPEC L1/L2: all required artifacts present under `docs/`

## Hard Compile-Failure Patterns (Blocking Gaps)

The following patterns in compile logs are Blocking Gaps (R1) — cannot claim PASS,
even if simulation appears to pass:

| Pattern | Checker | Severity | Why |
|---------|---------|:---:|------|
| `Simplified` or `NOT supported` in PRP RTL comments | PRP_STUB2 (E) | Blocking | PRP traversal is not fully implemented; the design does not support the claimed functionality |
| `PARAM[63:0]` part-select on <=32-bit parameter | WIDTH_BOUND1 (W) | Blocking | Icarus replaces out-of-bound bits with `'bx`; compile warning = data corruption |
| `docs/` directory empty with no dev_log | project_artifact_gate L2 inference | Blocking | No evidence of any design process; cannot audit |

## Empty-Docs Inference Rule

When `docs/` is empty and no `dev_log.md` exists anywhere, `project_artifact_gate.py`
infers the project level from complexity signals:
- >=3 `.v` files in `rtl/` -> L2
- NVMe signals (prp1/prp2/slba/nlb) + AXI signals (m_axi_awvalid/wvalid/awaddr) -> L2
- `tb/` + `rtl/` directories with .v files -> L2
- `sim/` with .vvp files -> at least L1

The inferred level drives No-SPEC artifact requirements. An empty-docs multi-module
project is automatically rejected by the artifact gate.
