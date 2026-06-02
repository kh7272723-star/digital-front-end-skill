# NVMe I/O Data Path — Project Specification

## Project Overview

Build the core read data path for an NVMe controller: accept NVM Read commands → traverse PRP lists → read from NVM SRAM → write data to host memory via AXI. Validate with directed simulation.

**Classification:** L2 Subsystem — 5 Verilog modules, ~900 lines total.

---

## 1. System Architecture

```
┌─────────────┐     ┌─────────────┐     ┌──────────────┐
│ cmd_tracker │────>│ prp_walker  │────>│ read_engine  │──> AXI (AW+W+B)
│ (4 slots)   │     │ (PRP→pages) │     │ (NVM→AXI)    │──> NVM (read)
└─────────────┘     └─────────────┘     └──────────────┘
       │                                       │
       └─────────── completion <───────────────┘
```

**Module inventory:**

| Module | Purpose | Est. Lines |
|--------|---------|:---:|
| `nvme_cmd_tracker` | 4-slot command queue, FIFO-ordered issue | ~170 |
| `nvme_prp_walker` | PRP traversal: pages → page stream | ~230 |
| `nvme_read_engine` | NVM read → FWFT FIFO → AXI write | ~350 |
| `nvme_axi_adapter` | 4-source AXI mux (AR+R, AW+W+B) | ~120 |
| `nvme_io_top` | Top-level instantiation + wiring | ~120 |

**Data flow for one NVM Read command:**
1. Command enters `cmd_tracker` (opcode, SLBA, PRP1, PRP2, NLB, SQID, CID, SQHD)
2. `cmd_tracker` starts `prp_walker` and `read_engine` **simultaneously** (not sequentially)
3. `prp_walker` translates PRP entries into a stream of `{addr, byte_count, last}` pages
4. `read_engine` accepts pages, reads NVM SRAM into an internal FWFT FIFO, and bursts data to host via AXI
5. When all pages complete, `read_engine` asserts `done_o` → `cmd_tracker` posts completion
6. Completion carries `{SQID, SQHD, CID, status}` back to the testbench

---

## 2. Global Design Constraints (Mandatory)

### 2.1 Coding Standards
All RTL must follow the skill's `rtl-coding-standards.md`. Key rules:

| Rule | Requirement |
|------|------------|
| **C3** | Every .v file starts with `` `default_nettype none `` |
| **C5/C6/C7** | Two-process FSM only. FSM outputs single-bit enables. Datapath registers NEVER read `cstate` directly |
| **C9/C10** | FSM uses `cstate`/`nstate` naming. Default case → IDLE. Default assignments before case |
| **C14** | All registers in the same `always` block must share the same reset and enable conditions |
| **C16** | All bit widths explicit (`2'b01`, never `1`) |
| **C19** | Every `if` in a sequential block must have an `else` (if-if chains prohibited) |
| **C21** | One declaration per line. One assignment per line. One `<=` per line |
| **N1** | Port suffixes: `_i` for input, `_o` for output, `_ni` for active-low, `_q` for registered state |

### 2.2 NBA Discipline (Non-Blocking Assignment Hazards)

Read `references/timing/nba-ordering-guide.md` before writing any `always @(posedge clk_i)` block. The following traps MUST be avoided:

| Trap | Rule | Example of violation |
|------|------|---------------------|
| **Trap 1** | Counters driving registered outputs → 1 cycle lag | `w_beat_q <= w_beat_q + 1; w_last_o <= (w_beat_q == len);` — w_last_o uses OLD w_beat_q |
| **Trap 2** | FIFO pointer advancing in same block as registered data read → data shift | `rd_ptr <= rd_ptr + 1; data_o <= fifo[rd_ptr];` — data_o gets OLD slot |
| **Trap 4** | Counter advances on `ready` alone, not `valid && ready` | `if (w_ready) w_beat <= w_beat + 1;` when valid is 0 |
| **Trap 5** | Address/offset advances on data ARRIVAL, not on command ISSUE | `if (rvalid) offset <= offset + 8;` — advance when read completes, not when issued |
| **Trap 6** | Consumer input gated by consumer's own output | `fifo_wr_en = rvalid && rd_en;` — last data beat lost when rd_en drops |

