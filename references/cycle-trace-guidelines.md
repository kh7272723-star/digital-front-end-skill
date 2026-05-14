# Cycle trace guidelines

## Purpose

Use cycle traces to force bottom-level circuit reasoning before RTL.
For FSMs, FIFOs, pipelines, ready/valid handshakes, and any nontrivial sequential logic, write a cycle trace before code.

## Required table

Use this table shape:

| Cycle | Pre-edge state | Combinational condition | Active-edge update | Next visible state | Invariant |
| --- | --- | --- | --- | --- | --- |

Definitions:

- Pre-edge state: values sampled by sequential logic at the active edge.
- Combinational condition: derived conditions during the cycle, such as `accept_input`, `wr_do`, or `advance`.
- Active-edge update: register assignments scheduled by the clock edge.
- Next visible state: values downstream logic sees after the edge.
- Invariant: the contract that must remain true.

## Reset release example

| Cycle | Pre-edge state | Combinational condition | Active-edge update | Next visible state | Invariant |
| --- | --- | --- | --- | --- | --- |
| reset | `rst_i=1`, state unknown | reset branch selected | state registers set to idle values | valid-like outputs low | no transaction is visible during reset |
| first active | idle state, `rst_i=0` | normal conditions evaluate | accept only if contract allows first-cycle input | first post-reset state visible | reset release does not create a false valid item |

## Ready/valid stall example

| Cycle | Pre-edge state | Combinational condition | Active-edge update | Next visible state | Invariant |
| --- | --- | --- | --- | --- | --- |
| t0 | `valid_o=1`, downstream not ready | `accept_output=0`, `ready_o=0` if storage full | no payload update | `valid_o` and `data_o` unchanged | payload stable while waiting |
| t1 | same stored item, downstream ready | `accept_output=1` | item may be consumed and replacement may load | next item or empty state visible | no item duplicated or lost |

## FIFO boundary example

| Cycle | Pre-edge state | Combinational condition | Active-edge update | Next visible state | Invariant |
| --- | --- | --- | --- | --- | --- |
| full write/read | `full_o=1`, `empty_o=0` | conservative policy: `wr_do=0`, `rd_do=rd_en_i` | read pointer and count update only if `rd_do=1` | occupancy decreases by one | full write is not accepted unless contract says so |
| empty read/write | `empty_o=1`, `full_o=0` | conservative policy: `rd_do=0`, `wr_do=wr_en_i` | write pointer and count update only if `wr_do=1` | occupancy increases by one | empty read is not accepted unless contract says so |

## Pipeline stall example

| Cycle | Pre-edge state | Combinational condition | Active-edge update | Next visible state | Invariant |
| --- | --- | --- | --- | --- | --- |
| stall | `valid_o=1`, payload A | `advance=0` | no state update | payload A remains visible | valid, data, and sideband freeze together |
| advance | payload A visible | `advance=1` | stage captures input payload B | payload B visible after edge | data and control move together |

## How to use the trace

- If a row cannot be filled, the design contract is not complete.
- If RTL does not implement a row, change the RTL or the contract before finalizing.
- If verification does not check the key invariant, add a directed test or assertion.
