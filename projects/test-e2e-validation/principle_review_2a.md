# Principle Review 2a — P4 (Independence) and P6 (Boundaries)

## Design: AXI-Stream to APB Write Bridge
## Classification: L1 (Leaf)
## Date: 2026-05-30

---

## P4: Independence (LITE)

**When to skip/lite (from design-principles.md):**
- SKIP if: single channel, single clock domain, single protocol, no concurrent operations
- LITE if: dual-channel but single-direction

**Verdict: LITE applies.** Single-direction data path (AXI-Stream -> APB), single clock domain, no concurrent read/write, no configuration interface. No independence coupling risk.

### Q1: What independent concerns exist in this design?

The design has only one data flow: AXI-Stream beats -> APB writes. There is no:
- Read channel (APB is write-only, apb_pwrite_o always 1)
- Configuration/status register path (no APB slave interface)
- Multi-clock domain
- Parallel data paths

**Concerns are inherently independent because there is only one concern.**

### Q2: Can a transaction on one concern accidentally consume or corrupt data on another?

N/A - only one concern exists. No risk of data corruption across channels.

**Verdict: P4 PASS. No action needed.**

---

## P6: Boundaries (LITE)

**When to skip/lite:**
- LITE: single module, simple bus interface -> check port widths and error handling.

### Q1: Do producer and consumer port widths match?

| Signal | Width | Match? |
|--------|-------|--------|
| s_axis_tdata_i | 32 | N/A (input) |
| apb_pwdata_o | 32 | Matches TDATA width |
| apb_paddr_o | 16 | Fixed width via APB_BASE_ADDR |
| s_axis_tready_o | 1 | Standard single-bit ready |
| busy_o | 1 | Status output |
| error_o | 1 | Pulse output |

All widths match the system contract.

### Q2: Are all errors propagated?

PSLVERR from APB slave is captured on PREADY=1 and propagated as error_o pulse. Single error source, single error output. No unhandled errors.

### Q3: Dead ports?

apb_prdata_i is unused (write-only bridge). This is by design - the port exists because APB protocol defines it, but the bridge never reads. Documented in contract as "unused but connected." All other ports are referenced in the module body.

**Verdict: P6 PASS. No action needed.**

---

## Summary

| Principle | Scope | Verdict | Action |
|-----------|-------|---------|--------|
| P4 | LITE | PASS | None |
| P6 | LITE | PASS | None |