**For Trap 1 and Trap 2:** The fix is to make the output **combinational** (`assign`), not registered. Counters are registered; outputs derived from counters must be combinational.

**For Trap 5:** The fix is to advance on the **issue strobe** (`rd_en_o`), not the **arrival signal** (`rvalid_i`).

### 2.3 Signal Unit Conventions

Every multi-bit port must have a clearly documented physical unit. When comparing two signals, both must be in the same unit. Conversion factors must be explicit:

| Signal naming pattern | Unit | Conversion |
|----------------------|------|------------|
| `*_bytes_*` or `*_bytes` | bytes | — |
| `*_beats_*` | beats | 1 beat = 8 bytes (64-bit bus) |
| `*_addr_*` | byte address | — |
| `*_offset_*` | bytes | — |
| `*_count_*` | items | — |
| `*_len_*` | beats-1 | AXI convention: AWLEN = number of beats minus 1 |

**Rule:** Never use `{zeros, signal, more_zeros}` concatenation for unit conversion. Use explicit `signal * factor` or `signal / factor` with a comment explaining the conversion.

### 2.4 AXI Constraints
- Data width: 64 bits
- AXI_MAX_BURST = 64 (parameter, maximum beats per burst)
- AW/W/B channels must be independent (P13)
- WVALID = `w_active_q` only — never gated by FIFO state mid-burst (P12)
- BREADY = 1 always
- WSTRB = 8'hFF (all bytes valid) — simplified for this project

---

## 3. Per-Module Interface Contracts

### 3.1 nvme_cmd_tracker — Command Queue

**Purpose:** Accept up to 4 outstanding NVM Read commands. FIFO-ordered issue. Simultaneous start of prp_walker and read_engine.

**Parameters:** `NUM_SLOTS = 4`, `LBA_SIZE = 512`

**Ports:**

```verilog
module nvme_cmd_tracker #(NUM_SLOTS = 4, LBA_SIZE = 512) (
    input  wire         clk_i, rst_ni,
    // Command input
    input  wire         cmd_valid_i,
    output wire         cmd_ready_o,
    input  wire [7:0]   cmd_opcode_i,     // OPC=02h (Read)
    input  wire [15:0]  cmd_cid_i,        // unit: id
    input  wire [31:0]  cmd_nsid_i,       // unit: id
    input  wire [63:0]  cmd_prp1_i,       // unit: byte address
    input  wire [63:0]  cmd_prp2_i,       // unit: byte address
    input  wire [63:0]  cmd_slba_i,       // unit: LBA address
    input  wire [15:0]  cmd_nlb_i,        // unit: logical blocks (0-based)
    input  wire [7:0]   cmd_sqid_i,       // unit: id
    input  wire [15:0]  cmd_sq_head_i,    // unit: index
    // PRP walker control
    output wire         prp_start_o,      // pulse: begin PRP traversal
    input  wire         prp_done_i,       // pulse: PRP traversal complete
    output wire [63:0]  prp_prp1_o,       // unit: byte address
    output wire [63:0]  prp_prp2_o,       // unit: byte address
    output wire [31:0]  prp_transfer_bytes_o,  // unit: bytes
    // Read engine control
    output wire         rd_start_o,       // pulse: begin NVM read
    input  wire         rd_done_i,        // pulse: read complete
    output wire [63:0]  rd_slba_o,        // unit: LBA address
    output wire [31:0]  rd_total_bytes_o, // unit: bytes
    // Completion output
    output wire         cpl_valid_o,      // level: completion data valid
    input  wire         cpl_ready_i,
    output wire [7:0]   cpl_sqid_o,       // unit: id
    output wire [15:0]  cpl_sqhd_o,       // unit: index
    output wire [15:0]  cpl_cid_o,        // unit: id
    output wire [15:0]  cpl_status_o      // unit: status code
);
```

