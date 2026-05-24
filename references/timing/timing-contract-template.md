# Timing contract template

## Purpose

Use this template before writing RTL or debugging RTL.
It forces the agent to describe cycle behavior explicitly.

## Required fields

- module purpose
- clock domain(s)
- reset style
- input handshake
- output handshake
- data latency
- stall behavior
- flush behavior
- boundary behavior
- illegal or unsupported cases

## Cycle contract questions

1. What is visible in the current cycle?
2. What is registered for the next cycle?
3. What must remain stable while waiting?
4. What happens when both sides are ready or not ready?
5. What happens on the first cycle after reset release?
6. What happens at the full/empty or valid/invalid boundary?

## Output format

When the skill uses this template, it should produce:

- a short timing summary
- a table or bullet list of cycle behavior
- any assumptions that still need confirmation
- a note about which signals are held or advanced each cycle

## DMA / burst-level timing contract additions

For DMA engines and burst-based data movers, add these fields to the timing contract:

### FIFO pipeline stages

Describe the FIFO output style and its impact on data-path timing:

| Field | Required | Example |
|-------|----------|---------|
| FIFO output style | Yes | FWFT (combinational) or registered |
| Read latency | Yes | 0 cycles (FWFT) or 1 cycle (registered) |
| Data available delay | Yes | Same cycle as `empty_o` deasserts (FWFT) or next cycle |
| Impact on WVALID/WDATA | Yes | WDATA valid same cycle as WVALID (FWFT) or one cycle later |

**FWFT is mandatory for data-path FIFOs.** If the FIFO uses registered output, the timing contract must explicitly state the one-cycle latency and how the consumer compensates (e.g., pre-fetch, bypass mux). See `references/rtl/fifo-examples.md` for the standard FWFT pattern.

### Burst-level timing

For each burst in the transfer, describe:

```
Burst N timing:
  Cycle 0: AWVALID asserts, AWADDR/AWLEN stable
  Cycle 1: WVALID asserts (FWFT: WDATA valid this cycle)
  Cycle 2+: W beats continue, WLAST on final beat
  Cycle K: B response arrives (may be many cycles after WLAST)
```

### Completion signal timing

Describe whether `done_o` is a pulse or level signal:

| Style | When to use | Behavior |
|-------|-------------|----------|
| Pulse (1 cycle) | Command-level completion | `done_o` high for exactly one cycle when all B responses received |
| Level (sticky) | Status register | `done_o` stays high until next command starts or status is cleared |

**Rule:** if the spec says "done pulses per command", use a rising-edge detector on the level signal:
```verilog
wire b_done_level = all_aw_done && (b_outstanding == 0);
reg b_done_prev_q;
always @(posedge clk_i) begin
    if (rst_i) b_done_prev_q <= 1'b0;
    else       b_done_prev_q <= b_done_level;
end
assign done_o = b_done_level && !b_done_prev_q;  // rising-edge pulse
```

### WVALID / FIFO relationship

State explicitly whether WVALID depends on FIFO state:

| Pattern | Correct? | When acceptable |
|---------|----------|-----------------|
| `WVALID = w_active_q` | ✅ | Always (FIFO pre-validated before burst start) |
| `WVALID = w_active_q && data_available` | ❌ | Never — P12 violation if FIFO empties mid-burst |
| `WVALID = w_active_q && burst_ready` | ✅ | When burst_ready checks FIFO count >= burst length |

See `references/axi-dma/axi-dma-channel-guidelines.md` for the burst-ready gate pattern.

### Registered output sampling in bridges and converters

When a bridge or converter connects to a downstream module with registered outputs, the consumer may need an extra cycle to sample the stable value. This is a common source of race conditions in protocol bridges.

**The problem:**
```
Downstream module: PRDATA is a registered output, updated when PREADY=1
Bridge: samples PRDATA on the same clock edge as PREADY=1
Result: bridge gets STALE data (PRDATA hasn't updated yet)
```

**The pattern:** add a dedicated "sample" state after the handshake completes:

```
Cycle N:   ACCESS phase, PREADY=1 → APB slave updates PRDATA (registered)
Cycle N+1: SAMPLE phase → bridge captures PRDATA (now stable)
Cycle N+2: RESPONSE phase → bridge drives RDATA to upstream
```

**When to apply:**
- Downstream module uses registered outputs (check the module's output stage)
- Handshake completion (READY=1) and data output update happen on the same clock edge
- Consumer samples data on the same clock edge as handshake completion

**When NOT to apply:**
- Downstream module uses combinational outputs (FWFT FIFO, combinational mux)
- Handshake and data are on separate cycles (data latched before VALID)

**Rule:** if the downstream module's output is registered, add one cycle of margin between handshake completion and data sampling. Document this in the timing contract as "registered output → extra sample cycle."