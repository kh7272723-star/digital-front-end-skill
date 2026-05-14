# Content-addressable memory (CAM) patterns

## Source authority

This file distills patterns from standard cache and TCAM architecture as documented in:
- **Xilinx CAM inference guides** (UG901, UG901 Synthesis Guide, CAM using Block RAM + LUT)
- **Standard digital design textbooks** for associative memory structures
- **FPGA vendor application notes** on binary CAM and ternary CAM (TCAM) inference

CAMs are standard hardware structures for address lookup, packet classification, cache tag comparison, and translation lookaside buffers (TLBs).

## When to use a CAM

Use when:
- A data value must be searched across multiple entries in a single cycle (associative lookup).
- Exact-match search is needed (binary CAM) or wildcard/prefix matching is needed (ternary CAM).
- The number of entries is small enough that full parallel comparison is feasible (<256 entries typical for LUT-based CAM).

Do NOT use when:
- The lookup key has a known hash function that maps to a small table — use a hash table or direct-mapped memory.
- Entry count is large (>1024) and latency can be >1 cycle — use a RAM with iterative search.
- Only one entry needs to be checked — a simple comparator suffices.

## 1. Binary CAM (exact match)

All entries compared against the search key in parallel. Outputs the matching entry index (or "not found").

```verilog
module binary_cam #(
  parameter NUM_ENTRIES = 16,
  parameter KEY_W       = 32,
  parameter ENTRIES_W   = 5    // ceil(log2(NUM_ENTRIES+1)), +1 for invalid
) (
  input  wire                    clk,
  input  wire                    rst,

  // search port
  input  wire                    search_valid_i,
  input  wire [KEY_W-1:0]        search_key_i,
  output wire                    match_valid_o,   // 1 = found
  output wire [ENTRIES_W-1:0]    match_index_o,

  // write port (update an entry)
  input  wire                    wr_en_i,
  input  wire [ENTRIES_W-1:0]    wr_addr_i,
  input  wire [KEY_W-1:0]        wr_data_i,
  output wire                    wr_ready_o
);

  reg  [KEY_W-1:0]   cam_mem [0:NUM_ENTRIES-1];
  reg  [NUM_ENTRIES-1:0] valid_entry;     // per-entry valid bit

  // search: parallel compare
  wire [NUM_ENTRIES-1:0] match_vec;
  wire                   any_match;

  genvar g;
  generate
    for (g = 0; g < NUM_ENTRIES; g = g + 1) begin : g_match
      assign match_vec[g] = valid_entry[g] && (cam_mem[g] == search_key_i);
    end
  endgenerate

  assign any_match = |match_vec;

  // priority encoder: find first matching entry
  wire [ENTRIES_W-1:0] match_idx;
  priority_encoder #(
    .IN_W(NUM_ENTRIES),
    .OUT_W(ENTRIES_W)
  ) u_pe (
    .onehot_i(match_vec),
    .index_o (match_idx),
    .valid_o ()    // any_match already tells us
  );

  assign match_valid_o = search_valid_i && any_match;
  assign match_index_o = any_match ? match_idx : {ENTRIES_W{1'b0}};

  // write: always ready (single-cycle write)
  assign wr_ready_o = 1'b1;

  integer entry_idx;
  always @(posedge clk) begin
    if (rst) begin
      for (entry_idx = 0; entry_idx < NUM_ENTRIES; entry_idx = entry_idx + 1) begin
        valid_entry[entry_idx] <= 1'b0;
      end
    end else if (wr_en_i) begin
      cam_mem[wr_addr_i]      <= wr_data_i;
      valid_entry[wr_addr_i]  <= 1'b1;
    end
  end

endmodule

// simple priority encoder (LSB has highest priority)
module priority_encoder #(
  parameter IN_W  = 16,
  parameter OUT_W = 5
) (
  input  wire [IN_W-1:0]  onehot_i,
  output wire [OUT_W-1:0] index_o,
  output wire             valid_o
);
  reg [OUT_W-1:0] idx;
  integer i;
  always @(*) begin
    idx = {OUT_W{1'b0}};
    for (i = 0; i < IN_W; i = i + 1) begin
      if (onehot_i[i])
        idx = i[OUT_W-1:0];
    end
  end
  assign index_o = idx;
  assign valid_o = |onehot_i;
endmodule
```

### Synthesis notes
- Binary CAM with NUM_ENTRIES=16, KEY_W=32 uses ~16 × 32 = 512 XOR bits + priority encoder. Fits in ~200-300 LUTs.
- For NUM_ENTRIES > 128, consider using Block RAM for storage + pipelined comparison (multi-cycle).
- The priority encoder is the critical path for large NUM_ENTRIES — pipeline after match_vec if timing fails.