**Timing contract:**
- `prp_start_o` and `rd_start_o` must assert in the SAME cycle (not sequential). Both are pulses — 1 cycle wide.
- `cmd_ready_o = 1` when a slot is free (not full).
- `cpl_valid_o` is a level flag — stays high until `cpl_ready_i` handshakes.
- Completion posts after `rd_done_i` rising edge (transition detection).

**FSM note:** This module has simple slot management logic. A lightweight FSM or flag-based control is acceptable (no strict two-process requirement for slot tracking).

---

### 3.2 nvme_prp_walker — PRP Traversal Engine

**Purpose:** Translate PRP entries into a stream of `{host_addr, byte_count, is_last}` pages. Handles three PRP2 roles: Reserved (transfer fits in PRP1), Page (PRP2 is a data page), List (PRP2 points to a PRP list).

**Parameters:** `PAGE_SIZE = 4096`, `LIST_ENTRIES = 512`

**Ports:**

```verilog
module nvme_prp_walker #(PAGE_SIZE = 4096, LIST_ENTRIES = 512) (
    input  wire         clk_i, rst_ni,
    input  wire         start_i,           // pulse
    output wire         done_o,            // level
    output wire         error_o,           // level
    output wire [15:0]  error_status_o,    // unit: NVMe status code
    input  wire [63:0]  prp1_i,            // unit: byte address
    input  wire [63:0]  prp2_i,            // unit: byte address
    input  wire [31:0]  transfer_bytes_i,  // unit: bytes
    // Page output stream
    output wire [63:0]  page_addr_o,       // unit: byte address
    output wire [16:0]  page_bytes_o,      // unit: bytes
    output wire         page_valid_o,      // pulse: one cycle per page
    output wire         page_last_o,       // pulse: 1 if this is the last page
    input  wire         page_ready_i,      // downstream accepts
    // AXI AR (PRP list fetch)
    output wire         list_ar_valid_o,
    input  wire         list_ar_ready_i,
    output wire [63:0]  list_ar_addr_o,    // unit: byte address
    output wire [7:0]   list_ar_len_o,     // unit: beats-1
    // AXI R (PRP list data)
    input  wire         list_r_valid_i,
    output wire         list_r_ready_o,
    input  wire [63:0]  list_r_data_i,
    input  wire         list_r_last_i,
    // Page done from downstream
    input  wire         page_done_i        // pulse: downstream processed this page
);
```

**Timing contract:**
- `page_valid_o` is a 1-cycle pulse. `page_addr_o` and `page_bytes_o` are valid in that cycle.
- `page_ready_i` must be checked — if low, hold page data and retry next cycle (standard valid/ready handshake).
- `page_last_o` asserts during the SAME cycle as `page_valid_o` for the last page of the transfer. The condition MUST be: `bytes_left_q <= page_bytes_o` — both in bytes, pure comparison, no unit conversion needed.
- `done_o` is a level flag, deasserted by `start_i`.

**FSM states:** IDLE → CALC → PAGE_TX → PAGE_WAIT → NEXT → (PAGE_TX or LIST_FETCH or DONE). LIST_FETCH → LIST_RECV → NEXT. Two-process FSM required (cstate/nstate, single-bit enables).

**PRP2 role decision (in CALC state):**
- `transfer_bytes <= first_page_capacity` → ROLE_RSVD (PRP2 not used)
- `transfer_bytes <= first_page_capacity + PAGE_SIZE` → ROLE_PAGE (PRP2 is data page)
- Otherwise → ROLE_LIST (PRP2 is PRP list pointer)

**First page capacity:** `PAGE_SIZE - (prp1_i[11:0])` — offset within the 4KB page. Unit: bytes.

---

### 3.3 nvme_read_engine — NVM Read to AXI Write Engine

**Purpose:** Three independent controllers: NVM Read (fills FWFT FIFO), AW (issues AXI AW independently), W+B (drains FIFO to AXI W, tracks B responses). Read and write paths are decoupled (P4).

**Parameters:** `AXI_DATA_W = 64`, `AXI_MAX_BURST = 64`, `LBA_SIZE = 512`, `DATA_FIFO_DEPTH = 64`

**Ports:**

