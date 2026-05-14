# Full module examples

## Purpose

Use these examples as golden patterns for contract-first RTL.
Each example shows the same sequence: contract, cycle trace, RTL, directed tests, and check ideas.
Prefer these examples over isolated snippets when generating a new block.

## 1. Ready/valid register slice

### Contract

- Single clock: `clk_i`.
- Reset: synchronous active-high `rst_i`.
- Input channel: `valid_i`, `ready_o`, `data_i`.
- Output channel: `valid_o`, `ready_i`, `data_o`.
- Latency: accepted input appears at the output after the active clock edge.
- Stall: while `valid_o && !ready_i`, `valid_o` and `data_o` hold.

### Cycle trace

| Cycle | Pre-edge state | Combinational condition | Active-edge update | Next visible state | Invariant |
| --- | --- | --- | --- | --- | --- |
| reset | `rst_i=1` | reset branch | clear `valid_o` | output invalid | no false output item |
| empty accept | `valid_o=0`, `valid_i=1` | `ready_o=1`, `accept_input=1` | capture `data_i` | `valid_o=1`, `data_o=data_i` | accepted item becomes visible after edge |
| stalled | `valid_o=1`, `ready_i=0` | `ready_o=0` | no update | output unchanged | payload stable while waiting |
| replace | `valid_o=1`, `ready_i=1`, `valid_i=1` | `accept_output=1`, `accept_input=1` | capture next input | next item visible | one item consumed and one item loaded |

### RTL

```verilog
module rv_register_slice #(
  parameter DATA_W = 8
) (
  input  wire              clk_i,
  input  wire              rst_i,
  input  wire              valid_i,
  output wire              ready_o,
  input  wire [DATA_W-1:0] data_i,
  output reg               valid_o,
  input  wire              ready_i,
  output reg  [DATA_W-1:0] data_o
);

wire accept_input;
wire accept_output;

assign accept_output = valid_o && ready_i;
assign ready_o       = !valid_o || accept_output;
assign accept_input  = valid_i && ready_o;

always @(posedge clk_i) begin
  if (rst_i) begin
    valid_o <= 1'b0;
  end else if (ready_o) begin
    valid_o <= valid_i;
    if (accept_input)
      data_o <= data_i;
  end
end

endmodule
```

### Directed tests

- Reset clears `valid_o`.
- One item accepted from empty state appears after the clock edge.
- Downstream stall holds `valid_o` and `data_o`.
- Consecutive transfers under `ready_i=1` maintain one item per cycle.

### Check ideas

- Assert `valid_o && !ready_i` implies stable `data_o` on the next cycle.
- Scoreboard accepted input items against output items.

## 2. Two-entry ready/valid buffer stage

### Contract

- Registered output plus one extra holding entry.
- `ready_o` deasserts only when the extra entry is occupied and downstream is not ready.
- The buffer must not lose or duplicate items when downstream stalls for one or more cycles.

### Cycle trace

| Cycle | Pre-edge state | Combinational condition | Active-edge update | Next visible state | Invariant |
| --- | --- | --- | --- | --- | --- |
| output empty | no output item | `accept_input=1` | load output register | input item visible | empty buffer accepts immediately |
| output stalled | output item valid, extra entry empty | `ready_i=0`, `ready_o=1` | store input in extra entry | output holds, extra entry full | one extra item captured |
| extra full | output item valid, extra entry full | `ready_i=0`, `ready_o=0` | no update | both entries hold | no overwrite |
| drain and refill | output accepted, extra entry full, input valid | `accept_output=1`, `accept_input=1` | move extra entry to output and store new input | order preserved | no bubble when downstream resumes |

### RTL

```verilog
module rv_two_entry_buffer #(
  parameter DATA_W = 8
) (
  input  wire              clk_i,
  input  wire              rst_i,
  input  wire              valid_i,
  output wire              ready_o,
  input  wire [DATA_W-1:0] data_i,
  output reg               valid_o,
  input  wire              ready_i,
  output reg  [DATA_W-1:0] data_o
);

reg               hold_valid_q;
reg [DATA_W-1:0] hold_data_q;

wire output_can_load;
wire accept_input;
wire accept_output;

assign output_can_load = !valid_o || ready_i;
assign ready_o         = !hold_valid_q || ready_i;
assign accept_input    = valid_i && ready_o;
assign accept_output   = valid_o && ready_i;

always @(posedge clk_i) begin
  if (rst_i) begin
    valid_o      <= 1'b0;
    hold_valid_q <= 1'b0;
  end else if (output_can_load) begin
    if (hold_valid_q) begin
      valid_o <= 1'b1;
      data_o  <= hold_data_q;
      if (accept_input) begin
        hold_valid_q <= 1'b1;
        hold_data_q  <= data_i;
      end else begin
        hold_valid_q <= 1'b0;
      end
    end else if (accept_input) begin
      valid_o <= 1'b1;
      data_o  <= data_i;
    end else begin
      valid_o <= 1'b0;
    end
  end else if (accept_input) begin
    hold_valid_q <= 1'b1;
    hold_data_q  <= data_i;
  end
end

endmodule
```

