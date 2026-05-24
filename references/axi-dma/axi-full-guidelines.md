# AXI full guidelines

## Purpose

Use this file for AXI3/AXI4/AXI5 full interfaces, masters, slaves, interconnect-facing blocks, memory engines, and bus bridges.
This guidance is distilled from the Arm AMBA AXI and ACE protocol specification. Use `protocol-authority-map.md` when exact AXI version, optional properties, or project-selected feature set matters.

## Scope discipline

Do not generate full AXI RTL from a vague prompt.
Before RTL, freeze:

- AXI version family,
- data, address, and ID widths,
- supported burst types,
- maximum burst length,
- outstanding read and write limits,
- write-data interleaving policy if applicable,
- response/error policy,
- ordering model,
- supported sideband signals.

If these are missing, produce a contract or one bounded slice only.

## Five-channel separation

Treat AXI as five independently backpressured channels:

- AW: write address and control,
- W: write data beats,
- B: write response,
- AR: read address and control,
- R: read data beats and response.

Each channel needs its own valid/ready rule, payload-hold rule, and local buffering decision.
Do not collapse a write into one combined AW/W/B handshake.

## Burst accounting

For every accepted command, define:

- beat count from burst length field,
- address progression or fixed address behavior,
- byte-lane strobe policy,
- last-beat generation or checking,
- command identity if IDs are used,
- response count expected from the peer.

`WLAST` and `RLAST` are beat-boundary indicators, not whole-system completion by themselves.

## Ordering and outstanding work

Before RTL, state:

- whether multiple IDs are supported,
- whether responses may return out of order across IDs,
- whether same-ID ordering must be preserved,
- how outstanding commands are counted,
- how command identity maps to data and response tracking.

If ID-based ordering is not implemented, explicitly restrict the design to one outstanding transaction or one ID.

## Error handling

AXI response errors must have visible policy:

- capture first error or all errors,
- continue draining expected beats/responses,
- abort future commands or finish current command,
- report completion with error after required drain,
- define reset behavior with outstanding work.

## Required cycle rows

Include rows for:

- AW accepted before W beats,
- W beats arrive while AW path is stalled if supported,
- final W beat accepted before B response,
- B response delayed,
- AR accepted and R beats return with `RLAST`,
- R response error before last beat or on last beat,
- independent stalls on each channel,
- reset/abort with outstanding work.

## Verification minimum

For a full AXI block, include checks for:

- independent channel backpressure,
- burst beat count and last-beat alignment,
- write response after accepted write command/data policy,
- read response ordering and `RLAST`,
- ID ordering if IDs are supported,
- no completion before required B/R responses,
- error capture and drain/abort behavior,
- outstanding counter underflow/overflow.

Use `evals/trials/axi_write_tracker_trial` as the executable local example for a single-ID write burst slice.
Use `evals/trials/axi_read_tracker_trial` as the executable local example for a single-ID read burst slice.
Use `evals/trials/axi_read_id_scoreboard_trial` as the executable local example for a bounded multi-ID read response scoreboard.
Use `evals/trials/dma_completion_slice_trial` as the DMA-oriented example for the common write-completion ordering bug.

The AXI write tracker fixture checks:

- AWVALID and AWLEN hold until AWREADY,
- W beats start only after AW acceptance in the conservative slice,
- W beat count derives from AWLEN plus one,
- WLAST appears only on the final accepted W beat,
- WREADY backpressure does not decrement the beat counter,
- completion waits for B response,
- non-OKAY B response produces an error completion.

Run:

```text
python scripts/rtl_check.py --case evals/trials/axi_write_tracker_trial
```

The AXI read tracker fixture checks:

- ARVALID and ARLEN hold until ARREADY,
- R beats are accepted only after AR acceptance,
- R beat count derives from ARLEN plus one,
- local read-data backpressure does not decrement the beat counter,
- RLAST aligns with the final expected accepted R beat,
- non-OKAY RRESP is captured as an error,
- completion waits for the final expected R beat.

Run:

```text
python scripts/rtl_check.py --case evals/trials/axi_read_tracker_trial
```

The AXI read ID scoreboard fixture checks:

- multiple IDs outstanding at once,
- one outstanding burst per ID in the conservative slice,
- cross-ID completion order can differ from command issue order,
- response for inactive ID is not accepted,
- same active ID is blocked from taking a second command,
- `RLAST` and `RRESP` errors are accumulated per ID.

Run:

```text
python scripts/rtl_check.py --case evals/trials/axi_read_id_scoreboard_trial
```