```verilog
module nvme_read_engine #(
    AXI_DATA_W = 64, AXI_MAX_BURST = 64, LBA_SIZE = 512, DATA_FIFO_DEPTH = 64
) (
    input  wire         clk_i, rst_ni,
    input  wire         start_i,           // pulse
    output wire         done_o,            // level
    input  wire [63:0]  slba_i,            // unit: LBA address
    input  wire [31:0]  total_bytes_i,     // unit: bytes
    // Page input stream (from prp_walker)
    input  wire [63:0]  page_addr_i,       // unit: byte address
    input  wire [16:0]  page_bytes_i,      // unit: bytes
    input  wire         page_valid_i,      // pulse
    input  wire         page_last_i,       // pulse: 1 if last page of transfer
    output wire         page_ready_o,      // accepts page
    output wire         page_done_o,       // pulse: page fully written to AXI
    // NVM SRAM read
    output wire [63:0]  nvm_addr_o,        // unit: byte address
    output wire         nvm_rd_en_o,       // issue strobe
    input  wire [63:0]  nvm_rdata_i,
    input  wire         nvm_rvalid_i,
    output wire         nvm_rready_o,
    // AXI AW
    output wire         axi_aw_valid_o,
    input  wire         axi_aw_ready_i,
    output wire [63:0]  axi_aw_addr_o,     // unit: byte address
    output wire [7:0]   axi_aw_len_o,      // unit: beats-1
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

**Sub-controllers:**

#### NVM Read Controller
- Issues reads to NVM SRAM while `page_rem_q >= 8` (at least one 64-bit beat remaining) AND FIFO has space (`fcnt_q < DATA_FIFO_DEPTH`).
- `nvm_addr_o = slba_i * LBA_SIZE + nvm_offset_q`. Unit: byte address.
- **NBA Trap 5:** `nvm_offset_q` advances on `nvm_rd_en_o` (issue strobe), NOT on `nvm_rvalid_i` (data arrival).
- Accepts pages from PRP walker. Has a 1-slot pending buffer for back-to-back page acceptance.

#### AW Controller (must be two-process FSM)
- **States:** AW_IDLE (waiting for page) → AW_ISSUE (issuing AW bursts).
- Page accepted → load `aw_a_q`, `aw_left_q` (beats), `aw_l_q` (burst length). Transition to AW_ISSUE.
- In AW_ISSUE: AW valid when `fcnt_q > aw_l_q` (burst-ready gate: FIFO has enough data) AND `!w_act_q` (previous W burst finished).
- AW handshake → advance address by `(aw_l_q + 1) * 8` bytes, decrement `aw_left_q`. Recalculate `aw_l_q` for next burst. If `aw_left_q == 0`, return to AW_IDLE.
- **FSM outputs single-bit enables only** (C7): `aw_load_o`, `aw_advance_o`. Datapath registers read these enables, not `aw_cstate`.
- **AW is decoupled from FIFO state** (P4). AW issues based on page beat count only. W pacing is handled separately.

#### W Controller
- `w_act_q` flag: 0 = idle, 1 = bursting.
- W burst starts when: AW handshake completes AND `!w_act_q`. Capture `aw_l_q` as `w_blen_q`.
- **NBA Trap 4:** W beat counter gates on `w_act_q && axi_w_valid_o && axi_w_ready_i`.
- **NBA Trap 1:** `axi_w_last_o` is **combinational**: `assign axi_w_last_o = w_act_q && (w_b_q == w_blen_q)`.
- **NBA Trap 2:** `axi_w_data_o` is **combinational** from FWFT FIFO: `assign axi_w_data_o = fifo_mem[rd_ptr_q]`.
- `axi_w_valid_o = w_act_q` only (P12).

#### FWFT Data FIFO
- Depth = 64. FWFT (First-Word Fall-Through) output — `assign frd = fifo_mem[rd_ptr_q]`.
- Write enable = `nvm_rvalid_i` (NBA Trap 6: do NOT gate with `rd_en_o`).
- Read advance = `axi_w_valid_o && axi_w_ready_i` (W handshake).
- Standard dual-pointer + count tracking.

#### B Controller
- `b_cnt_q`: outstanding B responses. Increment on AW handshake, decrement on B valid.
- `axi_b_ready_o = 1'b1` always.

