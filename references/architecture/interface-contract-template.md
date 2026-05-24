# Interface contract template

## Purpose

Use this template for submodule boundaries in subsystem and full-system designs.
It makes integration timing explicit without tracing every register.

## Required fields

- interface name,
- producer,
- consumer,
- payload fields,
- sideband fields,
- transfer condition,
- hold rule,
- release rule,
- backpressure direction,
- latency,
- ordering guarantee,
- reset behavior,
- flush or abort behavior,
- error behavior,
- checks.

## Output template

| Field | Contract |
| --- | --- |
| Interface | |
| Producer | |
| Consumer | |
| Payload | |
| Sideband | |
| Transfer condition | |
| Hold rule | |
| Release rule | |
| Backpressure direction | |
| Latency | |
| Ordering | |

## Inter-module handshake rules

When multiple modules form a pipeline or sequential chain, the interface contract must define:

1. **Completion signaling:** How does module A tell module B "I'm done"? Options:
   - Pulse `done_o` (1 cycle) — use when B starts on rising edge of done
   - Level `done_o` (sticky) — use when B checks done at its own pace
   - Valid/ready handshake — use when B may not be ready immediately

2. **Command passing:** How does module A pass work to module B? Options:
   - Direct connection: A's output → B's input (same cycle)
   - Registered: A's output registered, B sees next cycle
   - FIFO: A pushes to queue, B pops when ready

3. **Error propagation:** How do per-module errors combine?
   - OR of all error outputs (first-error-wins)
   - Priority encoding (specific error overrides generic)
   - Per-channel error with separate reporting

**Rule:** the interface contract must include a "sequencing" field that describes the order of operations between modules. Without this, sub-agents will make incompatible assumptions.

## Port width derivation rules

When a port's width depends on a parameter, derive it from the SAME parameter as the module that drives it:

| Port type | Width derivation | Example |
|-----------|-----------------|---------|
| FIFO count | `$clog2(DEPTH)+1` — from DEPTH, not DATA_WIDTH | `count_o [ADDR_WIDTH:0]` where `ADDR_WIDTH=$clog2(DEPTH)` |
| FIFO data | DATA_WIDTH — directly | `rdata_o [DATA_WIDTH-1:0]` |
| AXI len | 8 bits — fixed by AXI spec | `arlen_o [7:0]` |
| AXI addr | ADDR_WIDTH — from top-level parameter | `araddr_o [ADDR_WIDTH-1:0]` |
| Beat count | 8 bits (max 256) or 32 bits (arbitrary) | `beat_cnt [7:0]` for AXI bursts |

**Rule:** when connecting two modules, if the producer's output width differs from the consumer's input width, the top-level integration must include explicit width conversion. Document the conversion in the integration notes.

## Byte-to-beats conversion checklist

For any module that converts byte counts to AXI beat counts:

- [ ] `total_beats = (total_bytes + BUS_BYTES - 1) >> LP_BLOCK` — ceiling division
- [ ] `arlen = total_beats - 1` — AXI format (len = beats - 1)
- [ ] Do NOT use `cmd_len_i[12:LP_BLOCK]` as a substitute for division — bit extraction only works when the address offset is zero
- [ ] Handle `total_beats == 0` as an error or no-op
- [ ] Handle `total_beats > 256` by splitting into multiple bursts
- [ ] Document whether `cmd_len_i` is in bytes or beats — ambiguity causes integration bugs
| Reset | |
| Flush or abort | |
| Error behavior | |
| Checks | |

## Integration rule

Every top-level connection must connect two compatible interface contracts.
If the producer can advance while the consumer must hold, add buffering or change the contract before RTL.
