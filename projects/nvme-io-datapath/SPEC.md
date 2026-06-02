# NVMe I/O Data Path — Project Specification

## Overview

Build the core read data path for an NVMe controller: accept NVM Read commands, traverse PRP lists, read from NVM SRAM, and write data to host memory via AXI.

**5 Verilog modules, ~900 lines total.**

---

## 1. System Architecture

```
cmd_tracker ──> prp_walker ──> read_engine ──> AXI (AW+W+B)
    │                                        ──> NVM (read)
    └────────── completion <─────────────────┘
```

**Data flow for one NVM Read command:**
1. Command enters `cmd_tracker` (opcode, SLBA, PRP1, PRP2, NLB, SQID, CID, SQHD)
2. `cmd_tracker` starts `prp_walker` and `read_engine` simultaneously
3. `prp_walker` translates PRP entries into a stream of `{addr, byte_count, last}` pages
4. `read_engine` accepts pages, reads NVM SRAM into an internal FIFO, and bursts data to host via AXI
5. When all pages complete, `cmd_tracker` posts a completion carrying `{SQID, SQHD, CID, status}`

**Module inventory:**

| Module | Purpose |
|--------|---------|
| `nvme_cmd_tracker` | 4-slot command queue, FIFO-ordered issue, completion aggregation |
| `nvme_prp_walker` | PRP traversal: translates PRP entries into page stream |
| `nvme_read_engine` | NVM read → internal FIFO → AXI write (AW + W + B) |
| `nvme_axi_adapter` | 4-source AXI mux/demux (AR+R, AW+W+B) |
| `nvme_io_top` | Top-level instantiation and wiring |

---

## 2. Global Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| AXI data width | 64 bits | All AXI channels |
| AXI max burst | 64 beats | Maximum beats per AXI burst |
| LBA size | 512 bytes | NVMe logical block size |
| Page size | 4096 bytes | PRP page granularity |
| PRP list entries | 512 | Entries per PRP list page |
| Command slots | 4 | Outstanding I/O commands |
| Data FIFO depth | 64 | Pipeline buffer in read engine |

---

## 3. Module Interface Contracts

### 3.1 nvme_cmd_tracker

Accepts up to 4 NVM Read commands. FIFO-ordered issue. Starts PRP walker and read engine in the same cycle. Posts completion after read engine signals done.

```
module nvme_cmd_tracker #(
    parameter NUM_SLOTS = 4,
    parameter LBA_SIZE  = 512
) (
    input  wire         clk_i,
    input  wire         rst_ni,

    // Command input
    input  wire         cmd_valid_i,
    output wire         cmd_ready_o,
    input  wire [7:0]   cmd_opcode_i,
    input  wire [15:0]  cmd_cid_i,
    input  wire [31:0]  cmd_nsid_i,
    input  wire [63:0]  cmd_prp1_i,
    input  wire [63:0]  cmd_prp2_i,
    input  wire [63:0]  cmd_slba_i,
    input  wire [15:0]  cmd_nlb_i,
    input  wire [7:0]   cmd_sqid_i,
    input  wire [15:0]  cmd_sq_head_i,

    // PRP walker control
    output wire         prp_start_o,
    input  wire         prp_done_i,
    input  wire         prp_error_i,
    input  wire [15:0]  prp_error_status_i,
    output wire [63:0]  prp_prp1_o,
    output wire [63:0]  prp_prp2_o,
    output wire [31:0]  prp_transfer_bytes_o,

    // Read engine control
    output wire         rd_start_o,
    input  wire         rd_done_i,
    output wire [63:0]  rd_slba_o,
    output wire [31:0]  rd_total_bytes_o,

    // Completion output
    output wire         cpl_valid_o,
    input  wire         cpl_ready_i,
    output wire [7:0]   cpl_sqid_o,
    output wire [15:0]  cpl_sqhd_o,
    output wire [15:0]  cpl_cid_o,
    output wire [15:0]  cpl_status_o
);
```

**Behavior:**
- `cmd_ready_o` asserts when a slot is free.
- On command acceptance: store all command fields in the slot indexed by write pointer. Advance write pointer.
- `prp_start_o` and `rd_start_o` are 1-cycle pulses. Both assert when a new command begins processing (slot valid, not busy, no pending completion).
- After prp_walker completes (`prp_done_i` rising edge), read engine starts.
- After read engine completes (`rd_done_i` rising edge), completion is posted.
- `cpl_valid_o` is a level signal. It stays asserted until `cpl_ready_i` handshakes. On handshake: clear the slot, advance read pointer.
- `prp_transfer_bytes_o = (nlb + 1) * LBA_SIZE`. `rd_total_bytes_o` = same value.

