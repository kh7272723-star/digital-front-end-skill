# AXI DMA channel guidelines

## Purpose

Use this file when a DMA, memory mover, bus bridge, or AXI subsystem request includes AXI read, AXI write, completion, errors, or interrupts.
This is not a full AXI specification; it is a checklist that prevents common wrong RTL assumptions before detailed implementation.
This guidance is distilled from the Arm AMBA AXI protocol family and must be checked against the project-selected AXI version before signoff.

## AXI channel separation

Treat each AXI channel as independently backpressured:

- read address issues commands,
- read data returns beats and response status,
- write address issues write commands,
- write data emits payload beats,
- write response confirms write completion status.

Do not merge channels into one transaction handshake in RTL or explanation.
Each channel needs an owner, acceptance condition, held payload rule, outstanding counter, and error path.

## AXI handshake rules and local W-channel policies (Arm IHI 0022 Section A3.3)

The first five rules are normative AXI handshake requirements. W-channel buffering mode is a local design policy and must not be described as a universal AXI requirement.

**A3.3.1 — Handshake process:**

1. **VALID must not wait for READY.** A source must not wait until READY is asserted before asserting VALID. This prevents deadlock: if both sides wait for each other, no transfer ever occurs.

2. **VALID must hold until handshake completes.** Once VALID is asserted, it must not be deasserted until the transfer occurs (VALID && READY both high on the same rising clock edge). Deasserting VALID without a completed transfer is a protocol violation.

3. **READY may wait for VALID.** A destination is permitted to wait for VALID before asserting READY. However, it is also permitted to assert READY before VALID.

**A3.3.2 — Signal dependencies:**

4. **VALID must not depend on READY.** The assertion of VALID must not be dependent on the assertion of READY. This is a hard constraint to prevent combinational loops between master and slave.

5. **READY may depend on VALID.** A destination may base its READY assertion on the VALID signal. This is allowed and does not create combinational loop risk.

**W-channel burst rules:**

6. **Per-beat WVALID stability is normative.** If `WVALID=1` and `WREADY=0`, the master must keep `WVALID`, `WDATA`, `WSTRB`, and `WLAST` stable until that beat handshakes. Dropping `WVALID` before a presented beat is accepted is a protocol violation.

7. **Continuous WVALID across a whole burst is a local policy, not an AXI hard rule.** A design may choose continuous/full-burst-buffered mode to simplify counters and verification. In that mode, check that all burst data is available before the first W beat and keep `WVALID` asserted until the `WLAST` beat handshakes.

8. **Elastic W data mode is legal only with an explicit contract.** In elastic/per-beat buffered mode, `WVALID` may have bubbles between accepted W beats, but the design must prove no FIFO underflow, no data drop, correct `WLAST`, and bounded progress if the project requires a latency bound.

9. **WLAST must coincide with the final accepted W beat.** `WLAST` is meaningful only with a valid W beat, and the beat counter must advance only on `WVALID && WREADY`.

**RTL enforcement checklist (apply during self-review):**
- [ ] ARVALID/AWVALID hold until corresponding READY (rule 2) — check `ar_pending_q`/`aw_pending_q` logic
- [ ] WVALID, WDATA, WSTRB, and WLAST hold stable while `WVALID && !WREADY` (rule 6)
- [ ] W beat counter, FIFO pop, and WLAST update only on `WVALID && WREADY`
- [ ] W data mode is declared: continuous/full-burst-buffered or elastic/per-beat buffered
- [ ] Continuous mode only: WVALID holds from first presented beat to WLAST and full-burst data availability is checked before start
- [ ] Elastic mode only: WVALID bubbles between accepted beats are covered and bounded by local liveness policy
- [ ] VALID assertion does not wait for READY; local resource checks occur before VALID is asserted, then VALID holds until handshake
- [ ] RVALID/BVALID hold until READY (rule 2) — applies to slave-side logic
- [ ] No combinational path from VALID to READY or READY to VALID (rules 4, 5)

## DMA ordering rules