### Contract

| Decision | Value |
|----------|-------|
| Search latency | 1 cycle (combinational search from registered CAM entries) |
| Write latency | 1 cycle (write on next posedge) |
| Write policy | Always ready; writes overwrite the addressed entry |
| Match priority | LSB (entry 0) has highest priority when multiple entries match |
| Invalid entries | `valid_entry` bit prevents false matches to unwritten entries |
| Search during write | Newly written data is visible on the NEXT cycle (registered memory) |

## 2. Ternary CAM (wildcard match)

TCAM adds a per-entry mask: each bit can be 0, 1, or "don't care" (X). Used in packet classification (ACL rules, route prefix matching).

Each entry stores: `{data, mask}`. A match occurs when `(key & mask) == (data & mask)`.

```verilog
module ternary_cam #(
  parameter NUM_ENTRIES = 16,
  parameter KEY_W       = 32
) (
  input  wire                    clk,
  input  wire                    rst,

  input  wire                    search_valid_i,
  input  wire [KEY_W-1:0]        search_key_i,
  output wire                    match_valid_o,
  output wire [$clog2(NUM_ENTRIES)-1:0] match_index_o,

  input  wire                    wr_en_i,
  input  wire [$clog2(NUM_ENTRIES)-1:0] wr_addr_i,
  input  wire [KEY_W-1:0]        wr_data_i,
  input  wire [KEY_W-1:0]        wr_mask_i,   // 0 = don't care for that bit
  output wire                    wr_ready_o
);

  reg  [KEY_W-1:0]   tcam_data [0:NUM_ENTRIES-1];
  reg  [KEY_W-1:0]   tcam_mask [0:NUM_ENTRIES-1];
  reg  [NUM_ENTRIES-1:0] valid_entry;

  wire [NUM_ENTRIES-1:0] match_vec;

  genvar g;
  generate
    for (g = 0; g < NUM_ENTRIES; g = g + 1) begin : g_tcam
      wire [KEY_W-1:0] masked_key;
      wire [KEY_W-1:0] masked_data;
      assign masked_key  = search_key_i & tcam_mask[g];
      assign masked_data = tcam_data[g]   & tcam_mask[g];
      assign match_vec[g] = valid_entry[g] && (masked_key == masked_data);
    end
  endgenerate

  assign match_valid_o = search_valid_i && (|match_vec);

  priority_encoder #(
    .IN_W(NUM_ENTRIES),
    .OUT_W($clog2(NUM_ENTRIES))
  ) u_pe (.onehot_i(match_vec), .index_o(match_index_o), .valid_o());

  assign wr_ready_o = 1'b1;

  integer entry_idx;
  always @(posedge clk) begin
    if (rst) begin
      for (entry_idx = 0; entry_idx < NUM_ENTRIES; entry_idx = entry_idx + 1)
        valid_entry[entry_idx] <= 1'b0;
    end else if (wr_en_i) begin
      tcam_data[wr_addr_i]  <= wr_data_i;
      tcam_mask[wr_addr_i]  <= wr_mask_i;
      valid_entry[wr_addr_i] <= 1'b1;
    end
  end

endmodule
```

Pattern rule:
- TCAM doubles the storage per entry (data + mask) compared to binary CAM.
- Mask bits = 0 mean "don't care" for that bit position. Mask = all-1s = exact match.
- Synthesis cost: ~KEY_W × 2 × NUM_ENTRIES bits of storage + ~KEY_W × NUM_ENTRIES × 2 LUTs for comparison.

## Common bugs

| Bug | Symptom | Fix |
|-----|---------|-----|
| Invalid entries match | Search returns garbage after reset | `valid_entry` bit per entry; only valid entries participate in match |
| Multiple match priority | Wrong entry selected when multiple match | Priority encoder with defined priority (LSB-first or programmed priority) |
| Write-read race | Search during write returns stale data | Registered CAM memory: writes visible next cycle. Accept this or add bypass. |
| TCAM mask polarity inverted | Mask=0 should be "don't care" but code treats mask=1 as don't-care | Check mask semantics: `(key & mask) == (data & mask)` → mask=0 means don't care |

## What to capture from CAM examples
- Binary CAM: parallel comparison of all entries, priority encoder for match resolution
- TCAM: adds per-bit mask for wildcard matching (prefix, ACL rules)
- Synthesis: LUT-based for small CAMs (<128 entries); Block RAM + iterative search for large CAMs
- Valid bit per entry prevents false matches to unwritten entries
- Registered CAM memory: search is combinational from registered data
- For >256 entries: pipeline the comparison across multiple cycles ("time-multiplexed CAM")
