# NVMe I/O Data Path — System Contract

## Project Scope

NVM Read command (OPC=02h) data path: PRP traversal → NVM SRAM read → AXI write to host memory → CQE post.

**Out of scope for Phase 3:** NVM Write (OPC=01h), Flush (OPC=00h), multiple I/O queues, MSI-X interrupts.

## Clock & Reset

- Single clock domain: `clk_i` (assume 250 MHz)
- Active-low async reset: `rst_ni`
- All registers reset to known values (P3)

## Module Inventory

| Module | Type | Est. Lines | Source |
|--------|------|:---:|--------|
| `nvme_cmd_tracker` | NEW | ~200 | — |
| `nvme_prp_walker` | NEW | ~350 | — |
| `nvme_read_engine` | NEW | ~300 | — |
| `nvme_axi_adapter` | EXTEND | 126→250 | Phase 1 |
| `nvme_io_top` | EXTEND (from ctrl_top) | ~250 | Phase 1 |
| `nvme_sq_fetch` | REUSE | 297 | Phase 1 |
| `nvme_cq_post` | REUSE | 253 | Phase 1 |
| `nvme_reg_file` | REUSE | 189 | Phase 1 |

---

## 1. nvme_cmd_tracker — Interface Contract

### Purpose
Track up to 4 outstanding NVM I/O commands. FIFO-ordered issue to PRP walker + read engine. Completion aggregation.

### Port List

```verilog
module nvme_cmd_tracker #(
    parameter NUM_SLOTS = 4,
    parameter LBA_SIZE  = 512   // bytes per logical block
) (
    input  wire         clk_i,
    input  wire         rst_ni,

    // ── Command input (from top-level demux) ──
    input  wire         cmd_valid_i,
    output wire         cmd_ready_o,
    input  wire [7:0]   cmd_opcode_i,      // OPC=02h (Read)
    input  wire [15:0]  cmd_cid_i,         // Command ID
    input  wire [31:0]  cmd_nsid_i,        // Namespace ID
    input  wire [63:0]  cmd_prp1_i,        // PRP Entry 1
    input  wire [63:0]  cmd_prp2_i,        // PRP Entry 2
    input  wire [63:0]  cmd_slba_i,        // Starting LBA (from CDW10-11)
    input  wire [15:0]  cmd_nlb_i,         // Number of LBAs (0's based)
    input  wire [7:0]   cmd_sqid_i,        // Source SQ ID
    input  wire [15:0]  cmd_sq_head_i,     // SQ head at fetch time (for CQE.SQHD)

    // ── PRP Walker control ──
    output wire         prp_start_o,       // Pulse: begin PRP traversal
    input  wire         prp_done_i,        // Pulse: PRP traversal complete
    input  wire         prp_error_i,       // PRP error detected
    input  wire [15:0]  prp_error_status_i,// NVMe status code (0=success)
    output wire [63:0]  prp_prp1_o,
    output wire [63:0]  prp_prp2_o,
    output wire [31:0]  prp_transfer_bytes_o,

    // ── Read Engine control ──
    output wire         rd_start_o,        // Pulse: begin data transfer
    input  wire         rd_done_i,         // Pulse: all data + B responses done
    output wire [63:0]  rd_slba_o,
    output wire [31:0]  rd_total_bytes_o,

    // ── Completion output (to CQ Post) ──
    output wire         cpl_valid_o,       // Level: completion ready
    input  wire         cpl_ready_i,       // CQ post accepts completion
    output wire [7:0]   cpl_sqid_o,
    output wire [15:0]  cpl_sqhd_o,        // SQ head at command fetch
    output wire [15:0]  cpl_cid_o,
    output wire [15:0]  cpl_status_o       // 0=success, others=error
);
```

### Timing Contract

