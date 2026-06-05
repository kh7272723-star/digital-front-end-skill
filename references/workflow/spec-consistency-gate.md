# SPEC Consistency Gate

Before writing any RTL, verify that the design specification and contract are internally
self-consistent. This gate catches formula errors, unit mismatches, protocol
misinterpretation, and check-then-fail gaps that produce structurally-correct RTL
with functionally-wrong behavior.

## When to Apply

Mandatory for ALL levels before Step 2 (timing contract). L0 may skip formal
recording but must still verify the hard formulas. L1/L2 must produce a
checklist record in the dev log.

## Hard Formula Verification (must pass before any RTL)

### NVMe/DMA

| # | Check | Formula | Common bug |
|---|-------|---------|-----------|
| S1 | Transfer bytes | `transfer_bytes = (NLB + 1) * LBA_SIZE` | NLB used as-is without +1; NLB declared as 16'h (hex) misinterpreted |
| S2 | PRP1 first page capacity | `first_page_cap = PAGE_SIZE - prp1_offset` | Non-zero offset ignored; first page capacity hardcoded to PAGE_SIZE |
| S3 | PRP2 role | `PRP2 = data page` when `transfer_bytes <= first_page_cap + PAGE_SIZE`; `PRP2 = list pointer` when `>` (NOT a data page) | PRP2-list counted as data page: `(1+1+N)*PAGE_SIZE` wrong |
| S4 | PRP list entry count | `data pages = 1 (PRP1) + N_data_entries` (excluding chain pointer). Chain pointer = last entry of full list page only when another list page needed. | Chain pointer counted as data; `(1+1+64)*PAGE_SIZE` anti-pattern |
| S5 | AWLEN/ARLEN | `= beats - 1`, NOT beat count | AWLEN=beats causes wrong burst length |
| S6 | Expected beat count | `total_beats = ceil(transfer_bytes / BUS_BYTES)` | Bytes vs beats confusion; mismatched units |

### AXI

| # | Check | Formula | Common bug |
|---|-------|---------|-----------|
| A1 | Burst boundary | no burst crosses 4KB: `addr[11:0] + (AWLEN+1) * BUS_BYTES <= 4096` | 4KB boundary not checked; address wraps |
| A2 | WSTRB | `all-ones on all beats except possibly last`; last beat: `wstrb = (last_byte_offset < BUS_BYTES) ? (1<<last_byte_offset)-1 : all-ones` | Last beat WSTRB wrong; no WSTRB planning |
| A3 | BRESP/RRESP | `must be captured and propagate to completion status`; `OKAY`=2'b00, `EXOKAY`=2'b01, `SLVERR`=2'b10, `DECERR`=2'b11 | Response wired but never checked |

### General

| # | Check | Formula | Common bug |
|---|-------|---------|-----------|
| G1 | Byte-to-beat conversion | `beats = bytes >> log2(BUS_BYTES)`; explicit conversion wire | Implicit unit mixing |
| G2 | Parameter consistency | No local hardcode when parameter exists | LIST_ENTRIES=512, local array [0:63] |

## Failure Classification

| Class | Symptom | Action |
|:-----:|---------|--------|
| **SPEC-FORMULA** | Contract formula contradicts protocol spec or arithmetic | Fix SPEC/contract before any RTL. Re-run consistency check. |
| **SPEC-UNIT** | Bytes vs beats vs entries mismatch in contract | Rename variables with unit suffix; update contract. |
| **SPEC-CLAIM** | Protocol hard claim in contract lacks source label or contradicts source | Downgrade to Conservative pattern or cite correct source section. |
| **SPEC-GAP** | Required protocol field (BRESP, status, opcode) has no verification plan | Add to test plan or document as intentional waiver. |

## Record Format

Insert into dev log before Step 2:

```
SPEC Consistency Check:
- [ ] S1: transfer_bytes = (NLB+1)*LBA_SIZE verified
- [ ] S2: PRP1 offset handled; first_page_cap correct
- [ ] S3: PRP2 page/list decision boundary correct
- [ ] S4: PRP list entries/chaining documented or waivered
- [ ] S5: AWLEN/ARLEN = beats-1 (not beat count)
- [ ] S6: expected beat count computed from transfer_bytes
- [ ] A1: 4KB boundary handling planned
- [ ] A2: WSTRB plan for last beat
- [ ] A3: BRESP/RRESP captured + propagate to completion
- [ ] G1: byte-to-beat conversions explicit and named
- [ ] G2: no fake parameterization (RSP7)
Status: PASS / FAIL (list failed items)
```

If any S/A/G item fails, fix the specification or contract before proceeding to
Step 2. Do not write RTL against a self-contradictory spec.
