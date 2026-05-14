# AXI-Lite guidelines

## Purpose

Use this file for small AXI-Lite slaves, register blocks, and bus adapters.
AXI-Lite looks simple but fails often when write address, write data, write response, read address, and read data channels are treated as one combined handshake.
This guidance is distilled from the Arm AMBA AXI and AXI-Lite protocol specifications. Use `protocol-authority-map.md` when exact source/version matters.

## Supported conservative subset

Default to this subset unless the user gives a stronger project convention:

- one clock domain,
- synchronous active-high `rst_i` in examples,
- one outstanding write transaction,
- one outstanding read transaction,
- no read-data replacement while `rvalid_o && !rready_i`,
- no write-address or write-data acceptance while `bvalid_o && !bready_i`,
- decode errors return an error response and do not update registers.

If the user needs multiple outstanding transactions, pipelined address acceptance, or bridge behavior, move to a subsystem contract before writing RTL.

## Channel contracts

Write address:

- `awvalid_i && awready_o` accepts address and protection sideband if present.
- Address may arrive before, after, or in the same cycle as write data.
- Address must be stored until matching write data is available.

Write data:

- `wvalid_i && wready_o` accepts data and byte strobes.
- Data must be stored until matching write address is available.
- Byte strobes must update only selected byte lanes.

Write response:

- `bvalid_o` asserts after both write address and write data are accepted and the register update or decode error is known.
- `bvalid_o` and `bresp_o` hold until `bready_i=1`.
- A block must not report a write complete before the response is visible to the master.

Read address:

- `arvalid_i && arready_o` accepts a read address.
- Read data and response are registered in the example subset.

Read data:

- `rvalid_o`, `rdata_o`, and `rresp_o` hold while `rvalid_o && !rready_i`.
- A decode error returns an error response and a deterministic data value.

## Required cycle rows

Include rows for:

- reset release,
- AW before W,
- W before AW,
- AW and W accepted in the same cycle,
- B held under backpressure,
- AR accepted and R generated,
- R held under backpressure,
- decode error response.

## Verification minimum

For an AXI-Lite register block, include checks for:

- independent AW/W arrival order,
- byte strobe update behavior,
- B response hold until `bready_i`,
- R payload hold until `rready_i`,
- invalid address response,
- no register update on invalid write address,
- no new transaction accepted beyond the declared outstanding limit.

## Golden fixture

Use `evals/trials/axi_lite_regs_trial` as the executable local example.
Run:

```text
python scripts/rtl_check.py --case evals/trials/axi_lite_regs_trial
```
