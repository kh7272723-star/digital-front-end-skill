# Principle Review 5a — P1 (Timing Contract) and P2 (FSM Safety)

## Design: AXI-Stream to APB Write Bridge
## Classification: L1 (Leaf)
## Date: 2026-05-30

---

## P1: Timing Contract

### Signal Classification

| Signal | Type | Details |
|--------|------|---------|
| s_axis_tvalid_i | Level | Standard AXI-Stream valid, holds until TREADY |
| s_axis_tdata_i | Level | Payload, stable while TVALID asserted |
| s_axis_tlast_i | Level | Ignored per contract |
| s_axis_tready_o | Level (combinational) | 1 when FSM in IDLE, 0 otherwise |
| apb_psel_o | Registered | Driven from psel_q, reflects FSM SETUP/ACCESS |
| apb_penable_o | Registered | Driven from penable_q, 1 only in ACCESS |
| apb_paddr_o | Registered | Driven from paddr_q, updated after PREADY |
| apb_pwdata_o | Registered | Driven from pwdata_q, captured on TVALID |
| apb_pwrite_o | Static | Always 1 (write-only bridge) |
| busy_o | Level (combinational) | 1 when FSM not in IDLE |
| error_o | Pulse (registered) | 1 cycle, set on PSLVERR detection |

### Q1: For each pulse output (error_o): does it use transition detection or state comparison?

**Answer:** error_o uses state comparison indirectly. In the combinational block, when state_q==ACCESS && PREADY && PSLVERR, error_d=1. In all other cases, error_d=0 (default). The registered error_q then holds the pulse value. Since error_d is default-0, error_q automatically clears after 1 cycle. This is safe because:
- error_d is only 1 in exactly one condition (ACCESS+PREADY+PSLVERR)
- After state transitions away from ACCESS, error_d returns to 0
- No risk of spurious firing on reset (reset clears error_q)

### Q2: For each valid/ready handshake: does VALID hold until READY? Is payload stable while VALID=1?

**Answer:** s_axis_tvalid_i is driven by the upstream AXI-Stream master. By AXI-Stream specification, TVALID must hold until TREADY. The bridge does not deassert TVALID (it's an input). Payload (TDATA) is assumed stable while TVALID=1. Per spec, TDATA is captured on the TVALID+TREADY handshake edge.

### Q3: Is s_axis_tready_o dependent on non-protocol conditions?

**Answer:** No. TREADY is purely state-dependent: 1 in IDLE, 0 in SETUP/ACCESS. It does not depend on FIFO status, outstanding count, or any flow control beyond the FSM state. This is correct per AXI-Stream spec (IHI0051).

**Verdict: P1 PASS. No issues found.**

---

## P2: FSM Safety

### FSM States and Transitions

```
IDLE ---(TVALID)---> SETUP ---(always 1 cycle)---> ACCESS ---(PREADY)---> IDLE/SETUP
```

### Q1: Can this FSM get stuck? For every non-IDLE state, what guarantees the transition condition?

**SETUP:** Always transitions to ACCESS after 1 cycle. No wait condition. **Cannot get stuck.**

**ACCESS:** Waits for PREADY. PREADY is driven by the APB slave. Per APB spec (IHI 0024C), PREADY must eventually be asserted for every valid access. The APB slave is required to respond. If PREADY never asserts, the bridge stalls — this is the standard APB behavior (wait states). The bridge correctly holds all outputs stable while PREADY=0. **Cannot get stuck for a correctly functioning slave — standard APB protocol.**

### Q2: For states entered on a request signal (IDLE entered on TVALID): if TVALID deasserts, is there an abort path?

**IDLE:** The FSM only transitions to SETUP when TVALID is asserted. If TVALID is deasserted while in IDLE, the FSM stays in IDLE. This is safe — IDLE is the reset state and idle state.

**SETUP:** Not entered on a request — always entered from IDLE after a valid beat. No abort path needed; unconditionally transitions to ACCESS.

**ACCESS:** Not entered on a request. If TVALID deasserts while the FSM is in ACCESS, there is no issue — the current APB transaction completes, and the FSM returns to IDLE (or stays IDLE if no new data). The FSM does not wait for TVALID in ACCESS; it waits for PREADY. **No abort path needed.**

### Q3: After reset, is the FSM in IDLE with all outputs at safe defaults?

| Output | Reset Value | Safe? |
|--------|------------|-------|
| state_q | IDLE | Yes |
| psel_q | 0 | Yes |
| penable_q | 0 | Yes |
| paddr_q | APB_BASE_ADDR | Yes |
| pwdata_q | 0 | Yes |
| error_q | 0 | Yes |

**Verdict: All outputs are at safe defaults after reset. No spurious pulses.**

### Q4: Does the combinational block have default assignments before the case statement?

**Answer:** Yes. state_d = state_q, psel_d = 0, penable_d = 0, pwdata_d = pwdata_q, paddr_d = paddr_q, error_d = 0, s_axis_tready_o = 0. All signals have default values before any conditional assignments. This prevents latch inference.

### Q5: Is there a default case that recovers to IDLE?

**Answer:** Yes. The FSM has `default: state_d = IDLE;` in the case statement.

### Q6: Are all state transitions intentional and sequential?

**Answer:** Yes. The transitions are: IDLE -> SETUP, SETUP -> ACCESS, ACCESS -> IDLE, ACCESS -> SETUP (back-to-back). All transitions are explicit and intentional.

**Verdict: P2 PASS. No issues found.**
