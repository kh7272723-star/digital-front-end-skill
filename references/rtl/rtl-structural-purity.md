# RTL Structural Purity - FSM/Datapath Gate

## Purpose

Prevent the most persistent structural bug class in this skill's RTL output:
FSM/datapath boundary violations. These bugs often compile and pass narrow
directed simulation, but they create hidden coupling, NBA ordering hazards, and
unmaintainable control flow.

Use this reference before writing RTL and during Step 8 self-review.

## Three Allowed Block Types

Every `always` block and every state-related `assign` must fit one of these
roles.

| Block type | Owns | Must not touch |
| --- | --- | --- |
| State register | `cstate <= nstate` only | Datapath registers, payload, counters, sideband, output registers |
| Combinational control decode | `nstate` and single-bit control signals | Multi-bit addresses, byte counts, data, pointers, indices, next datapath values |
| Datapath sequential | Counters, addresses, payload, pointers, byte/beat cursors, FIFO state, status flags | `cstate`, `nstate`, `S_*` state constants |

The design may be in one source file or split across files. The same separation
still applies.

## Hard Rules

### RSP1 (M): State Register Block Has One Job

The FSM sequential block must update only the state register.

Correct:

```verilog
always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        cstate <= S_IDLE;
    end else begin
        cstate <= nstate;
    end
end
```

Forbidden:

```verilog
always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        cstate <= S_IDLE;
        byte_cnt_q <= 32'b0;       // datapath mixed into state block
    end else begin
        cstate <= nstate;
        if (page_accept) begin
            byte_cnt_q <= byte_cnt_q + 32'd8;
        end
    end
end
```

If an `always @(posedge clk)` block contains `cstate <= nstate`, no other
nonblocking assignment is allowed in that block except reset assignment to
`cstate`.

### RSP2 (M): FSM Combinational Block Emits Control Only

The FSM combinational block may assign:

- `nstate`
- single-bit controls such as `*_en`, `*_clr`, `*_fire`, `*_load`, `*_start`,
  `*_done`
- simple single-bit output decodes from state, such as
  `assign done_o = (cstate == S_DONE)`

It must not assign multi-bit datapath values.

Forbidden:

```verilog
always @(*) begin
    nstate = cstate;
    page_valid_o = 1'b0;
    page_addr_n = 64'b0;        // multi-bit datapath
    page_bytes_n = 17'b0;       // multi-bit datapath

    case (cstate)
        S_PAGE_TX: begin
            page_valid_o = 1'b1;
            page_addr_n = page_base_q + page_offset_q;
            page_bytes_n = bytes_left_q;
        end
    endcase
end
```

Correct:

```verilog
always @(*) begin
    nstate = cstate;
    page_tx_en = 1'b0;
    load_prp_entry_en = 1'b0;

    case (cstate)
        S_PAGE_TX: begin
            page_tx_en = 1'b1;
            if (page_accept) begin
                nstate = S_NEXT;
            end
        end
    endcase
end
```

### RSP3 (M): Datapath Sequential Blocks Do Not Read State IDs

Datapath update blocks must be driven by named control signals, not direct state
checks.

Forbidden:

```verilog
always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        current_addr_q <= 64'b0;
    end else begin
        case (cstate)
            S_PAGE_TX: begin
                if (page_accept) begin
                    current_addr_q <= current_addr_q + 64'd4096;
                end
            end
        endcase
    end
end
```

Correct:

```verilog
always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        current_addr_q <= 64'b0;
    end else begin
        if (page_tx_en && page_accept) begin
            current_addr_q <= current_addr_q + 64'd4096;
        end
    end
end
```

### RSP4 (M): Datapath Ownership Inventory

These belong in datapath sequential blocks only:

- byte, beat, entry, and burst counters
- source and destination address registers
- global byte cursors and per-page cursors
- payload and sideband registers
- FIFO memory, pointers, count, and status
- PRP list buffer indices
- descriptor or command field registers
- error, done, and busy sticky flags, unless they are pure one-state decodes

### RSP5 (M): Named Accepted-Operation Conditions

Every datapath update must be gated by a named condition that declares the
accepted operation.

Correct:

```verilog
wire cmd_accept  = cmd_valid_i && cmd_ready_o;
wire page_accept = page_valid_i && page_ready_o;
wire aw_fire     = axi_aw_valid_o && axi_aw_ready_i;
wire w_fire      = axi_w_valid_o && axi_w_ready_i;
wire nvm_read_do = nvm_rd_en_o;

always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        nvm_global_offset_bytes_q <= 32'b0;
    end else if (start_i) begin
        nvm_global_offset_bytes_q <= 32'b0;
    end else if (nvm_read_do) begin
        nvm_global_offset_bytes_q <= nvm_global_offset_bytes_q + 32'd8;
    end else begin
        nvm_global_offset_bytes_q <= nvm_global_offset_bytes_q;
    end
end
```

