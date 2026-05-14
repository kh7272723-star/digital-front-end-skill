# AXI-Stream guidelines

## Purpose

Use this file for AXI-Stream sources, sinks, width converters, packetizers, and DMA stream boundaries.
This guidance is distilled from the Arm AMBA AXI4-Stream protocol specification. Use `protocol-authority-map.md` when the exact AXI-Stream version matters.

## Channel contract

AXI-Stream is a unidirectional ready/valid stream.
Generated RTL must define payload and sideband movement together:

- transfer occurs when `tvalid_i && tready_o` or `tvalid_o && tready_i`;
- `tdata`, `tkeep`, `tstrb`, `tlast`, `tid`, `tdest`, and `tuser` move as one item when present;
- source holds payload and sideband stable while valid is asserted and ready is low;
- packet boundary behavior is defined by `tlast` when used.

## Common design traps

- Dropping `tlast` alignment during stall.
- Updating `tdata` without updating `tkeep` or `tuser`.
- Assuming every beat has all byte lanes valid.
- Width conversion that loses packet boundary or byte-lane meaning.
- Backpressure loop through combinational ready paths.

## Required contract points

- Data width and byte-lane sideband policy.
- Whether `tkeep` and `tstrb` are present.
- Packet semantics for `tlast`.
- Behavior for zero-byte or partial last beats if supported.
- Latency and buffering depth.
- Backpressure and replacement-cycle behavior.

## Required cycle rows

Include rows for:

- reset release,
- normal beat,
- downstream stall,
- replacement beat,
- packet last beat,
- partial last beat if `tkeep` is present,
- sideband stability under stall.

## Verification minimum

For an AXI-Stream block, include checks for:

- payload and sideband stability under stall,
- packet boundary preservation,
- byte-lane preservation through width conversion,
- no data loss or duplication under randomized ready,
- ready path loop review,
- scoreboard for packet ordering.

## Golden fixture

Use `evals/trials/axis_buffer_trial` as the executable local example.
The fixture is independently written from the Arm AXI4-Stream rules, with implementation style informed by mature open-source AXI-Stream component libraries.

It checks:

- `TDATA`, `TKEEP`, `TLAST`, and `TUSER` move together,
- output fields stay stable under downstream stall,
- partial last beats preserve `TKEEP`,
- scoreboard ordering under a randomized ready pattern.

Run:

```text
python scripts/rtl_check.py --case evals/trials/axis_buffer_trial
```