---

### 3.2 nvme_prp_walker

Translates PRP entries into a stream of `{host_addr, byte_count, is_last}` pages.

```
module nvme_prp_walker #(
    parameter PAGE_SIZE    = 4096,
    parameter LIST_ENTRIES = 512
) (
    input  wire         clk_i,
    input  wire         rst_ni,
    input  wire         start_i,
    output wire         done_o,
    output wire         error_o,
    output wire [15:0]  error_status_o,
    input  wire [63:0]  prp1_i,
    input  wire [63:0]  prp2_i,
    input  wire [31:0]  transfer_bytes_i,

    // Page output stream
    output wire [63:0]  page_addr_o,
    output wire [16:0]  page_bytes_o,
    output wire         page_valid_o,
    output wire         page_last_o,
    input  wire         page_ready_i,

    // AXI AR (PRP list fetch)
    output wire         list_ar_valid_o,
    input  wire         list_ar_ready_i,
    output wire [63:0]  list_ar_addr_o,
    output wire [7:0]   list_ar_len_o,

    // AXI R (PRP list data)
    input  wire         list_r_valid_i,
    output wire         list_r_ready_o,
    input  wire [63:0]  list_r_data_i,
    input  wire         list_r_last_i,

    // Page done from downstream
    input  wire         page_done_i
);
```

**PRP2 role decision:**
- `transfer_bytes <= first_page_capacity` → PRP2 not used (transfer fits in PRP1 page).
- `transfer_bytes <= first_page_capacity + PAGE_SIZE` → PRP2 is a data page.
- Otherwise → PRP2 points to a PRP list (512 entries, each 8 bytes).

`first_page_capacity = PAGE_SIZE - (prp1_i[11:0])` — the number of bytes available in the first page, accounting for the PRP1 offset.

**Page output stream:**
- `page_addr_o`: host physical address for this page. Unit: byte address.
- `page_bytes_o`: number of bytes in this page. Unit: bytes. First page uses `first_page_capacity` (capped at `transfer_bytes`). Subsequent pages use `PAGE_SIZE` (capped at remaining bytes).
- `page_valid_o`: 1-cycle pulse. `page_addr_o` and `page_bytes_o` are valid in this cycle.
- `page_last_o`: 1-cycle pulse, asserted in the same cycle as `page_valid_o` for the last page of the transfer. The last page is the page where `bytes_left_q <= page_bytes_o` after this page is sent. Both quantities are in bytes.
- `page_ready_i`: downstream handshake. If low, hold page data and retry next cycle.

**PRP list fetch:**
- When PRP2 role is LIST: issue AXI read to `prp2_i` address. Burst length covers 512 entries × 8 bytes = 4096 bytes. Split into 256-beat bursts (AXI max burst constraint).
- Store received entries in internal buffer. Last entry (index 511) is a chain pointer to the next list page.
- After list fetch complete, iterate through entries as page addresses.

**Completion:**
- `page_done_i` from downstream signals that the current page's data has been fully written to AXI.
- `done_o` asserts after the last page's `page_done_i` is received. Level signal, deasserted by `start_i`.

---

### 3.3 nvme_read_engine

Reads NVM SRAM into an internal FIFO, then bursts data to host via AXI. Three independent sub-controllers: NVM read, AW, W+B.

```
module nvme_read_engine #(
    parameter AXI_DATA_W      = 64,
    parameter AXI_MAX_BURST   = 64,
    parameter LBA_SIZE        = 512,
    parameter DATA_FIFO_DEPTH = 64
) (
    input  wire         clk_i,
    input  wire         rst_ni,
    input  wire         start_i,
    output wire         done_o,
    input  wire [63:0]  slba_i,
    input  wire [31:0]  total_bytes_i,

    // Page input stream (from prp_walker)
    input  wire [63:0]  page_addr_i,
    input  wire [16:0]  page_bytes_i,
    input  wire         page_valid_i,
    input  wire         page_last_i,
    output wire         page_ready_o,
    output wire         page_done_o,

    // NVM SRAM read
    output wire [63:0]  nvm_addr_o,
    output wire         nvm_rd_en_o,
    input  wire [63:0]  nvm_rdata_i,
    input  wire         nvm_rvalid_i,
    output wire         nvm_rready_o,

    // AXI AW
    output wire         axi_aw_valid_o,
    input  wire         axi_aw_ready_i,
    output wire [63:0]  axi_aw_addr_o,
    output wire [7:0]   axi_aw_len_o,

    // AXI W
    output wire         axi_w_valid_o,
    input  wire         axi_w_ready_i,
    output wire [63:0]  axi_w_data_o,
    output wire [7:0]   axi_w_strb_o,
    output wire         axi_w_last_o,

    // AXI B
    input  wire         axi_b_valid_i,
    output wire         axi_b_ready_o,
    input  wire [1:0]   axi_b_resp_i
);
```