| Signal | Type | Width | Timing |
|--------|------|-------|--------|
| `cmd_valid_i` | Pulse | 1 | 1 cycle, held until `cmd_ready_o` |
| `cmd_ready_o` | Level | 1 | High when any slot is free |
| `prp_start_o` | Pulse | 1 | 1 cycle, asserted when command issues |
| `prp_done_i` | Pulse | 1 | Sampled on posedge; triggers rd_start_o next cycle |
| `rd_start_o` | Pulse | 1 | 1 cycle after prp_done_i |
| `rd_done_i` | Pulse | 1 | Triggers cpl_valid_o assertion |
| `cpl_valid_o` | Level | 1 | Held until `cpl_ready_i` |

### Key Registers

| Register | Width | Reset | Description |
|----------|-------|-------|-------------|
| `slot_valid_q[0:3]` | 4 | 4'h0 | Bit-vector of occupied slots |
| `slot_cid_q[0:3]` | 16 | 0 | Command ID per slot |
| `slot_nsid_q[0:3]` | 32 | 0 | Namespace ID per slot |
| `slot_prp1_q[0:3]` | 64 | 0 | PRP1 per slot |
| `slot_prp2_q[0:3]` | 64 | 0 | PRP2 per slot |
| `slot_slba_q[0:3]` | 64 | 0 | Starting LBA per slot |
| `slot_nlb_q[0:3]` | 16 | 0 | NLB per slot |
| `slot_sqid_q[0:3]` | 8 | 0 | SQ ID per slot |
| `slot_sqhd_q[0:3]` | 16 | 0 | SQ head per slot |
| `wr_ptr_q` | 2 | 0 | Write pointer |
| `rd_ptr_q` | 2 | 0 | Read pointer |
| `processing_q` | 1 | 0 | Currently processing a command |

### Invariants

1. `slot_valid_q[wr_ptr_q]` must be 0 before accepting new command
2. `wr_ptr_q != rd_ptr_q` when `|slot_valid_q` (at least one slot occupied)
3. `cpl_valid_o` deasserts on cycle after `cpl_ready_i` (1-cycle pulse from tracker perspective, level to cq_post)
4. `transfer_bytes = (nlb + 1) * LBA_SIZE` — NLB=0 means 1 block

---

## 2. nvme_prp_walker — Interface Contract

### Purpose
Traverse PRP entries to emit a sequence of {host_memory_page_addr, byte_count} pairs for AXI data transfer.

### Port List

```verilog
module nvme_prp_walker #(
    parameter PAGE_SIZE       = 4096,  // 4 KiB (CC.MPS=0)
    parameter AXI_DATA_W      = 64,
    parameter AXI_ADDR_W      = 64,
    parameter LIST_ENTRIES    = 512    // PAGE_SIZE / 8
) (
    input  wire         clk_i,
    input  wire         rst_ni,

    // ── Control ──
    input  wire         start_i,           // Pulse: begin traversal
    output wire         done_o,            // Pulse: traversal complete
    output wire         error_o,           // Pulse: error detected
    output wire [15:0]  error_status_o,    // NVMe status code

    // ── PRP registers for this command ──
    input  wire [63:0]  prp1_i,
    input  wire [63:0]  prp2_i,
    input  wire [31:0]  transfer_bytes_i,  // (NLB+1) * LBA_SIZE

    // ── Page address output → read_engine ──
    output wire [63:0]  page_addr_o,       // Host memory physical addr for this page
    output wire [15:0]  page_bytes_o,      // Bytes to transfer for this page
    output wire         page_valid_o,      // Pulse: page_addr valid
    input  wire         page_ready_i,      // read_engine accepts page

    // ── AXI AR (PRP List fetch) ──
    output wire         list_ar_valid_o,
    input  wire         list_ar_ready_i,
    output wire [63:0]  list_ar_addr_o,
    output wire [7:0]   list_ar_len_o,     // = LIST_ENTRIES - 1 = 511

    // ── AXI R (PRP List data) ──
    input  wire         list_r_valid_i,
    output wire         list_r_ready_o,
    input  wire [63:0]  list_r_data_i,
    input  wire         list_r_last_i,

    // ── Page done feedback ──
    input  wire         page_done_i        // read_engine completed this page's transfers
);
```

### FSM States