- A descriptor is not complete when the last write data beat is emitted.
- Completion requires all required write responses for that descriptor to be observed.
- Interrupt follows visible completion state or writeback, not the last data beat.
- Read data accepted internally must be written, drained by an explicit error policy, or discarded only by a defined abort/reset policy.
- Errors need a first-error capture rule and a drain or abort rule.

## Burst and beat accounting

Before RTL, define:

- maximum burst length,
- address alignment policy,
- byte count to beat conversion,
- last-beat generation,
- write strobe policy,
- boundary crossing policy,
- outstanding read limit,
- outstanding write command limit,
- outstanding write response limit,
- descriptor ID or ordering rule.

If any item is missing, write architecture or one leaf module only.

## Byte-to-beat conversion formula

Given: `addr`, `data_len`, `BUS_BYTES` (= `DATA_WIDTH / 8`), `LP_BLOCK` (= `$clog2(BUS_BYTES)`)

```
addr_offset   = addr[LP_BLOCK-1:0]
total_bytes   = addr_offset + data_len
total_beats   = ceil(total_bytes / BUS_BYTES) = (total_bytes + BUS_BYTES - 1) / BUS_BYTES
burst_count   = ceil(total_beats / 256)       = (total_beats + 255) / 256
remain_beats  = total_beats % 256              (0 means no partial burst)
```

**Special case:** if `total_beats == 256`, `remain_beats = 0` but `burst_count = 1`.
Use explicit `if (total_beats <= 256)` branch — do NOT use bit-slicing for the remainder.
See bug pattern DP4 for the bit-slicing trap.

## WSTRB computation for unaligned addresses

For transfers with unaligned start address:

```
1. aligned_addr = addr & ~(BUS_BYTES - 1)
2. first_offset = addr - aligned_addr        (bytes to skip in first beat)
3. total_bytes  = first_offset + data_len
4. total_beats  = ceil(total_bytes / BUS_BYTES)
5. last_offset  = (first_offset + data_len) % BUS_BYTES
   (if last_offset == 0: all bytes valid on last beat)
```

WSTRB masks:

| Beat | WSTRB |
|------|-------|
| First beat | `~((1 << first_offset) - 1)` — mask off low bytes |
| Last beat (if != first) | `(1 << last_offset) - 1` — mask off high bytes |
| Middle beats | all 1s (full bus width valid) |

**Example:** `BUS_BYTES=32`, `addr=0x1003`, `data_len=100`

```
first_offset = 3
total_bytes  = 103
total_beats  = ceil(103/32) = 4
last_offset  = 103 % 32 = 7

First beat WSTRB = 32'hFFFFFFF8  (skip low 3 bytes)
Last beat WSTRB  = 32'h00000007  (only low 7 bytes valid)
Middle beats     = 32'hFFFFFFFF
```

**Verilog implementation (must handle last_offset == 0):**

```verilog
// First beat: mask off low bytes
wire [BUS_BYTES-1:0] wstrb_first = ~({BUS_BYTES{1'b1}} << first_offset);

// Last beat: mask off high bytes
// CRITICAL: when last_offset == 0, all bytes are valid (transfer ends at bus boundary)
// The formula (1 << last_offset) - 1 produces 0 when last_offset == 0, which is WRONG
// Must use explicit check:
wire [BUS_BYTES-1:0] wstrb_last = (last_offset == {LP_BLOCK{1'b0}})
    ? {BUS_BYTES{1'b1}}                           // all bytes valid
    : ({BUS_BYTES{1'b1}} >> (BUS_BYTES - last_offset));

// Single beat: intersection of first and last
wire [BUS_BYTES-1:0] wstrb_single = wstrb_first & wstrb_last;

// Middle beats: all 1s (always full bus width)
```

**Why last_offset == 0 is special:** When `(first_offset + data_len) % BUS_BYTES == 0`, the transfer ends exactly at a bus boundary. All bytes in the last beat are valid. The shift formula `>> (BUS_BYTES - 0)` would shift by BUS_BYTES, producing all-zeros — an invalid WSTRB that causes the slave to ignore all data.

## 4KB boundary splitting

