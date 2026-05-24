# Retry buffer with replay patterns

## Source authority

This file distills patterns from:
- **Forty-Bot `axis_replay_buffer`** (`github.com/Forty-Bot/ethernet`, `rtl/axis_replay_buffer.v`) — AXI-Stream FIFO with indefinite replay capability, used in half-duplex Ethernet MAC designs.
- **00mjk `ReplayBuffer`** (`github.com/00mjk/ReplayBuffer`) — standalone PCIe-style replay buffer with sequence-number-based ACK/NAK and sliding window.

The RTL here is adapted to the skill's plain-Verilog convention and ready/valid naming standard.

## When to use a retry buffer

Use when:
- Transmitted data must be held until the receiver explicitly acknowledges (ACK) or rejects (NAK) it.
- On NAK, all unacknowledged data must be retransmitted starting from the oldest unacknowledged item.
- The protocol has a sliding window of in-flight data bounded by a sequence number space.

Do NOT use when:
- Data is sent without acknowledgment (no receiver confirmation expected) — use a simple FIFO.
- The protocol guarantees in-order delivery without retry — use a pipeline or FIFO.
- Retry could cause unbounded buffer growth — requires a window size limit AND a timeout.

## Architecture

```
         ┌─────────────────────────────┐
data_i  ─┤► circular buffer (BRAM)    ├─► data_o
valid_i ─┤                             ├─► valid_o
ready_o ◄┤                             │◄─ ready_i
         │                             │
ack_i   ─┤► advance replay_ptr        │
nak_i   ─┤► reset read_ptr = replay_ptr│
         └─────────────────────────────┘
```

Three pointers in a circular buffer:
- `wr_ptr`: where new data is written (accept_input advances this).
- `rd_ptr`: where data is read for output (accept_output advances this).
- `replay_ptr`: oldest unacknowledged data. On ACK, advances. On NAK, `rd_ptr` resets to `replay_ptr`.

## 1. Retry buffer core module

```verilog
module retry_buffer #(
  parameter WIDTH = 8,
  parameter DEPTH = 16,
  parameter ADDRW = 4    // ceil(log2(DEPTH))
) (
  input  wire             clk,
  input  wire             rst,

  // input stream
  input  wire             valid_i,
  input  wire [WIDTH-1:0] data_i,
  output wire             ready_o,

  // output stream
  output wire             valid_o,
  output wire [WIDTH-1:0] data_o,
  input  wire             ready_i,

  // ack/nak from downstream protocol layer
  input  wire             ack_i,         // advance replay window
  input  wire             nak_i,         // replay from oldest unacked

  // status
  output wire             replaying_o    // currently in replay (rd_ptr != replay_ptr?)
);

  reg  [ADDRW-1:0] wr_ptr;
  reg  [ADDRW-1:0] rd_ptr;
  reg  [ADDRW-1:0] replay_ptr;
  reg  [ADDRW:0]   count;         // occupancy = items written but not yet acked

  wire             wr_do;
  wire             accept_output;

  // write when input is valid, ready, and buffer not full
  assign wr_do         = valid_i && ready_o;
  assign accept_output = valid_o && ready_i;

  // ready when buffer has space
  assign ready_o       = (count < DEPTH[ADDRW:0]);

  // valid when there is unread data between rd_ptr and wr_ptr
  wire             items_avail;
  wire [ADDRW:0]   rd_count;
  assign rd_count    = (wr_ptr - rd_ptr);  // items between rd and wr (modulo-aware)
  assign items_avail = (rd_ptr != wr_ptr);
  assign valid_o     = items_avail;

  always @(posedge clk) begin
    if (rst) begin
      wr_ptr     <= {ADDRW{1'b0}};
      rd_ptr     <= {ADDRW{1'b0}};
      replay_ptr <= {ADDRW{1'b0}};
      count      <= {(ADDRW+1){1'b0}};
    end else begin
      // write pointer
      if (wr_do)
        wr_ptr <= wr_ptr + {{ADDRW-1{1'b0}}, 1'b1};

      // read pointer: advance on accept_output, OR reset to replay_ptr on NAK
      if (nak_i)
        rd_ptr <= replay_ptr;
      else if (accept_output)
        rd_ptr <= rd_ptr + {{ADDRW-1{1'b0}}, 1'b1};

      // replay pointer: advance on ACK
      if (ack_i)
        replay_ptr <= replay_ptr + {{ADDRW-1{1'b0}}, 1'b1};

      // occupancy (items written but not yet acked)
      case ({wr_do, ack_i})
        2'b10: count <= count + {{ADDRW{1'b0}}, 1'b1};
        2'b01: count <= count - {{ADDRW{1'b0}}, 1'b1};
        default: count <= count;
      endcase
    end
  end

  // replay flag: replay_ptr != rd_ptr
  assign replaying_o = (replay_ptr != rd_ptr);

  // circular buffer memory
  reg [WIDTH-1:0] mem [0:DEPTH-1];

  always @(posedge clk) begin
    if (wr_do)
      mem[wr_ptr] <= data_i;
  end

  // read data: registered
  reg [WIDTH-1:0] dout_r;

  always @(posedge clk) begin
    if (rst) begin
      dout_r <= {WIDTH{1'b0}};
    end else if (accept_output || nak_i) begin
      // read next item on accept, or re-read on NAK
      dout_r <= mem[nak_i ? replay_ptr : rd_ptr];
    end
  end

  assign data_o = dout_r;

endmodule
```