```
IDLE (0)          — wait for start_i
CALC_FIRST (1)     — compute first_page_capacity, determine PRP2 role
PAGE_TX (2)        — output page_addr to read_engine, wait for page_ready_i
NEXT_PAGE (3)      — select next page source
LIST_FETCH (4)     — issue AXI AR for PRP list page
LIST_FETCH_R (5)   — receive AXI R beats into list buffer
LIST_WALK (6)      — read next entry from list buffer
DONE (7)           — pulse done_o, return to IDLE
```

### PRP2 Role Decision

```verilog
first_page_capacity = PAGE_SIZE - prp1_i[11:0];  // bytes in first page

if (transfer_bytes_i <= first_page_capacity)
    role = RESERVED;   // PRP2 unused
else if (transfer_bytes_i <= first_page_capacity + PAGE_SIZE)
    role = PAGE;       // PRP2 = second memory page
else
    role = LIST;       // PRP2 = PRP list pointer
```

### Timing Contract

| Signal | Type | Timing |
|--------|------|--------|
| `start_i` | Pulse | 1 cycle; FSM latches inputs on this cycle |
| `done_o` | Pulse | 1 cycle; FSM returns to IDLE next cycle |
| `page_valid_o` | Pulse | 1 cycle; `page_addr_o` and `page_bytes_o` valid |
| `page_ready_i` | Level | Read engine sets when ready to accept page |
| `page_done_i` | Pulse | Read engine pulses when all AXI bursts for this page complete |
| `list_ar_valid_o` | Level | Held until `list_ar_ready_i` |
| `list_r_ready_o` | Level | Always 1 in LIST_FETCH_R state |

### Key Registers

| Register | Width | Reset | Description |
|----------|-------|-------|-------------|
| `state_q` | 4 | IDLE | FSM state |
| `current_addr_q` | 64 | 0 | Page base addr for current output |
| `bytes_remaining_q` | 32 | 0 | Remaining bytes for entire command |
| `page_offset_q` | 12 | 0 | Offset within first page (PRP1[11:0], MPS=0) |
| `in_list_q` | 1 | 0 | Currently traversing PRP list |
| `list_page_addr_q` | 64 | 0 | Current PRP list page addr in host mem |
| `list_index_q` | 10 | 0 | Entry index within list page (0..511) |
| `prp2_role_q` | 2 | 0 | 0=Reserved, 1=Page, 2=List |
| `transferred_first_q` | 1 | 0 | First page already output |
| `list_buf` | 512×64 | — | PRP list entries (register array) |
| `list_buf_avail_q` | 1 | 0 | List buffer contains valid data |

### Invariants

1. PRP1.offset applies ONLY to first page output; all subsequent pages have offset=0
2. PRP list entries within a list page must have offset[11:0]==0 (page-aligned). Non-zero offset → error_o, status=0x13
3. List entry[511] is either chain pointer (to next list page) or 0 (last list page)
4. page_bytes_o ≤ PAGE_SIZE (never crosses 4KB boundary)
5. bytes_remaining_q monotonically decreases; done_o only when bytes_remaining_q == 0
6. After done_o: FSM returns to IDLE within 1 cycle

---

## 3. nvme_read_engine — Interface Contract

### Purpose
Read data from NVM SRAM, buffer in FWFT FIFO, write to host memory via AXI AW+W+B. Three independent controllers (P13).

### Port List