AXI spec (IHI0022E Section A3.4.1): bursts must not cross a 4KB boundary. A burst that starts at address `A` with length `N` beats must satisfy:
```
aligned_start = A & ~(BUS_BYTES - 1)       // beat-aligned start
last_byte     = aligned_start + (N * BUS_BYTES) - 1
boundary      = (A & ~12'hFFF) + 12'h1000  // next 4KB boundary
assert(last_byte < boundary)
```

**Beats-to-boundary formula:**
```verilog
// How many beats before crossing the next 4KB boundary?
wire [11:0] bytes_to_boundary = 12'h1000 - {1'b0, addr[11:0]};
wire [7:0]  beats_to_boundary = bytes_to_boundary >> LP_BLOCK;

// First burst length: min(beats_to_boundary, 256, remaining_beats)
wire [7:0] first_burst_len = (beats_to_boundary < remaining_beats[7:0])
                           ? ((beats_to_boundary < 8'd256) ? beats_to_boundary : 8'd255)
                           : ((remaining_beats[7:0] < 8'd256) ? remaining_beats[7:0] - 1 : 8'd255);
```

**Common mistake:** using `12'h800` (2KB) instead of `12'h1000` (4KB). This causes unnecessary burst splitting and reduces throughput. The 4KB boundary is a hard AXI requirement, not a design choice.

## Risky local traces

Trace these before implementation:

- read command accepted but data FIFO later becomes full,
- read data returns while write data channel is stalled,
- write address accepted but write data is delayed,
- last write data beat emitted while write response is delayed,
- error response arrives after partial movement,
- abort/reset occurs with outstanding read or write work,
- completion writeback is delayed while interrupt is requested.

## Verification minimum

For a DMA slice, include:

- command count versus response count checks,
- descriptor byte count versus emitted beat count,
- data ordering scoreboard,
- backpressure on every AXI channel independently,
- error response and drain/abort tests,
- completion-after-write-response check,
- interrupt-after-visible-completion check.

## Golden completion slice

Use `evals/trials/dma_burst_planner_trial` as the executable first slice for descriptor parsing and burst command generation.
Use `evals/trials/dma_completion_slice_trial` as the executable first slice for completion ordering.
It models one active descriptor, final write-data acceptance, expected B response count, error capture, and completion hold.

The burst planner fixture checks:

- descriptor byte count converts to full-width beat count,
- source and destination addresses increment together,
- read and write command lengths match,
- read and write command backpressure holds payload stable,
- expected B response count equals write command count,
- invalid descriptors emit error completion and no commands.

Key rule captured by the fixture:

- final W beat acceptance sets data-side done only,
- each accepted B response reduces outstanding response count,
- descriptor completion appears only after data-side done and response count zero,
- any non-OKAY B response marks the descriptor error after all expected responses drain.

Run:

```text
python scripts/rtl_check.py --case evals/trials/dma_completion_slice_trial
```

## Anti-pattern: single FSM for AW+W+B

A common mistake is using one FSM that sequentially manages AW issuance, W data driving, and B response collection. This couples the channels and prevents independent backpressure handling.

**Wrong pattern (DO NOT USE):**
```verilog
// Single FSM: CALC→SEND→B — couples AW, W, B
case (state_q)
  S_CALC: begin aw_valid_q <= 1; aw_addr_q <= addr; end
  S_SEND: begin w_valid_q <= 1; w_data_q <= data; end  // waits for w_fire
  S_B:    begin if (b_fire) state_d = DONE; end         // waits for B
endcase
```

**Correct pattern: independent channel controllers**

Each AXI channel gets its own valid/ready handshake logic. A burst planner feeds commands to the AW controller; a data feeder feeds the W controller; the B controller tracks outstanding responses.

