# Coding guidelines

## Correctness rules (mandatory)

See `references/rtl/correctness-rules.md` for full details with tool warnings, bug examples, and fixes. Key rules:

- Every module file starts with `` `default_nettype none `` and ends with `` `default_nettype wire `` (E8).
- Every `reg`/`wire` has exactly one driving `always`/`assign` block (E1).
- Every combinational `always @(*)` block assigns default values before conditional branches (E2).
- `<=` (nonblocking) in `always @(posedge clk)`, `=` (blocking) in `always @(*)`, never mixed (E4).
- All registers have explicit reset assignments (E6).
- No implicit width truncation — use explicit part-selects (E3).
- No combinational feedback loops (E7).

## General rules

- Keep combinational blocks fully assigned.
- Keep sequential blocks edge-triggered and easy to scan.
- Prefer one reset style per module.
- Use parameters for widths and depths when appropriate.
- Preserve protocol semantics over micro-optimizations.
- If a feature is ambiguous, surface the ambiguity rather than guessing.
- Avoid mixed blocking/nonblocking style in stateful logic.
- Name protocol conditions once and reuse them.
- Keep data, valid, sideband, and error fields aligned through every stall or flush.
- State whether FIFO memory read data is registered or combinational.
- State the read-during-write policy (read-first, write-first, or undefined) when the FIFO allows simultaneous read and write to the same address.
- Declare wires before their first use — avoid forward references. While Verilog allows wire forward references, some lint tools produce warnings and it reduces readability.

## Naming conventions

Read `references/timing/naming-guidelines.md` before writing any module port list. Key rules:

- Port suffixes: `*_i` for inputs, `*_o` for outputs. Clock: `clk_i`. Reset: `rst_i` (active-high) or `rst_ni` (active-low).
- FIFO external controls: `wr_en_i`, `rd_en_i` — never use informal alternatives like `write`/`read` or producer/consumer verbs.
- FIFO external data: `wdata_i`, `rdata_o`.
- FIFO status: `full_o`, `empty_o`, `count_o`.
- FIFO internal operations: `wr_do = wr_en_i && !full_o`, `rd_do = rd_en_i && !empty_o`.
- Registered state: `*_q` suffix (e.g., `state_q`, `count_q`, `wr_ptr_q`, `rd_ptr_q`).
- Next-state values: `*_d` suffix (e.g., `state_d`, `count_d`).
- Movement conditions: name once as a wire, reuse everywhere. Do not inline `valid_i && ready_o` in multiple places.
- For AXI-adjacent command/status interfaces, prefer `valid_i`/`ready_o` over `req_i`/`ack_o` to maintain semantic consistency with AXI's own valid/ready protocol.

## AXI channel separation

For any AXI write master: AW, W, and B channels must have independent valid/ready control. Do not use a single FSM that sequentially manages AW issuance, W data driving, and B response collection. Each channel needs its own acceptance condition and payload-hold rule. Read `references/axi-dma/axi-dma-channel-guidelines.md` "Golden completion slice" for the correct pattern: burst planner feeds independent AW/W/B controllers, completion waits for B response count to reach zero.

Burst-level flow control must also be independent: accepting a new burst from the burst planner must not block on the previous burst's B response. Use an outstanding counter (like the read master's `ar_outstanding_q`) to allow overlapping bursts. The `burst_ready_o` signal should check outstanding capacity, not B response arrival. AXI protocol supports multiple outstanding transactions (IHI0022E Section A5.3); blocking on B re-couples channels at the burst level, defeating the purpose of independent AW/W/B control.

Read and write command paths must also be independent. Do not use `burst_ready = burst_ready_rd & burst_ready_wr` — this couples the two directions at the command level, blocking the fast side when the slow side stalls. Instead, the burst planner should issue read and write burst commands independently, each with its own valid/ready handshake. The FIFO between read and write paths naturally decouples data availability: the write path only issues when data is present, the read path issues as fast as the source allows. Reference: ARM PL330 (DDI 0441) uses independent RD/WD half-channels; Xilinx CDMA (PG034) uses separate read/write master interfaces decoupled by an internal FIFO.

For DMA completion tracking: use a single ordered queue where each entry tracks outstanding burst count. Avoid mixing multiple pointer domains (alloc, burst, done) — if used, document the ordering invariant that keeps them aligned. Completion requires all B responses for that command, not just the last W beat (see bug pattern P4).

## High-value design patterns

### FSM

Use when the logic is control-heavy and the behavior is stateful. Include: state list, transition conditions, outputs per state, illegal-state handling if needed. See `references/rtl/fsm-examples.md`.

**Single-bit control rule:** The FSM's `always @(*)` block must only assign single-bit signals (enables, qualifiers, flags) and `state_d`. Multi-bit registers (addresses, counters, lengths, data, strobes) must be updated in synchronous `always @(posedge clk)` blocks gated by the FSM's single-bit enables. Do not use `_d` suffix as a loophole — if the target is wider than 1 bit, it does not belong in the FSM combinational block. See `references/debug/bug-pattern-library.md` SM1, SM2.

### FIFO / buffer

Use when the block absorbs timing mismatch or decouples producer and consumer. Include: occupancy tracking, full/empty behavior, write/read conflict behavior. Port names: `wr_en_i`/`rd_en_i`, `wdata_i`/`rdata_o`, `full_o`/`empty_o`. Internal conditions: `wr_do`, `rd_do`. Pointer names: `wr_ptr_q`, `rd_ptr_q`, `count_q`. See `references/rtl/fifo-examples.md` and `references/timing/naming-guidelines.md`.

### Handshake adapter

Use when converting between different ready/valid or request/ack style interfaces. Include: ordering guarantees, backpressure behavior, data stability rules, throughput assumptions. See `references/rtl/handshake-examples.md`.

### Pipeline stage

Use when the goal is timing closure or controlled latency. Include: stage latency, bypass or stall behavior, bubble handling, flush/reset policy. See `references/rtl/pipeline-examples.md`.