```verilog
module nvme_read_engine #(
    parameter AXI_DATA_W      = 64,
    parameter AXI_ADDR_W      = 64,
    parameter AXI_MAX_BURST   = 256,   // max beats per AXI burst
    parameter LBA_SIZE        = 512,
    parameter DATA_FIFO_DEPTH = 512    // ≥ AXI_MAX_BURST for P12
) (
    input  wire         clk_i,
    input  wire         rst_ni,

    // ── Control ──
    input  wire         start_i,           // Pulse: begin data transfer
    output wire         done_o,            // Pulse: all pages done + all B responses

    // ── Command parameters ──
    input  wire [63:0]  slba_i,            // Starting LBA
    input  wire [31:0]  total_bytes_i,     // (NLB+1) * LBA_SIZE

    // ── Page input (from PRP walker) ──
    input  wire [63:0]  page_addr_i,       // Host memory addr for current page
    input  wire [15:0]  page_bytes_i,      // Bytes for current page
    input  wire         page_valid_i,      // Pulse: page address valid
    output wire         page_ready_o,      // Ready for page
    output wire         page_done_o,       // Pulse: current page AXI writes complete

    // ── NVM SRAM read interface ──
    output wire [63:0]  nvm_addr_o,        // Byte address in NVM SRAM
    output wire         nvm_rd_en_o,       // Read enable
    input  wire [63:0]  nvm_rdata_i,       // Read data
    input  wire         nvm_rvalid_i,      // Read data valid (1 cycle latency)
    output wire         nvm_rready_o,      // Ready for read data

    // ── AXI AW ──
    output wire         axi_aw_valid_o,
    input  wire         axi_aw_ready_i,
    output wire [63:0]  axi_aw_addr_o,
    output wire [7:0]   axi_aw_len_o,      // burst_len = beats - 1

    // ── AXI W ──
    output wire         axi_w_valid_o,
    input  wire         axi_w_ready_i,
    output wire [63:0]  axi_w_data_o,
    output wire [7:0]   axi_w_strb_o,      // all-ones for aligned, partial for unaligned
    output wire         axi_w_last_o,

    // ── AXI B ──
    input  wire         axi_b_valid_i,
    output wire         axi_b_ready_o,     // Always 1
    input  wire [1:0]   axi_b_resp_i       // 0=OKAY
);
```

### Internal Architecture (Three Independent Controllers)

**1. NVM Read Controller** — Receives page_addr, computes nvm_addr = slba * LBA_SIZE + nvm_offset, reads NVM SRAM, fills FWFT FIFO.

**2. AW Controller** — Computes burst_len from page_addr offset + page_bytes + 4KB boundary. Issues AWVALID when FIFO pre-filled.

**3. W Controller (P12)** — `WVALID = w_active_q` only. `w_active_q` set on burst start, cleared on WLAST. Data from FWFT FIFO combinational output.

**4. B Controller** — `BREADY = 1`. Tracks `b_outstanding_q`. Done when all pages done AND b_outstanding == 0.

### Timing Contract

| Signal | Type | Timing |
|--------|------|--------|
| `start_i` | Pulse | 1 cycle; latches slba_i, total_bytes_i |
| `done_o` | Pulse | 1 cycle; all B responses received |
| `page_ready_o` | Level | High when engine can accept next page (after current page done) |
| `page_done_o` | Pulse | 1 cycle; when page's last WLAST sent AND all page's B responses received |
| `axi_aw_valid_o` | Level | Held until `axi_aw_ready_i` |
| `axi_w_valid_o` | Level | Held from first beat to WLAST (P12 compliance) |
| `axi_w_last_o` | Pulse | 1 cycle; coincides with final WVALID beat |
| `axi_b_ready_o` | Level | Always 1 |

### Key Registers

| Register | Width | Reset | Description |
|----------|-------|-------|-------------|
| `nvm_offset_q` | 32 | 0 | Byte offset within NVM for current transfer |
| `page_bytes_remain_q` | 16 | 0 | Bytes remaining in current page |
| `dfifo_mem` | DEPTH×64 | — | FWFT data FIFO storage |
| `dfifo_wr_ptr_q` | $clog2(DEPTH) | 0 | FIFO write pointer |
| `dfifo_rd_ptr_q` | $clog2(DEPTH) | 0 | FIFO read pointer |
| `dfifo_count_q` | $clog2(DEPTH+1) | 0 | FIFO occupancy |
| `aw_active_q` | 1 | 0 | AW has been issued for current burst |
| `w_active_q` | 1 | 0 | W burst in progress |
| `w_beat_q` | 8 | 0 | W beat counter (0..255) |
| `b_outstanding_q` | 8 | 0 | Outstanding B responses |
| `page_active_q` | 1 | 0 | Currently processing a page |
| `all_pages_done_q` | 1 | 0 | All pages issued (set by PRP walker done) |