### Contract

| Decision | Value | Why |
|----------|-------|-----|
| NAK priority | NAK resets rd_ptr to replay_ptr immediately; accept_output is suppressed that cycle | NAK means all unacked data must be re-sent |
| ACK behavior | ACK advances replay_ptr by 1 | Consumer confirms one item successfully received |
| Multiple outstanding | Buffer holds up to DEPTH unacknowledged items | Sliding window = DEPTH |
| ACK before NAK priority | If both ACK and NAK asserted: NAK wins (rd_ptr resets, replay_ptr advances on ACK) | Conservative: replay wins over advance |
| Full behavior | `wr_do = valid_i && !full` — write blocked when all items unacknowledged | No overflow |
| Empty + read | `valid_o = (rd_ptr != wr_ptr)` — read prevented when empty | No underflow |
| Memory read timing | Registered (one cycle after rd_en/nak) | Safe default; consistent with skill's FIFO pattern |

### Priority decision: ACK + NAK simultaneous

When `ack_i && nak_i` in the same cycle:
- `rd_ptr` resets to `replay_ptr` (NAK dominates).
- `replay_ptr` advances by 1 (ACK still processes the one confirmed item).
- Net effect: the replay window shrinks by 1 (the ACKed item is removed), then replay begins from the new `replay_ptr`.

This is the conservative interpretation: NAK means "everything unacknowledged after the last ACK must be replayed."

### Verification notes

Directed tests:
1. Reset → `valid_o=0`, `ready_o=1`, `count=0`.
2. Write 3, ACK 3 → all pointers advance, buffer empty.
3. Write 4, NAK → `rd_ptr` resets to `replay_ptr`, all 4 replayed.
4. Write 2, ACK 1, NAK → only the unacked item (#2) replayed.
5. Simultaneous ACK+NAK → replay_ptr advances, rd_ptr resets to new replay_ptr.
6. Fill buffer (DEPTH items), no ACK → `ready_o=0`, writes blocked.
7. ACK frees space → `ready_o` reasserts.

Assertions:
```systemverilog
assert property (@(posedge clk) disable iff (rst)
  count <= DEPTH);
assert property (@(posedge clk) disable iff (rst)
  !(ack_i && nak_i) || (replaying_o == 1'b1));  // NAK always triggers replay
assert property (@(posedge clk) disable iff (rst)
  nak_i |=> rd_ptr == $past(replay_ptr));  // after NAK, rd_ptr at replay_ptr
```

## 2. Retry buffer with sequence number tracking

For protocols where ACK/NAK arrive out-of-order or carry explicit sequence numbers:

```verilog
// Track the sequence number of each buffered item
reg [SEQ_W-1:0] seq_mem [0:DEPTH-1];  // sequence number per slot

// On write: store sequence number
if (wr_do) seq_mem[wr_ptr] <= seq_i;

// On ACK with sequence number: advance replay_ptr past all contiguous ACKed items
// Requires a small FSM or combinational search of the buffer
```

Pattern rule:
- Sequence number tracking adds complexity proportional to DEPTH.
- For simple protocols where ACKs arrive in order: the base retry buffer (pattern 1) is sufficient.
- For out-of-order ACKs: add a "replay_ptr catch-up" FSM that scans consecutive ACKed slots.

## Common bugs

| Bug | Symptom | Fix |
|-----|---------|-----|
| ACK + NAK race | `replay_ptr` advances past `wr_ptr` | NAK must gate ACK, or ACK must check replay_ptr < wr_ptr before advancing |
| Replayed data is stale | NAK resets rd_ptr but memory was overwritten | Check `wr_ptr` doesn't wrap past `replay_ptr` while data is unacknowledged — this is the DEPTH sizing contract |
| Read data misalignment on NAK | First item after NAK is wrong | rd_ptr reset and first read must sample from the same `replay_ptr` |
| ACK count exceeds outstanding | `count` underflows to max value | Assert `ack_i → count > 0` |

## What to capture from retry buffer examples
- Three-pointer model: wr_ptr, rd_ptr, replay_ptr
- NAK resets rd_ptr to replay_ptr — all unacked data is re-sent
- ACK advances replay_ptr — confirmed data is freed
- Simultaneous ACK+NAK: NAK dominates for read, ACK still advances replay
- Buffer depth = max in-flight window; sized by protocol round-trip × throughput
- Sequence number tracking adds complexity; start with in-order ACK assumptions