Forbidden:

```verilog
always @(posedge clk_i) begin
    if (cstate == S_PAGE_TX && page_valid_i && page_ready_o) begin
        nvm_offset_q <= nvm_offset_q + 32'd8;
    end
end
```

### RSP6 (S): Unit and Width Discipline

Physical quantities must carry their unit in the name.

| Suffix | Meaning | Example |
| --- | --- | --- |
| `_bytes` | bytes | `total_bytes_i`, `bytes_left_q` |
| `_beats` | AXI data beats | `aw_beats_left_q` |
| `_entries` | table or buffer entries | `list_entries` |
| `_len` | AXI AxLEN, meaning beats minus one | `aw_len_q` |

Conversions must be explicit and named.

```verilog
localparam BUS_BYTES = AXI_DATA_W / 8;
localparam BUS_LG_BYTES = $clog2(BUS_BYTES);

wire [16:0] page_total_beats;
assign page_total_beats = page_bytes_i >> BUS_LG_BYTES;
```

### RSP7 (S): No Fake Parameterization

If a parameter defines capacity or width, dependent arrays, pointer widths, loop
bounds, and burst lengths must derive from it or declare a waiver.

Forbidden:

```verilog
parameter LIST_ENTRIES = 512;
reg [63:0] list_buf [0:63];
reg [5:0] list_idx_q;
assign list_ar_len_o = 8'd63;
```

Correct:

```verilog
parameter LIST_ENTRIES = 512;
localparam LIST_IDX_W = $clog2(LIST_ENTRIES);
localparam LIST_BUF_DEPTH = LIST_ENTRIES;

reg [63:0] list_buf [0:LIST_BUF_DEPTH-1];
reg [LIST_IDX_W-1:0] list_idx_q;
```

If the hardware intentionally caches only part of a protocol structure, name the
limit and document it:

```verilog
parameter LIST_ENTRIES = 512;
localparam LIST_CACHE_ENTRIES = 64;  // waiver: one-burst cache, no list chaining
```

## RSP3a (M): Datapath Done/Clear Uses Named Controls, Not State Equality

Datapath logic that clears, completes, or resets a value must use a named
`*_clr_en` or `*_set_en` control signal from the FSM combinational decode,
not a direct `cstate == S_DONE` comparison in the datapath block.

Forbidden:

```verilog
// datapath block — no cstate/S_* references
always @(posedge clk_i) begin
    if (cstate == S_DONE)        // ❌ state equality in datapath
        byte_cnt_q <= 32'b0;
end
```

Correct:

```verilog
// FSM combinational decode
always @(*) begin
    done_clr_en = 1'b0;
    case (cstate)
        S_DONE: done_clr_en = 1'b1;
    endcase
end

// datapath block — driven by named control
always @(posedge clk_i) begin
    if (done_clr_en)             // ✅ named control signal
        byte_cnt_q <= 32'b0;
end
```

## Comment-Only Compliance Is Invalid

If a file contains comments claiming RSP3/RSP compliance (e.g. "RSP3 compliant",
"structural purity pass", "no cstate in datapath") but the checker still fires
RSP3, the finding is upgraded to E-level. Comments do not override code evidence.
A waiver requires the formal waiver format below, not a prose assertion.

## Waiver Format

Any exception to RSP1-RSP4 requires a waiver in the timing contract or review
log:

```text
Waiver:
- Signal/block:
- Rule waived:
- Reason:
- Risk:
- Verification coverage:
- Residual limitation:
```

Waivers are not a way to avoid the rule. They are used only for intentional,
bounded, reviewed deviations.

## Step 8 Checklist

- [ ] RSP1: each FSM state-register block updates only `cstate`.
- [ ] RSP2: each FSM combinational block assigns only `nstate` and single-bit controls.
- [ ] RSP3: datapath sequential blocks do not reference `cstate`, `nstate`, or `S_*`.
- [ ] RSP4: counters, addresses, payload, pointers, byte cursors, and FIFO state are datapath-owned.
- [ ] RSP5: every datapath update uses a named accepted-operation condition.
- [ ] RSP6: bytes, beats, entries, and AxLEN values are named by unit and converted explicitly.
- [ ] RSP7: parameter-dependent structures are actually derived from parameters, or waivered.
- [ ] Any waiver includes signal, rule, reason, risk, coverage, and limitation.
