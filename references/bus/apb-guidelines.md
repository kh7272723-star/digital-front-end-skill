# APB guidelines

## Purpose

Use this file for APB slaves, register blocks, and AXI/APB bridges.
This guidance is distilled from the Arm AMBA APB protocol specification. Use `protocol-authority-map.md` when the exact APB version matters.

## Conservative subset

Default to this subset unless the project requires more:

- one clock domain,
- synchronous active-high `rst_i` in examples,
- no pipelined transfers inside one APB slave,
- register update only in the access phase when the slave is ready,
- deterministic decode error behavior.

## Transfer phases

APB has a setup phase followed by an access phase:

- setup: `psel_i=1`, `penable_i=0`;
- access: `psel_i=1`, `penable_i=1`;
- completed access: `psel_i && penable_i && pready_o`.

Do not update registers in setup phase.
If `pready_o=0`, hold off the transfer and do not update state.

## Signal rules for generated examples

- `paddr_i`, `pwrite_i`, `pwdata_i`, and `pstrb_i` are sampled on completed write access.
- `prdata_o` and `pslverr_o` are meaningful for completed access.
- `pstrb_i` updates only selected byte lanes.
- Decode errors return `pslverr_o=1` and do not update registers.

## Required cycle rows

Include rows for:

- reset release,
- setup phase,
- access phase with wait state,
- completed write access,
- completed read access,
- byte-strobe partial write,
- invalid address response.

## APB master-side rules (for bridges and bus masters)

When generating an APB master interface (e.g., AXI-to-APB bridge):

- `PSEL` asserted in SETUP phase only; deasserted in IDLE and RESPONSE phases
- `PENABLE` asserted in ACCESS phase only; deasserted in SETUP
- `PADDR`, `PWDATA`, `PWRITE` latched in SETUP, held stable through ACCESS
- `PSEL` and `PENABLE` must not glitch — combinational from FSM state is acceptable if state transitions are clean
- On `PREADY=0`: hold all APB signals stable, do not advance FSM
- On `PREADY=1` with `PSLVERR=1`: capture error, map to upstream error response (e.g., AXI SLVERR)
- `PSEL` must deassert between transactions (no permanent assertion)

**Registered output race condition:** if the APB slave uses registered `PRDATA`/`PSLVERR` outputs, the bridge must sample these one cycle after `PREADY=1`. On the `PREADY=1` cycle, the slave's registered outputs are updating — sampling on the same edge may capture stale data. Add a dedicated sample state (e.g., `S_RDATA`) after ACCESS completes. See `references/timing/timing-contract-template.md` for the registered output sampling pattern.

## APB self-review checklist

Apply this checklist when generating APB interfaces:

- [ ] PSEL asserted only in SETUP and ACCESS phases
- [ ] PENABLE asserted only in ACCESS phase
- [ ] PADDR/PWDATA/PWRITE latched in SETUP, held through ACCESS
- [ ] No register updates during SETUP phase
- [ ] No register updates while PREADY=0
- [ ] PSLVERR asserted on BOTH invalid read AND invalid write addresses
- [ ] PSEL deasserted between transactions
- [ ] If APB slave uses registered PRDATA: bridge samples one cycle after PREADY=1
- [ ] Reset clears all APB master outputs (PSEL, PENABLE, PADDR, PWDATA, PWRITE)

## Verification minimum

For an APB register block, include checks for:

- no state update during setup,
- no state update while `pready_o=0`,
- write state update only on completed access,
- read data for valid address,
- byte strobe lane update,
- invalid address error response,
- no register update on invalid write.

### Combinational output test timing (critical)

APB combinational outputs (`pslverr_o`, `prdata_o` from combinational mux) are only valid DURING the transaction (when `psel_i && penable_i`). After the transaction ends, `psel_i` and `penable_i` deassert, and combinational outputs return to default.

**Wrong pattern (checks after transaction):**
```verilog
apb_write(8'hFF, 32'h0);  // transaction completes
@(posedge clk);             // too late — pslverr already 0
if (pslverr === 1'b1) ...   // always fails
```

**Correct pattern (checks during transaction):**
```verilog
@(posedge clk); psel<=1; penable<=0; pwrite<=1; paddr<=8'hFF;
@(posedge clk); penable<=1;
#1;  // wait for combinational settle (not a clock edge)
if (pslverr === 1'b1) ...   // correct — checked while transaction active
@(posedge clk); psel<=0; penable<=0;
```

**Rule:** Combinational APB outputs must be checked with `#delay` after `penable<=1` takes effect, NOT after the transaction completes. Use blocking `#1` (or `#0.1`) to let combinational logic settle, then sample.

**Source:** ARM AMBA APB Protocol Specification (IHI 0024) — PSLVERR is driven combinationally from the address decode, valid only when PSEL and PENABLE are asserted.

For an APB master (bridge), additionally check:

- PSEL/PENABLE phase sequencing,
- PADDR/PWDATA stability during ACCESS with wait states,
- error response mapping (PSLVERR → upstream SLVERR),
- back-to-back transactions (PSEL deasserted between them).

## Golden fixture

Use `evals/trials/apb_regs_trial` as the executable local example.
Run:

```text
python scripts/rtl_check.py --case evals/trials/apb_regs_trial
```
