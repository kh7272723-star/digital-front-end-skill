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

## Verification minimum

For an APB register block, include checks for:

- no state update during setup,
- no state update while `pready_o=0`,
- write state update only on completed access,
- read data for valid address,
- byte strobe lane update,
- invalid address error response,
- no register update on invalid write.

## Golden fixture

Use `evals/trials/apb_regs_trial` as the executable local example.
Run:

```text
python scripts/rtl_check.py --case evals/trials/apb_regs_trial
```