### Key Formulas

```verilog
// NVM address
nvm_addr = slba_i * LBA_SIZE + nvm_offset_q;  // byte address in SRAM

// AXI burst length
addr_offset = page_addr_i[11:0];          // byte offset within 4KB page
bytes_to_boundary = 12'h1000 - addr_offset;
beats_to_boundary = bytes_to_boundary >> 3;  // 64-bit bus
requested_beats = min(page_bytes_i >> 3, beats_to_boundary);
burst_len = (total_beats <= 256) ? total_beats - 1 : 255;  // DP4 explicit branch

// WSTRB for unaligned
wstrb_first = ~((1 << addr_offset[2:0]) - 1);  // mask off low bytes
wstrb_last = (last_offset == 0) ? 8'hFF : (8'hFF >> (8 - last_offset));
```

### Invariants

1. `WVALID` never depends on `dfifo_count` mid-burst (P12: WVALID = w_active_q only)
2. `burst_ready = (dfifo_count >= requested_beats)` BEFORE asserting AWVALID
3. `aw_active_q` and `w_active_q` are set independently (no AW→W coupling)
4. `BREADY = 1` always
5. FWFT FIFO: `rdata = dfifo_mem[rd_ptr_q]` (combinational, not registered — F1)

---

## 4. nvme_axi_adapter — Extension Contract

### Changes from Phase 1

| Change | Description |
|--------|-------------|
| New S2 port | PRP Walker AR/R — 512-beat burst for PRP list fetch |
| New S3 port | Read Engine AW/W/B — variable-length data burst |
| New master AWLEN | `m_axi_aw_len_o` output (was hardcoded to 1 in Phase 1) |
| New master AWSIZE | `m_axi_aw_size_o` = 3'd3 (8 bytes) |
| AR arbitration | S2 (PRP list) > S0 (SQ fetch) — fixed priority |
| AW/W arbitration | S3 (read engine) > S1 (CQ post) — fixed priority |
| R demux | Route R data to correct source based on pending AR |
| B demux | Route B response to correct source based on pending AW |

### Port List (Extended)

```verilog
module nvme_axi_adapter (
    input  wire         clk_i,
    input  wire         rst_ni,

    // S0: SQ Fetch (AR+R)
    input  wire         s0_ar_valid_i,  output wire s0_ar_ready_o,
    input  wire [63:0]  s0_ar_addr_i,   input  wire [7:0] s0_ar_len_i,
    output wire         s0_r_valid_o,   input  wire s0_r_ready_i,
    output wire [63:0]  s0_r_data_o,    output wire s0_r_last_o,

    // S1: CQ Post (AW+W+B)
    input  wire         s1_aw_valid_i,  output wire s1_aw_ready_o,
    input  wire [63:0]  s1_aw_addr_i,
    input  wire         s1_w_valid_i,   output wire s1_w_ready_o,
    input  wire [63:0]  s1_w_data_i,    input  wire [7:0] s1_w_strb_i,
    input  wire         s1_w_last_i,
    output wire         s1_b_valid_o,   input  wire s1_b_ready_i,

    // S2: PRP Walker (AR+R) — NEW
    input  wire         s2_ar_valid_i,  output wire s2_ar_ready_o,
    input  wire [63:0]  s2_ar_addr_i,   input  wire [7:0] s2_ar_len_i,
    output wire         s2_r_valid_o,   input  wire s2_r_ready_i,
    output wire [63:0]  s2_r_data_o,    output wire s2_r_last_o,

    // S3: Read Engine (AW+W+B) — NEW
    input  wire         s3_aw_valid_i,  output wire s3_aw_ready_o,
    input  wire [63:0]  s3_aw_addr_i,   input  wire [7:0] s3_aw_len_i,
    input  wire         s3_w_valid_i,   output wire s3_w_ready_o,
    input  wire [63:0]  s3_w_data_i,    input  wire [7:0] s3_w_strb_i,
    input  wire         s3_w_last_i,
    output wire         s3_b_valid_o,   input  wire s3_b_ready_i,

    // Master AXI
    output wire         m_axi_ar_valid, input  wire m_axi_ar_ready,
    output wire [63:0]  m_axi_ar_addr,  output wire [7:0] m_axi_ar_len,
    input  wire         m_axi_r_valid,  output wire m_axi_r_ready,
    input  wire [63:0]  m_axi_r_data,   input  wire m_axi_r_last,
    output wire         m_axi_aw_valid, input  wire m_axi_aw_ready,
    output wire [63:0]  m_axi_aw_addr,  output wire [7:0] m_axi_aw_len,
    output wire         m_axi_w_valid,  input  wire m_axi_w_ready,
    output wire [64:0]  m_axi_w_data,   output wire [7:0] m_axi_w_strb,
    output wire         m_axi_w_last,
    input  wire         m_axi_b_valid,  output wire m_axi_b_ready
);
```