### Directed tests

- Fill output, stall downstream, then accept one more input into the extra entry.
- Keep downstream stalled after the extra entry fills and verify `ready_o=0`.
- Resume downstream while upstream remains valid and verify item ordering.

### Check ideas

- Scoreboard all accepted input items and compare against accepted output items.
- Assert stable `data_o` while `valid_o && !ready_i`.

## 3. Conservative synchronous FIFO

### Contract

- Single clock FIFO.
- `wr_en_i` is accepted only when `full_o=0`.
- `rd_en_i` is accepted only when `empty_o=0`.
- Conservative boundary policy: a write while full is not accepted, even if a read happens in the same cycle.
- Conservative boundary policy: a read while empty is not accepted, even if a write happens in the same cycle.
- Read data is registered and visible after an accepted read.
- Assumption: `DEPTH == 2**ADDR_W`.

### Cycle trace

| Cycle | Pre-edge state | Combinational condition | Active-edge update | Next visible state | Invariant |
| --- | --- | --- | --- | --- | --- |
| empty write | `count_q=0` | `wr_do=1`, `rd_do=0` | write memory, increment write pointer and count | not empty | occupancy matches accepted writes minus reads |
| normal read | `count_q>0` | `rd_do=1` | load `rdata_o`, increment read pointer and decrement count | read data visible | no empty read accepted |
| simultaneous write/read | `0<count_q<DEPTH` | `wr_do=1`, `rd_do=1` | update both pointers, count unchanged | occupancy unchanged | order preserved |
| full write/read | `count_q=DEPTH` | `wr_do=0`, `rd_do=rd_en_i` | optional read only | count decreases if read accepted | full write rejected by contract |

### RTL

```verilog
module sync_fifo #(
  parameter DATA_W  = 8,
  parameter ADDR_W  = 4,
  parameter DEPTH   = (1 << ADDR_W),
  parameter COUNT_W = ADDR_W + 1
) (
  input  wire                clk_i,
  input  wire                rst_i,
  input  wire                wr_en_i,
  input  wire [DATA_W-1:0]   wdata_i,
  input  wire                rd_en_i,
  output reg  [DATA_W-1:0]   rdata_o,
  output wire                full_o,
  output wire                empty_o,
  output wire [COUNT_W-1:0]  count_o
);

reg [DATA_W-1:0]  mem [0:DEPTH-1];
reg [ADDR_W-1:0]  wr_ptr_q;
reg [ADDR_W-1:0]  rd_ptr_q;
reg [COUNT_W-1:0] count_q;

wire wr_do;
wire rd_do;

assign full_o  = (count_q == DEPTH);
assign empty_o = (count_q == {COUNT_W{1'b0}});
assign count_o = count_q;
assign wr_do   = wr_en_i && !full_o;
assign rd_do   = rd_en_i && !empty_o;

always @(posedge clk_i) begin
  if (rst_i) begin
    wr_ptr_q <= {ADDR_W{1'b0}};
    rd_ptr_q <= {ADDR_W{1'b0}};
    count_q  <= {COUNT_W{1'b0}};
  end else begin
    if (wr_do)
      wr_ptr_q <= wr_ptr_q + {{(ADDR_W-1){1'b0}}, 1'b1};
    if (rd_do)
      rd_ptr_q <= rd_ptr_q + {{(ADDR_W-1){1'b0}}, 1'b1};

    case ({wr_do, rd_do})
      2'b10: count_q <= count_q + {{(COUNT_W-1){1'b0}}, 1'b1};
      2'b01: count_q <= count_q - {{(COUNT_W-1){1'b0}}, 1'b1};
      default: count_q <= count_q;
    endcase
  end
end

always @(posedge clk_i) begin
  if (wr_do)
    mem[wr_ptr_q] <= wdata_i;
  if (rd_do)
    rdata_o <= mem[rd_ptr_q];
end

endmodule
```

### Directed tests

- Reset and verify empty, not full, count zero.
- Write one item, read one item, compare output after accepted read.
- Fill to full and verify an extra write is rejected.
- Read to empty and verify an extra read is rejected.
- Exercise simultaneous write/read away from boundaries and verify count holds.

### Check ideas