```verilog
// AW channel: independent valid/ready with payload hold
reg aw_pending_q;
always @(posedge clk_i) begin
  if (rst_i) aw_pending_q <= 1'b0;
  else if (aw_fire) aw_pending_q <= 1'b0;
  else if (burst_valid && !aw_pending_q) aw_pending_q <= 1'b1;
end
assign m_axi_awvalid = aw_pending_q;
// aw_addr_q, aw_len_q loaded when burst_valid && !aw_pending_q

// W channel: independent valid/ready with payload hold
// Pre-condition: burst_ready guarantees FIFO has enough data BEFORE starting
reg w_pending_q;
always @(posedge clk_i) begin
  if (rst_i) w_pending_q <= 1'b0;
  else if (w_fire && w_last_q) w_pending_q <= 1'b0;
  else if (burst_ready && !w_pending_q) w_pending_q <= 1'b1;  // NOT data_available
end
assign m_axi_wvalid = w_pending_q;
// w_data_q loaded from FWFT buffer (combinational), popped on w_fire

// B channel: count outstanding responses
reg [7:0] b_outstanding_q;
always @(posedge clk_i) begin
  if (rst_i) b_outstanding_q <= 8'd0;
  else case ({aw_fire, b_fire})
    2'b10: b_outstanding_q <= b_outstanding_q + 1'b1;
    2'b01: b_outstanding_q <= b_outstanding_q - 1'b1;
    default: ;
  endcase
end
assign m_axi_bready = 1'b1;  // always accept B
assign all_done = (b_outstanding_q == 8'd0) && all_w_sent;
```

Key properties:
- AW can be accepted before W data is ready when the design has independent W command/data tracking
- W can stall independently of AW; every presented W beat holds payload stable until `WREADY`
- This example uses continuous/full-burst-buffered W mode as a conservative local policy
- B is always accepted (no backpressure from master to slave on B)
- Completion requires `b_outstanding_q == 0` after all W beats sent
- Data FIFO must use FWFT output (combinational read) — see `references/rtl/fifo-examples.md`

### Complete write engine module template

This is the reference architecture for any AXI write master. Use it as the starting point — do NOT design a write engine from scratch using a sequential AW→W→B FSM.

```
Write engine architecture (no single FSM for AW+W+B):
┌─────────────────────────────────────────────────┐
│  Burst command FIFO (from burst planner)         │
│  {addr, len, cid}                                │
└──────────────┬──────────────────────────────────┘
               │ burst_valid / burst_ready
               ▼
┌──────────────────────────────────────────────────┐
│  AW controller (pending register)                │
│  aw_pending_q: set on burst accept, clear on fire│
│  aw_addr_q, aw_len_q: loaded on burst accept     │
│  AWVALID = aw_pending_q                          │
│  Can issue: !aw_pending_q && outstanding < MAX   │
└──────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────┐
│  W controller (beat counter + per-beat hold)     │
│  w_active_q: set by selected W data mode         │
│  w_beat_cnt_q: counts beats, WLAST on count==0   │
│  WVALID holds each presented beat until WREADY   │
│  Data from FWFT FIFO, popped on W fire           │
└──────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────┐
│  B outstanding counter (independent of AW/W)     │
│  b_outstanding_q: inc on AW fire, dec on B fire  │
│  BREADY = 1 (always accept)                      │
│  Completion: outstanding==0 && all bursts issued  │
└──────────────────────────────────────────────────┘
```

**Critical difference from read engine:** The read engine's FSM (IDLE→AR→RDATA) is correct because R data naturally follows AR. The write engine MUST NOT follow the same pattern (IDLE→AW→WDATA→BRESP) because:
- B response may arrive long after WLAST — blocking the FSM in S_BRESP prevents issuing the next AW
- W data may be ready before or after AW — coupling W to S_WDATA prevents independent flow
- Multiple bursts should be pipelined — a sequential FSM forces burst-at-a-time