### Arbitration Rules

- **AR:** S2 asserted → route S2. Else S0 → route S0. R response demuxed by `ar_source_q` register.
- **AW/W:** S3 asserted → route S3. Else S1 → route S1. W data/WSTRB/WLAST muxed by same rule.
- **B:** Demuxed by `aw_source_q` register.
- **No starvation guard needed:** S2 only active during PRP list fetch (rare, short), S1 only active on CQE post (2 beats). S3/S0 are the common path.

---

## 5. nvme_io_top — Integration Contract

### Purpose
Top-level integration: wire reused modules + new modules. Command demux routes NVM Read to tracker, admin commands to admin_exec.

### Pin-Level Connections

```
sq_fetch.cmd_* → demux → [admin_exec (admin ops) | cmd_tracker (Read op=02h)]

cmd_tracker.prp_* → prp_walker.prp*_i
cmd_tracker.rd_* → read_engine.slba_i, total_bytes_i
cmd_tracker.cpl_* → cq_post.cpl*_i

prp_walker.page_* → read_engine.page_*_i
prp_walker.list_ar_* → axi_adapter.s2_ar_*
prp_walker.list_r_* ← axi_adapter.s2_r_*

read_engine.axi_aw_* → axi_adapter.s3_aw_*
read_engine.axi_w_* → axi_adapter.s3_w_*
read_engine.axi_b_* ← axi_adapter.s3_b_*
read_engine.nvm_* → top-level NVM SRAM ports

sq_fetch.head_update → sq_head_held_q register → cmd_tracker.cmd_sq_head_i
                                                        → cq_post.cpl_sqhd_i (via tracker)
```

### NVM SRAM Top-Level Ports

```verilog
output wire [63:0]  nvm_addr_o,       // to testbench NVM SRAM
output wire         nvm_rd_en_o,
input  wire [63:0]  nvm_rdata_i,
input  wire         nvm_rvalid_i,
```

---

## Design Decision Log

| Decision | Rationale | Date |
|----------|-----------|------|
| Read-only first | PRP traversal is the core risk; Write is symmetric | 2026-06-01 |
| Blocking page interface (walker waits for read_engine) | Simpler than decoupled pipeline; sufficient for 4-slot tracker | 2026-06-01 |
| Register array for PRP list buffer | Icarus compatible; 32K FF acceptable for simulation; BRAM later | 2026-06-01 |
| Fixed priority AXI arbitration | PRP list fetch is rare (<1% of cycles); CQ post is 2 beats | 2026-06-01 |
| Single CQ for I/O (reuse Phase 1 phase_q) | Avoids per-CQ phase tracking complexity | 2026-06-01 |
| LBA_SIZE=512 hardcoded | Default namespace format; parameterizable later | 2026-06-01 |
| No MSI-X interrupt | Not needed for Phase 3 validation | 2026-06-01 |

## Residual Risks

1. **PRP list buffer simulation performance:** 512-entry register array may slow Icarus. Acceptable for 8-test regression.
2. **AXI adapter arbitration livelock:** Fixed priority without backoff could theoretically starve. Mitigated by burst-length limiting and rare S2 usage.
3. **NVM SRAM read latency:** Hardcoded to 1 cycle. Real flash has variable latency — out of scope.