#### Page Tracking
- `pg_in_q`: count of pages accepted. `pg_out_q`: count of pages completed.
- `last_seen_q`: set when `page_last_i` is seen. Never cleared until `start_i`.
- Page completion: NVM reads done + all W beats for this page sent + all B responses received.
- `done_o`: all pages accepted AND all pages completed AND `last_seen_q` is set.

---

### 3.4 nvme_axi_adapter — AXI Mux/Demux

**Purpose:** Route up to 4 internal AXI sources to a single external AXI master. Fixed priority arbitration.

**Sources:**
- S0: SQ Fetch (AR+R) — from sq_fetch (Phase 1)
- S1: CQ Post (AW+W+B) — from cq_post (Phase 1)
- S2: PRP Walker (AR+R) — from prp_walker
- S3: Read Engine (AW+W+B) — from read_engine

**Priority:** AR: S2 > S0. AW/W: S3 > S1.

**Ports:** Each source has a complete AXI channel subset. Master side has full AXI. Detailed port list in the interface contract appendix.

**Source tracking:** At least 1 bit per channel direction to track which source is active (for R and B demux). Must handle back-to-back bursts from the same source correctly (source ID held until last beat).

---

### 3.5 nvme_io_top — Top-Level Integration

Instantiate all four submodules. Wire the data paths. No logic — pure interconnection.

For Phase 3 validation, SQ fetch and CQ post are replaced by direct testbench command input and completion output. The adapter is instantiated but only read engine AXI traffic is routed through it. PRP list fetch AXI and unused sources are tied off.

---

## 4. Test Plan

### Testbench

Single testbench file `tb_nvme_io.v`. Uses Icarus Verilog compatible syntax (no `return`, no `break`, no `ref` ports — see `references/verification/icarus-common-pitfalls.md`).

**Output protocol:**
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

| Test | Description | Verification |
|------|-------------|-------------|
| T1 | NLB=0, PRP2=Reserved. 64 bytes. 1 page. | Golden Reference Strategy D: compare AXI W data with known NVM content. Check CQE fields. |
| T2 | NLB=15, PRP2=Page. 1024 bytes. 2 pages. | Same as T1. Verify back-to-back page processing. |
| T3 | NLB=63, PRP2=List. 4096 bytes. 8 pages. | Same as T1. Stress PRP list fetch engine. |

### Golden Reference Model

The testbench instantiates a simple NVM SRAM model and AXI slave model:
- **NVM model:** Pre-loaded with known data pattern at initialization. Responds to reads with 1-cycle latency.
- **AXI slave:** Captures write data. Compares captured data against expected (known NVM content at the expected offset). Reports mismatches.
- **Completion checker:** After `cpl_valid_o` handshake, verifies `cpl_cid_o`, `cpl_sqid_o`, `cpl_sqhd_o` match the issued command.

---

## 5. Deliverables Checklist

- [ ] `nvme_cmd_tracker.v` — synthesizable RTL
- [ ] `nvme_prp_walker.v` — synthesizable RTL (two-process FSM)
- [ ] `nvme_read_engine.v` — synthesizable RTL (three independent controllers, AW is two-process FSM)
- [ ] `nvme_axi_adapter.v` — synthesizable RTL
- [ ] `nvme_io_top.v` — top-level wiring
- [ ] `tb_nvme_io.v` — self-checking testbench (3 tests, golden reference model)
- [ ] `DEVELOPMENT_LOG.md` — bug tracking table filled during development

### Before Simulation (Step 7b Gate)

```bash
bash scripts/pre_sim_check.sh --all --top nvme_io_top *.v
```

All three checks (yosys synthesis, rtl_style_check, standalone compile) must pass before simulation.

### Coding Standard Verification

Run before submission:
```bash
python scripts/rtl_style_check.py *.v
```

Zero E-level findings required. W-level findings must be reviewed and documented in DEVELOPMENT_LOG.md.