**Full write engine template:**
```verilog
module axi_wr_engine #(
    parameter ADDR_WIDTH = 32, DATA_WIDTH = 256,
    parameter BUS_BYTES = DATA_WIDTH/8, MAX_OUTSTANDING = 16
)(
    input  wire clk_i, rst_i,
    // Burst command input (from FIFO)
    input  wire                    cmd_valid_i,
    output wire                    cmd_ready_o,
    input  wire [ADDR_WIDTH-1:0]  cmd_addr_i,
    input  wire [7:0]             cmd_len_i,
    input  wire                   cmd_wdata_ready_i,  // continuous mode: full burst buffered
    // Data FIFO
    input  wire [DATA_WIDTH-1:0]  dfifo_rdata_i,
    input  wire                   dfifo_empty_i,
    output wire                   dfifo_rd_en_o,
    // AXI AW
    output reg  [ADDR_WIDTH-1:0]  m_axi_awaddr_o,
    output reg  [7:0]             m_axi_awlen_o,
    output reg                    m_axi_awvalid_o,
    input  wire                   m_axi_awready_i,
    // AXI W
    output wire [DATA_WIDTH-1:0]  m_axi_wdata_o,
    output reg  [BUS_BYTES-1:0]  m_axi_wstrb_o,
    output reg                    m_axi_wlast_o,
    output reg                    m_axi_wvalid_o,
    input  wire                   m_axi_wready_i,
    // AXI B
    input  wire [1:0]             m_axi_bresp_i,
    input  wire                   m_axi_bvalid_i,
    output wire                   m_axi_bready_o
);
    wire aw_fire = m_axi_awvalid_o & m_axi_awready_i;
    wire w_fire  = m_axi_wvalid_o  & m_axi_wready_i;
    wire b_fire  = m_axi_bvalid_i  & m_axi_bready_o;

    // ── AW controller: independent pending register ──
    wire can_issue_aw  = !m_axi_awvalid_o && (b_outstanding_q < MAX_OUTSTANDING);
    wire can_accept_cmd = can_issue_aw && cmd_wdata_ready_i;
    assign cmd_ready_o = can_accept_cmd;

    always @(posedge clk_i) begin
        if (rst_i) m_axi_awvalid_o <= 1'b0;
        else if (aw_fire) m_axi_awvalid_o <= 1'b0;
        else if (cmd_valid_i && can_accept_cmd) m_axi_awvalid_o <= 1'b1;
    end
    always @(posedge clk_i) begin
        if (cmd_valid_i && can_accept_cmd) begin
            m_axi_awaddr_o <= cmd_addr_i;
            m_axi_awlen_o  <= cmd_len_i;
        end
    end

    // ── W controller: independent beat counter ──
    reg [7:0] w_beat_cnt_q;

    // Continuous-mode W policy: local conservative pattern, not an AXI hard rule.
    // Pre-condition: cmd_wdata_ready_i guarantees the full burst is buffered.
    always @(posedge clk_i) begin
        if (rst_i) m_axi_wvalid_o <= 1'b0;
        else if (w_fire && m_axi_wlast_o) m_axi_wvalid_o <= 1'b0;
        else if (cmd_valid_i && can_accept_cmd) m_axi_wvalid_o <= 1'b1;
    end

    // Beat counter: load on burst accept, decrement on W fire
    always @(posedge clk_i) begin
        if (rst_i) w_beat_cnt_q <= 8'd0;
        else if (cmd_valid_i && can_accept_cmd) w_beat_cnt_q <= cmd_len_i;
        else if (w_fire) w_beat_cnt_q <= w_beat_cnt_q - 1'b1;
    end

    // WLAST
    always @(posedge clk_i) begin
        if (rst_i) m_axi_wlast_o <= 1'b0;
        else if (w_fire && w_beat_cnt_q == 8'd1) m_axi_wlast_o <= 1'b1;
        else if (w_fire && m_axi_wlast_o) m_axi_wlast_o <= 1'b0;
    end

    assign m_axi_wdata_o = dfifo_rdata_i;  // FWFT: combinational, no read latency
    assign dfifo_rd_en_o = w_fire;

    // ── B outstanding counter: independent ──
    reg [7:0] b_outstanding_q;
    always @(posedge clk_i) begin
        if (rst_i) b_outstanding_q <= 8'd0;
        else case ({aw_fire, b_fire})
            2'b10: b_outstanding_q <= b_outstanding_q + 1'b1;
            2'b01: b_outstanding_q <= b_outstanding_q - 1'b1;
            default: ;
        endcase
    end
    assign m_axi_bready_o = 1'b1;
endmodule
```