**NVM Read Controller:**
- Issues reads to NVM when a page is active and the FIFO has space.
- `nvm_addr_o = slba_i * LBA_SIZE + nvm_offset_q`. Unit: byte address.
- `nvm_offset_q` advances by 8 on each read issue. Unit: bytes.
- Page bytes remaining decrements by 8 on each read issue. When remaining reaches < 8, NVM reads for this page are done.
- `page_ready_o` asserts when able to accept a new page.

**Internal Data FIFO:**
- Depth = DATA_FIFO_DEPTH (64).
- Write: NVM read data (`nvm_rvalid_i`). Write when data arrives, regardless of read state.
- Read: AXI W beat handshake.
- Output data is combinational from read pointer (FWFT — First-Word Fall-Through).

**AW Controller:**
- On page acceptance: capture host address, compute total beats for this page (`page_bytes / 8`), issue first AW.
- AW burst length = min(total_beats, AXI_MAX_BURST). AXI AWLEN = beats - 1.
- On each AW handshake: advance address by `(AWLEN + 1) * 8` bytes. Decrement remaining beats. Issue next AW if beats remain.
- AW issues independently of FIFO state — AW is based on page beat count only.

**W Controller:**
- W burst starts when AW handshake completes and previous W burst is done.
- WLAST is combinational: asserts when current beat equals burst length.
- WDATA is combinational from FIFO read port.
- WSTRB = 8'hFF (all bytes valid).
- W beat advances when WVALID, WREADY, and W active.

**B Controller:**
- Track outstanding B responses (increment on AW handshake, decrement on B valid).
- BREADY = 1 always.

**Page completion:**
- A page is done when: all NVM reads for this page are issued, all W beats for this page are sent, and all B responses for this page are received.
- `page_done_o` is a 1-cycle pulse.
- `done_o` is a level signal: all pages accepted, all pages completed, and `page_last_i` was received.

---

### 3.4 nvme_axi_adapter

Routes up to 4 internal AXI sources to a single external AXI master. Fixed priority: AR: S2 > S0. AW/W: S3 > S1.

**Sources:** S0 (SQ Fetch, AR+R), S1 (CQ Post, AW+W+B), S2 (PRP Walker, AR+R), S3 (Read Engine, AW+W+B).

Each source port uses `s0_`, `s1_`, `s2_`, `s3_` prefix for its AXI channel signals. Master-side ports use `m_axi_` prefix.

For R and B channel demux, track which source is active using a registered source ID. The source ID for AR is captured on AR handshake. For AW, captured on AW handshake.

---

### 3.5 nvme_io_top

Instantiate all four submodules. Wire the data paths. No logic — pure interconnection.

For Phase 3 validation: SQ fetch and CQ post are replaced by direct testbench command input and completion output. PRP list fetch AXI on the adapter is tied off (no list fetch traffic in Phase 3 tests).

---

## 4. Test Plan

### Testbench

Single file `tb_nvme_io.v`. Icarus Verilog compatible. Output protocol:

```
SIMULATION_START
RESET_RELEASED
TEST_START <name>
TEST_PASS <name>   or   TEST_FAIL <name>: <details>
...
ALL_TESTS_PASS
SIMULATION_DONE
```

### Test Cases

| Test | NLB | PRP2 Role | Transfer Size | Pages |
|------|-----|-----------|:---:|:---:|
| T1 | 0 | Reserved | 64 bytes | 1 |
| T2 | 15 | Page | 1024 bytes | 2 |
| T3 | 63 | List | 4096 bytes | 8 |

### Verification Strategy

- **NVM model:** Pre-loaded with known data pattern. Responds to reads with 1-cycle latency.
- **AXI slave model:** Captures write data. Compares against expected (known NVM content at expected offset).
- **Completion checker:** After `cpl_valid_o` handshake, verifies CID, SQID, SQHD match the issued command.
- **Golden reference:** Strategy D (end-to-end data integrity scoreboard).
