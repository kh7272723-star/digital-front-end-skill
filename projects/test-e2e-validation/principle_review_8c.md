# Principle Review 8c — P3 (Known Values) and P5a (Output Discipline)

## Design: AXI-Stream to APB Write Bridge
## Classification: L1 (Leaf)
## Date: 2026-05-30

---

## P3: Known Values

### Register Audit

| Register | Width | Reset Value | Location | Notes |
|----------|-------|-------------|----------|-------|
| state_q | 2 | IDLE (2'b00) | Process 2 | Explicit reset |
| pwdata_q | 32 | 32'd0 | Process 2 | Explicit reset |
| paddr_q | 16 | APB_BASE_ADDR (16'h1000) | Process 2 | Explicit reset to parameter |
| psel_q | 1 | 1'b0 | Process 2 | Explicit reset |
| penable_q | 1 | 1'b0 | Process 2 | Explicit reset |
| error_q | 1 | 1'b0 | Process 2 | Explicit reset |

### Q1: After reset, what value does every register hold?

All registers have explicit reset values (see table above). No registers lack reset assignments.

### Q2: Are there any unreset register arrays or memories?

No. There are no register arrays or memories in this design.

### Q3: Does every combinational block assign defaults before conditional branches?

Yes. Process 1 (the single `always @(*)` block) assigns defaults to every signal at the top:
- state_d = state_q
- psel_d = 1'b0
- penable_d = 1'b0
- error_d = 1'b0
- s_axis_tready_o = 1'b0
- load_data = 1'b0
- incr_addr = 1'b0

This prevents latch inference on all signals.

### Q4: Is every net driven by exactly one source?

Yes. All signals have exactly one driver:
- state_q, pwdata_q, paddr_q, psel_q, penable_q, error_q: driven by Process 2 (sequential)
- state_d, psel_d, penable_d, error_d, s_axis_tready_o, load_data, incr_addr: driven by Process 1 (combinational)
- apb_psel_o, apb_penable_o, apb_paddr_o, apb_pwdata_o, apb_pwrite_o, busy_o, error_o: driven by `assign` statements

No multiply-driven nets.

### Q5: Are blocking assignments used in combinational blocks and nonblocking in sequential blocks?

Yes. Process 1 uses `=` (blocking). Process 2 uses `<=` (nonblocking). Never mixed in the same block.

### Q6: Does the file start with `default_nettype none?

Yes. Line 1: `` `default_nettype none ``
End of file: `` `default_nettype wire ``

**Verdict: P3 PASS. All registers have known values at all times. No issues.**

---

## P5a: Output Discipline

### Q1: Are all module boundary outputs driven from registers?

| Output | Driven From | Registered? |
|--------|------------|-------------|
| apb_psel_o | psel_q | Yes |
| apb_penable_o | penable_q | Yes |
| apb_paddr_o | paddr_q | Yes |
| apb_pwdata_o | pwdata_q | Yes |
| apb_pwrite_o | Constant 1 | Static |
| s_axis_tready_o | Combinational from state_q | No (AXI-Stream, not APB) |
| busy_o | Combinational from state_q | No (status signal) |
| error_o | error_q | Yes (registered 1-cycle pulse) |

**Rationale for non-registered outputs:**
- **s_axis_tready_o**: Must be combinational from IDLE state to reflect readiness immediately. Per AXI-Stream spec (IHI0051), backpressure can be combinational for short paths. There is only one module in the data path, so no combinational ready loop (H2) risk.
- **busy_o**: Status signal, not part of APB protocol. Combinational from state_q == IDLE is safe and standard for status outputs.

### Q2: Are internal counters gated by state?

There are no internal counters in this design. The address register (paddr_q) only updates when incr_addr is asserted (which occurs only in the ACCESS state when PREADY=1). It does not run freely.

### Q3: Are bit widths derived from $clog2 or parameters?

- APB_BASE_ADDR is a 16-bit parameter.
- ADDR_INCR is a 1-bit parameter.
- paddr_q is 16 bits wide, matching APB_BASE_ADDR width.
- pwdata_q is 32 bits wide, matching s_axis_tdata_i width.
- state_q is 2 bits wide (3 states, safe encoding).
- All widths are explicitly defined in the parameter list and module ports. No hardcoded magic numbers.

### Q4: Does error_o pulse stay exactly 1 cycle wide?

**Analysis:** error_d is set to apb_pslverr_i in the ACCESS+PREADY branch. In all other states and conditions, error_d defaults to 0. error_q registers error_d. This creates a 1-cycle pulse:
- Cycle N (ACCESS+PREADY+PSLVERR): error_d = 1
- Cycle N+1 (any state): error_d = 0 (default)
- Cycle N+1 posedge: error_q becomes 0

The pulse is exactly 1 cycle wide because error_d is default-0 and is only asserted in a single branch condition.

**Verdict: P5a PASS. Output discipline is clean. No issues.**