**Why this works:**
- AW fires as soon as burst command arrives and outstanding allows — no waiting for W or B
- W starts independently when data is available — no waiting for AW to complete first
- B is always accepted — no FSM state blocking B collection
- Multiple bursts can be pipelined: next AW fires while previous W is still in progress

## Anti-pattern: burst_ready blocked by B response

Making `burst_ready_o` depend on `waiting_for_b_q` (whether the previous burst's B response has arrived) re-couples channels at the burst level, defeating the purpose of independent AW/W/B control.

AXI protocol supports multiple outstanding transactions (IHI0022E Section A5.3). Industrial DMA engines (Xilinx CDMA, ARM DMA-330, Linux DMA engine framework) all use outstanding counters, not B-blocking flow control.

**Wrong pattern:**
```verilog
// Blocks new burst until previous B arrives
assign burst_ready_o = ~aw_pending_q & ~w_active_q & ~waiting_for_b_q;
```

**Correct pattern: use outstanding counter**
```verilog
// Allow new burst if outstanding count is below limit
assign burst_ready_o = ~aw_pending_q & ~w_active_q & (b_outstanding_q < MAX_OUTSTANDING);
```

This allows the burst planner to feed new bursts while B responses are still in flight, matching the read master's `ar_outstanding_q` pattern.

## Anti-pattern: W data mode is implicit or under-specified

The pattern `WVALID = w_active_q && data_available` (where `data_available = !fifo_empty`) is not automatically an AXI violation. It is wrong when the design claims continuous/full-burst-buffered W mode but still allows the FIFO to empty before `WLAST`. In elastic/per-beat mode, the same gating may be legal, but it must hold each presented beat stable while `!WREADY` and must not drop accepted data.

**Bug pattern for continuous mode:**
```verilog
// BUG in continuous mode: WVALID can gap before WLAST
wire data_available = !dfifo_empty_i;
always @(posedge clk_i) begin
    if (rst_i) m_axi_wvalid_o <= 1'b0;
    else       m_axi_wvalid_o <= w_active_q && data_available;
end
```

**Correct pattern for continuous mode: burst-ready gate**

In continuous mode, `WVALID` depends only on the active burst state once the burst starts. The full-burst-ready check happens before the burst is accepted:

```verilog
// Pre-burst: check FIFO has enough data for the full burst
wire burst_ready = (dfifo_count >= burst_length) && !w_active_q;

// WVALID: continuous local policy, depends on w_active_q after burst start
always @(posedge clk_i) begin
    if (rst_i) m_axi_wvalid_o <= 1'b0;
    else if (w_fire && m_axi_wlast_o) m_axi_wvalid_o <= 1'b0;  // burst ends
    else if (burst_start) m_axi_wvalid_o <= 1'b1;               // burst starts
    // Local policy: no WVALID gaps until WLAST
end

// Data FIFO read: FWFT output, popped on W fire
assign m_axi_wdata_o = dfifo_rdata;  // combinational (FWFT)
assign dfifo_rd_en_o = w_fire;
```

**Why this works:**
- `burst_ready` guarantees FIFO has enough data BEFORE WVALID asserts
- Once WVALID asserts, this local policy holds it until WLAST
- FWFT FIFO output provides data combinationally, no read latency
- If FIFO depth >= max burst length, `burst_ready` simplifies to `!w_active_q`

**Correct pattern for elastic mode: per-beat availability with sticky presented beat**

```verilog
// Elastic mode: bubbles between accepted W beats are allowed by the local contract.
// Once a beat is presented, it remains presented until WREADY.
always @(posedge clk_i) begin
    if (rst_i) begin
        m_axi_wvalid_o <= 1'b0;
    end else if (m_axi_wvalid_o && !m_axi_wready_i) begin
        m_axi_wvalid_o <= 1'b1;        // hold current beat
    end else if (have_next_wbeat) begin
        m_axi_wvalid_o <= 1'b1;        // present next beat
    end else begin
        m_axi_wvalid_o <= 1'b0;        // legal bubble between beats
    end
end

assign dfifo_rd_en_o = have_next_wbeat && (!m_axi_wvalid_o || m_axi_wready_i);
```

Elastic mode still needs assertions for per-beat stability, FIFO underflow prevention, correct `WLAST`, and local liveness if the system cannot tolerate unbounded gaps.

**When FIFO depth >= max burst length:**
If the FIFO is always large enough (e.g., depth=1024, max burst=256), the `fifo_count >= burst_length` check is always true. In this case, simplify to:
```verilog
wire burst_ready = !w_active_q;  // FIFO always has enough data
```

## Anti-pattern: read/write command paths coupled

A common architecture mistake is coupling read and write command paths at the burst planner level:

**Wrong pattern:**
```verilog
// Top-level: both must be ready before any burst issues
assign burst_ready = burst_ready_rd & burst_ready_wr;
// Burst planner issues ONE burst signal that goes to BOTH rd_master and wr_master
```

This blocks the fast direction when the slow direction stalls. If read data returns quickly but write responses are delayed, the read channel sits idle waiting for the write channel to become ready.

**Correct pattern: independent read/write command paths**

The burst planner issues **separate** read and write burst commands, each with its own valid/ready handshake:

```verilog
// Burst planner output: two independent command streams
wire rd_burst_valid, rd_burst_ready;
wire wr_burst_valid, wr_burst_ready;

// Read path: issues AR commands as fast as source allows
assign rd_burst_ready = ~ar_pending_q & (ar_outstanding_q < MAX_OUTSTANDING);

// Write path: issues AW commands only when FIFO has data
assign wr_burst_ready = ~aw_pending_q & (b_outstanding_q < MAX_OUTSTANDING) & ~fifo_empty;
```

The FIFO between read and write paths naturally decouples them:
- Read path issues commands and fills FIFO independently
- Write path issues commands only when data is available in FIFO
- Each path has its own outstanding counter and flow control

**Authoritative references:**
- **ARM PL330** (DDI 0441): "Each DMA channel is split into two half-channels: a read channel (RD) and a write channel (WD). These half-channels operate independently and concurrently."
- **Xilinx CDMA** (PG034): "The AXI CDMA uses separate AXI4 master interfaces for read and write operations... An internal data buffer/FIFO sits between the read and write channels, decoupling the two sides."
- **Linux DMAengine**: Each channel manages descriptors independently; direction is per-channel, not per-descriptor.

## Completion tracker design

For ordered DMA completion, use a single FIFO-based tracker:

```verilog
// Each entry: {valid, burst_count, error}
// alloc_ptr: advances on command accept
// done_ptr: advances when entry.valid && entry.burst_count == 0
// burst_count: incremented on burst_alloc, decremented on burst_done

// Key invariant: alloc_ptr >= done_ptr (modular)
// Completion: entry at done_ptr has burst_count == 0 → pulse done_o, advance done_ptr
// Error: captured per-entry from B response, reported on completion
```

Avoid three independent pointers (alloc, burst, done) without a clear ordering invariant — they can desynchronize if burst_alloc and burst_done arrive out of expected order.

### Completion FIFO pattern (ordered done output)

When multiple commands can be in-flight, use a completion FIFO to maintain ordered done output:

```verilog
// Write engine pushes {error} to completion FIFO when command completes
// Top level pops from FIFO and generates cdma_done_o pulse
// Error flag is per-entry: comp_rdata indicates if this command had an error

assign comp_pop = ~comp_empty;  // pop when FIFO has entries
always @(posedge clk_i) begin
    if (rst_i) cdma_done_o <= 1'b0;
    else       cdma_done_o <= comp_pop;  // 1-cycle pulse per command
end

// Sticky global error: set on any error, clear only on reset
always @(posedge clk_i) begin
    if (rst_i) cdma_error_o <= 1'b0;
    else if (comp_pop && comp_rdata) cdma_error_o <= 1'b1;
    else if (rd_error || wr_error)   cdma_error_o <= 1'b1;
end
```

**Why this works:** the FIFO naturally enforces ordering — the first command pushed is the first popped. Done pulses appear in command-input order regardless of which command's B responses arrived first.