- Assert `count_o <= DEPTH`.
- Assert no accepted read when `empty_o`.
- Assert no accepted write when `full_o`.
- Scoreboard write order against read order.

## 4. Two-process FSM controller

### Contract

- Reset state is `IDLE`.
- `start_i` is sampled in `IDLE`.
- `done_i` returns the controller from `BUSY` to `DONE`.
- `DONE` asserts `done_o` for one cycle, then returns to `IDLE`.
- Outputs are combinational from current state; register outputs instead if glitch-free outputs are required.

### Cycle trace

| Cycle | Pre-edge state | Combinational condition | Active-edge update | Next visible state | Invariant |
| --- | --- | --- | --- | --- | --- |
| reset | state unknown | reset branch | `state_q=IDLE` | idle outputs | known reset state |
| start | `state_q=IDLE`, `start_i=1` | `state_d=BUSY` | capture next state | busy state visible | start is sampled once |
| wait | `state_q=BUSY`, `done_i=0` | hold busy | state unchanged | still busy | no unintended exit |
| complete | `state_q=BUSY`, `done_i=1` | `state_d=DONE` | capture done state | `done_o=1` | done pulse follows completion |

### RTL

```verilog
module simple_fsm_ctrl (
  input  wire clk_i,
  input  wire rst_i,
  input  wire start_i,
  input  wire done_i,
  output reg  busy_o,
  output reg  done_o
);

localparam [1:0] IDLE = 2'd0;
localparam [1:0] BUSY = 2'd1;
localparam [1:0] DONE = 2'd2;

reg [1:0] state_q;
reg [1:0] state_d;

always @(*) begin
  state_d = state_q;
  busy_o  = 1'b0;
  done_o  = 1'b0;

  case (state_q)
    IDLE: begin
      if (start_i)
        state_d = BUSY;
    end
    BUSY: begin
      busy_o = 1'b1;
      if (done_i)
        state_d = DONE;
    end
    DONE: begin
      done_o  = 1'b1;
      state_d = IDLE;
    end
    default: begin
      state_d = IDLE;
    end
  endcase
end

always @(posedge clk_i) begin
  if (rst_i)
    state_q <= IDLE;
  else
    state_q <= state_d;
end

endmodule
```

### Directed tests

- Reset and verify idle outputs.
- Drive one start and verify transition to busy.
- Hold busy until `done_i`.
- Verify `done_o` is one cycle.
- Force or simulate illegal state if the environment allows and verify recovery policy.

### Check ideas

- Assert reset state is `IDLE`.
- Cover each legal state transition.
- Assert `done_o` is not high for two consecutive cycles in this contract.

## 5. Stallable pipeline stage

### Contract

- One registered stage.
- `stall_i=1` freezes `valid_o`, `data_o`, and any sideband fields.
- `flush_i=1` clears `valid_o`; payload becomes irrelevant while invalid.
- If `flush_i` and `stall_i` conflict, flush has priority in this example.
- Latency is one active clock edge when not stalled.

### Cycle trace

| Cycle | Pre-edge state | Combinational condition | Active-edge update | Next visible state | Invariant |
| --- | --- | --- | --- | --- | --- |
| reset | unknown | reset branch | clear `valid_o` | invalid output | no false item |
| load | not stalled, not flushing | `advance=1` | capture `valid_i` and `data_i` | input visible after edge | valid and data move together |
| stall | `valid_o=1`, data A | `advance=0` | no update | data A remains visible | stage freezes as a unit |
| flush | any state | `flush_i=1` | clear `valid_o` | invalid output | flush wins over stall |

### RTL

```verilog
module stallable_pipeline_stage #(
  parameter DATA_W = 8
) (
  input  wire              clk_i,
  input  wire              rst_i,
  input  wire              valid_i,
  input  wire [DATA_W-1:0] data_i,
  input  wire              stall_i,
  input  wire              flush_i,
  output reg               valid_o,
  output reg  [DATA_W-1:0] data_o
);

wire advance;

assign advance = !stall_i;

always @(posedge clk_i) begin
  if (rst_i) begin
    valid_o <= 1'b0;
  end else if (flush_i) begin
    valid_o <= 1'b0;
  end else if (advance) begin
    valid_o <= valid_i;
    data_o  <= data_i;
  end
end

endmodule
```

### Directed tests

- Reset clears `valid_o`.
- Normal load transfers valid and data after one edge.
- Stall holds valid and data for multiple cycles.
- Flush clears valid even when stalled.

### Check ideas

- Assert `stall_i && !flush_i` implies stable `valid_o` and `data_o`.
- Assert `flush_i` implies `valid_o=0` after the next active edge.
