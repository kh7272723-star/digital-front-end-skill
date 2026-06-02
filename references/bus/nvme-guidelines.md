# NVMe Controller Design Guidelines

## Purpose

This document defines the NVMe (NVM Express) protocol concepts needed for RTL design. It covers the queue model, doorbell mechanism, command format, and completion posting — the minimum set required to implement an NVMe controller's control path.

**Scope:** NVMe Base Spec 2.3 + NVM Command Set 1.2, PCIe memory-based transport model. Admin command set + NVM I/O command set (Read/Write/Flush). PRP-based data transfer. Single controller, single namespace.

**Authority:**
- NVM Express Base Specification Revision 2.3 (2025-08-01) — queue model, doorbell, PRP/SGL, Admin commands, controller init, Flush command (§7.2)
- NVM Express NVM Command Set Specification Revision 1.2 (2025-08-01) — NVM Read (§3.3.1), Write (§3.3.4), I/O command opcodes, SLBA/NLB field definitions
- Local markdown extracts: `nvme-spec-2.3.md`, `nvme-nvm-cmd-set-1.2.md`. Treat this file as distilled guidance; re-check those extracts before adding new hard NVMe rules.

---

## 1. Queue Model

NVMe uses paired Submission Queues (SQ) and Completion Queues (CQ) in host memory. The controller reads commands from SQs and writes completions to CQs.

### Queue Types

| Queue | Purpose | Created By | Max Entries |
|-------|---------|-----------|-------------|
| Admin SQ (SQ0) | Controller management | Register writes | 2-4096 |
| Admin CQ (CQ0) | Controller management responses | Register writes | 2-4096 |
| I/O SQ (SQ1..N) | NVM read/write | Admin commands | 2-65535 |
| I/O CQ (CQ1..N) | NVM read/write responses | Admin commands | 2-65535 |

### Queue Entry Sizes (fixed)

| Entry Type | Size |
|-----------|------|
| Submission Queue Entry (SQE) | 64 bytes |
| Completion Queue Entry (CQE) | 16 bytes |

### Ring Buffer Semantics

Both SQ and CQ are circular buffers. The controller maintains Head pointer (next to process); the host maintains Tail pointer (next to write).

**Empty condition:** for an SQ, the controller has no newly submitted command when its local SQ head equals the last SQ tail doorbell value after modulo-depth wrap handling.
**Full condition:** NVMe memory-based queues use one unused slot; the maximum number of entries that can be queued is one less than the queue size. Queue wrap conditions must be included in comparisons.

Head and tail entry pointers wrap modulo the queue size. Completion Queue Phase Tag is a CQE bit used by the host to distinguish newly posted completions after CQ wrap; it does not make SQ/CQ pointers count to `2*depth`.

---

## 2. Doorbell Mechanism

Doorbell registers are MMIO locations in PCIe BAR0. The host writes to them to notify the controller of new commands (SQ Tail Doorbell) or consumed completions (CQ Head Doorbell).

### Doorbell Offset Calculation

```
SQ y Tail Doorbell:  BAR0 + 0x1000 + (2 * y) * stride
CQ y Head Doorbell:  BAR0 + 0x1000 + (2 * y + 1) * stride

where stride = 4 << CAP.DSTRD (usually 4 or 8 bytes)
```

### Doorbell Register Format (32-bit)

| Bits | Field | Description |
|------|-------|-------------|
| 15:0 | Value | New tail/head pointer |
| 31:16 | Reserved | Ignored |

### Credit Model

When host writes a new tail value to SQyTDBL:
1. `delta = (new_tail - old_tail) modulo queue_depth` with queue wrap conditions handled (number of new commands submitted)
2. Controller adds `delta` credits to internal credit accumulator for queue `y`
3. SQ Fetch Engine consumes credits when issuing Memory Read TLP for each command slot

When host writes a new head value to CQyHDBL:
1. Controller releases completed slots up to `new_head - 1`, with queue wrap conditions handled
2. Controller can now reuse those CQ slots for new completions

---

## 3. Submission Queue Entry (SQE) Format (64 bytes)

### DWORD Layout

| DWORD | Bytes | Field | Width | Description |
|-------|-------|-------|-------|-------------|
| DW0 | 03:00 | CDW0 | 32 | OPC[7:0], FUSE[9:8], PSDT[15], CID[31:16] |
| DW1 | 07:04 | NSID | 32 | Namespace ID (0=no namespace) |
| DW2-3 | 15:08 | RSVD | 64 | Reserved (zero) |
| DW4-5 | 23:16 | MPTR | 64 | Metadata pointer (not used for Admin) |
| **DW6-7** | **31:24** | **PRP1** | **64** | **First data pointer (64-bit physical addr)** |
| **DW8-9** | **39:32** | **PRP2** | **64** | **Second data pointer or PRP list pointer** |
| DW10 | 43:40 | CDW10 | 32 | Command-specific (e.g., QID, QSIZE for Create SQ) |
| DW11 | 47:44 | CDW11 | 32 | Command-specific (e.g., CQID, PC, QPRIO) |
| DW12 | 51:48 | CDW12 | 32 | Command-specific |
| DW13 | 55:52 | CDW13 | 32 | Command-specific |
| DW14 | 59:56 | CDW14 | 32 | I/O only, reserved in Admin |
| DW15 | 63:60 | CDW15 | 32 | I/O only, reserved in Admin |

### CDW0 Bit Fields

| Bits | Field | Description |
|------|-------|-------------|
| 7:0 | OPC | Opcode (00h=Delete I/O SQ, 01h=Create I/O SQ, 04h=Delete I/O CQ, 05h=Create I/O CQ, 06h=Identify) |
| 9:8 | FUSE | 00=normal operation |
| 15 | PSDT | 0=PRP used (Admin always uses PRP) |
| 31:16 | CID | Command Identifier (per-SQ unique, echoed in CQE) |

### Key Admin Command Fields

#### Identify (OPC=06h)
- **DW10[7:0]:** CNS (Controller or Namespace Structure)
  - `8'h01` = Identify Controller → returns 4096-byte Controller Identify Data
  - `8'h00` = Identify Namespace → returns 4096-byte Namespace Identify Data
- **DW10[31:16]:** CNS-specific (0 for CNS=01h/00h)
- **PRP1:** Physical address where the 4096-byte response data should be written
- **PRP2:** If data crosses page boundary, PRP2 has second page address

#### Create I/O Completion Queue (OPC=05h)
- **DW10[15:0]:** QID (created CQ ID, > 0)
- **DW10[31:16]:** QSIZE (0-based, e.g., 255 for 256-entry queue)
- **DW11[0]:** PC (1=Physically Contiguous queue memory)
- **DW11[17:16]:** IEN (Interrupt Enable, 0=no interrupt)
- **DW11[31:19]:** IV (Interrupt Vector for MSI-X, 0 if IEN=0)
- **PRP1:** Physical address of CQ memory (64-byte aligned)

#### Create I/O Submission Queue (OPC=01h)
- **DW10[15:0]:** QID (created SQ ID, > 0)
- **DW10[31:16]:** QSIZE (0-based)
- **DW11[0]:** PC (1=Physically Contiguous)
- **DW11[3:2]:** QPRIO (00=Urgent, 01=High, 10=Medium, 11=Low)
- **DW11[15:4]:** CQID (associated CQ identifier, must already exist)
- **PRP1:** Physical address of SQ memory (page-aligned for PC=1)

### Status Code (SC) for CQE

| SC | Name | Description |
|----|------|-------------|
| 0x00 | Success | Command completed without error |
| 0x01 | Invalid Opcode | Opcode not supported |
| 0x02 | Invalid Field | Invalid field in command |
| 0x0B | Invalid Queue Identifier | QID or CQID not valid |
| 0x0C | Invalid Queue Size | QSIZE exceeds CAP.MQES |
| 0x0D | Invalid Queue Create | Queue already exists or CQ doesn't exist |

---

## 4. Completion Queue Entry (CQE) Format (16 bytes)

| DWORD | Bits | Field | Description |
|-------|------|-------|-------------|
| DW0 | 31:0 | Command Specific | Echoed from command or result data |
| DW1 | 31:0 | Reserved | Zero (for basic admin commands) |
| DW2 | 31:16 | SQID | Source Submission Queue ID |
| DW2 | 15:0 | SQHD | SQ Head Pointer at completion time |
| DW3 | 31:17 | Status | SCT[29:27] + SC[24:17] |
| **DW3** | **16** | **P** | **Phase Tag (toggled on each CQ wrap)** |
| DW3 | 15:0 | CID | Command Identifier (echoed from SQE) |

### Phase Tag (P bit)

The host initializes ALL CQ entries to `P = 0`. On the first pass through the CQ, the controller writes `P = 1`. After wrapping, the controller writes `P = 0`. On the third pass, `P = 1` again, etc.

```
Pass 0 (host init): P[0..depth-1] = 0
Pass 1 (controller): P[0..depth-1] = 1
Pass 2 (controller): P[0..depth-1] = 0
Pass 3 (controller): P[0..depth-1] = 1
```

The host detects new completions by reading the Phase bit: if `P == expected_phase`, CQE is valid. The host increments its own phase each time CQ head wraps.

### CQ Head Management

- Controller writes CQE to `CQ_base + (CQ_head * 16)`
- After writing, `CQ_head++`
- If `CQ_head == CQ_depth`: `CQ_head = 0`, toggle phase

---

## 5. BAR0 Register Map (Relevant Subset)

| Offset | Size | Register | Description |
|--------|------|----------|-------------|
| 0x00 | 8 | CAP | Controller Capabilities (read-only) |
| 0x08 | 4 | VS | Version (1.4.0 = 0x00010400) |
| 0x14 | 4 | CC | Controller Configuration |
| 0x1C | 4 | CSTS | Controller Status |
| 0x24 | 4 | AQA | Admin Queue Attributes (SQ size[27:16], CQ size[11:0]) |
| 0x28 | 8 | ASQ | Admin SQ Base Address (64-bit) |
| 0x30 | 8 | ACQ | Admin CQ Base Address (64-bit) |
| 0x1000 | ... | Doorbells | SQ/CQ doorbell array |

### Key CAP Fields

| Bits | Field | Typical Value | Description |
|------|-------|:---:|------|
| 15:0 | MQES | 255 | Max Queue Entries Supported |
| 35:32 | DSTRD | 0 | Doorbell Stride |

### CC (Controller Configuration) Fields

| Bits | Field | Description |
|------|-------|------|
| 0 | EN | Enable (1=controller operational) |
| 13:7 | IOCQES | I/O CQ Entry Size (typically 4 for 16-byte entries: 2^4=16) |
| 19:16 | MPS | Memory Page Size (0=4KB) |
| 23:20 | CSS | I/O Command Set (0=NVM) |

### CSTS (Controller Status) Fields

| Bits | Field | Description |
|------|-------|------|
| 0 | RDY | Ready (1 after CC.EN set and init complete) |
| 2 | NSSRO | NVM Subsystem Reset Occurred |

---

## 6. Host Initialization Sequence

```
1. Host reads CAP to check MQES, DSTRD
2. Host writes CC.EN = 0, waits for CSTS.RDY = 0 (controller disable)
3. Host writes ASQ (Admin SQ base address in host memory)
4. Host writes ACQ (Admin CQ base address in host memory)
5. Host writes AQA (SQ size[27:16] | CQ size[11:0])
6. Host writes CC.EN = 1 with MPS=0, CSS=0, IOCQES=4, IOSQES=6
7. Controller sets CSTS.RDY = 1 when ready
8. Host writes first Admin command to SQ0
9. Host rings SQ0 Tail Doorbell
10. Controller fetches and executes command
11. Controller posts CQE to CQ0
12. Host reads CQE, updates CQ0 Head Doorbell
```

---

## 7. Controller Internal State (per queue)

Each SQ/CQ pair tracks:

| State | Width | Description |
|-------|-------|------|
| queue_base | 64 | Host physical address of queue memory |
| queue_depth | 16 | Number of entries (`QSIZE + 1`; NVMe QSIZE fields are zero-based) |
| head_ptr | 16 | Next entry for controller to process (SQ) or write (CQ) |
| tail_ptr | 16 | Last known host tail (set by doorbell) |
| credits | 16 | Pending commands to fetch (tail - head) |
| cq_id | 16 | Associated CQ (for SQ only) |
| phase | 1 | Current CQE phase tag (for CQ only) |
| active | 1 | Queue is allocated and valid |

---

## 8. Simplified Memory Interface (Instead of PCIe TLP)

For this first project, replace PCIe TLP with a simplified AXI-based memory interface:

### Command Fetch (equivalent to MRd + CplD)
```
Controller → AXI AR channel: read request at {queue_base + head_ptr * entry_size, length}
Controller ← AXI R channel:  data beats (64-byte SQE or 16-byte CQE slot)
```

### Completion Post (equivalent to MWr)
```
Controller → AXI AW channel: write request at {cq_base + cq_head * 16, length=16}
Controller → AXI W channel:  16-byte CQE data
```

### Doorbell (equivalent to MWr to BAR0)
Simulated by testbench task: `write_doorbell(queue_id, new_tail);`
Internal: detected by monitoring APB/AXI-Lite writes to doorbell address range.

---

## 9. Design Constraints (Skill Principle Mappings)

### P4 (Independence)
- Each SQ/CQ pair must have independent fetch/post state machines
- Doorbell writes to different queues must not block each other
- Admin command execution must not block doorbell monitoring

### P2 (FSM Safety)
- SQ fetch FSM: IDLE → CMD_REQ → WAIT_DATA → PARSE → IDLE
- Must have timeout/abort if CplD never arrives
- After reset: all fetch engines return to IDLE

### P3 (Known Values)
- Every queue state register must have explicit reset
- Phase tag reset to 0 for each CQ
- Credit counters reset to 0

### P1 (Timing Contract)
- Doorbell write takes effect on the cycle after write strobe
- SQE parsing is combinational from fetched data (after R channel data valid)
- If a CQE is constructed with multiple memory writes, update the Phase Tag bit in the last write so the host does not observe a partially written completion as new.

### P6 (Boundaries)
- NVMe-specific module outputs: fetched commands (structured, not raw 64-byte)
- Admin executor outputs: completion data + status
- CQ post engine input: structured CQE fields, output: AXI write transactions

---

## 10. NVM I/O Command Set — Read, Write, Flush

### 10.1 Opcodes (CDW0[7:0])

| Command | Opcode | Data Transfer | Direction |
|---------|:------:|:-------------:|-----------|
| Flush | 00h | None | — |
| Write | 01h | Yes | Host → Controller |
| Read | 02h | Yes | Controller → Host |
| Write Uncorrectable | 04h | Yes | Host → Controller |
| Compare | 05h | Yes | Bidirectional |
| Write Zeroes | 08h | Yes | Host → Controller |
| Dataset Management | 09h | Yes | Host → Controller |
| Verify | 0Ch | No | — |

All NVM I/O commands use the NSID field. FFFFFFFFh is not supported except where explicitly noted.

### 10.2 Read Command (Opcode 02h)

Reads data and metadata (if applicable) from the controller for the LBAs indicated.
Data direction: Controller → Host Memory (via PRP/SGL).

**SQE Dword assignments:**

| DWORD | Bits | Field | Description |
|-------|------|-------|-------------|
| DW0 | 7:0 | OPC | 02h |
| DW0 | 15 | PSDT | 0=PRP (PCIe memory model), 1/2=SGL |
| DW0 | 31:16 | CID | Command Identifier |
| DW1 | 31:0 | NSID | Namespace ID |
| DW10-11 | 63:0 | **SLBA** | Starting LBA (64-bit). DW10[31:0], DW11[63:32] |
| DW12 | 15:0 | **NLB** | Number of Logical Blocks (0's based: 0=1 block) |
| DW12 | 19:16 | CETYPE | Command Extension Type (0h = normal) |
| DW12 | 24 | STC | Storage Tag Check |
| DW12 | 29:26 | PRINFO | Protection Information action/check |
| DW12 | 30 | FUA | Force Unit Access |
| DW12 | 31 | LR | Limited Retry |
| DW13 | 7:0 | DSM | Dataset Management attributes (if CETYPE=0h) |
| DW14-15 | — | ELBST/EILBRT | Expected protection info tags (if namespace formatted with PI) |

**Data transfer length:** `transfer_bytes = (NLB + 1) × LBA_size` (LBA_size from Identify Namespace, typically 512 bytes or 4 KiB).

**Note:** The host may specify FUA=1 to require non-volatile medium commit before returning data.

### 10.3 Write Command (Opcode 01h)

Writes data and metadata (if applicable) to the controller for the logical blocks indicated.
Data direction: Host Memory → Controller (via PRP/SGL).

**SQE Dword assignments:** Same field layout as Read (DW10-DW15), except:

| DWORD | Bits | Field | Difference from Read |
|-------|------|-------|---------------------|
| DW12 | 23:20 | DTYPE | Directive Type (not present in Read) |
| DW13 | 31:16 | DSPEC | Directive Specific (if CETYPE=0h) |

**FUA behavior:** If FUA=1, the controller shall write data and metadata to non-volatile medium before posting CQE.

### 10.4 Flush Command (Opcode 00h)

**Defined in:** Base Spec §7.2.

Commits volatile write cache contents to non-volatile medium. No data transfer.
The command uses only CDW0, NSID, and the FB (Flush Behavior) field.

If NSID = FFFFFFFFh and FB field supports it, applies to all namespaces attached to the controller.

### 10.5 Key Design Constraints for NVM I/O

- **NLB=0 means 1 logical block** — this is a common off-by-one trap. Transfer size = `(NLB + 1) × LBA_size`.
- **SLBA + NLB must not exceed namespace capacity** — the controller shall check bounds and abort with LBA Out of Range if violated.
- **Read and Write to the same LBA have no ordering guarantee** (Base Spec §3.3.2.1.1). A Read may complete before or after a concurrent Write to LBA x.
- **PRP or SGL, not both** — CDW0.PSDT selects the data pointer type for the entire command.

---

## 11. PRP Traversal Algorithm

### 11.1 PRP Entry Format (64-bit)

```
Bits [63:n+1]  Page Base Address (aligned to memory page size)
Bits [n:2]     Offset within page (n = log2(page_size) - 1)
Bits [1:0]     Must be 00b (dword-aligned)
```

For a 4 KiB page (CC.MPS=0): n=11, Offset = bits [11:2].

### 11.2 PRP Roles in a Command

```
PRP1 (SQE Bytes 31:24):
  - ALWAYS contains the first data page address
  - May have a non-zero Offset (data starts mid-page)

PRP2 (SQE Bytes 39:32):
  - Case A: Reserved          — total data fits in PRP1 page
  - Case B: Page Base Address — data crosses exactly 1 page boundary
  - Case C: PRP List Pointer  — data crosses >1 page boundaries
```

### 11.3 PRP List Structure

A PRP List occupies ONE physical memory page (4 KiB for MPS=0).

```
Entries per List page = page_size / 8 = 512 (for 4 KiB pages)

Entry 0..N:    Page Base Address (Offset MUST be 0h, page-aligned)
Last entry of a full list page:
               Next PRP List page base address, only when another list page is required
```

**Rules:**
1. PRP entries within a PRP List must have Offset = 0 (page-aligned)
2. If more PRP List pages are required, the last entry before the end of the current list page points to the NEXT PRP List page
3. PRP List pages themselves must be page-aligned
4. Entries are packed starting at entry 0 — no gaps
5. The total number of PRP entries needed is implied by `(NLB+1) × LBA_size` and page_size

### 11.4 Hardware Traversal Algorithm

```verilog
// Pseudo-code for PRP traversal FSM
// Inputs: prp1[63:0], prp2[63:0], transfer_bytes, page_size
// Output: sequential page_base addresses for AXI transactions

page_offset  = prp1[11:0];  // for 4KB pages
current_addr = {prp1[63:12], 12'h000};  // first page base
remaining    = transfer_bytes;
in_list      = 0;  // 0 = using PRP1/PRP2, 1 = traversing PRP List
list_page_addr = prp2;  // only valid if PRP2 is list pointer
list_index   = 0;
list_entries_per_page = page_size / 8;  // 512 for 4KB

while (remaining > 0) begin
    // 1. Calculate bytes from this page
    bytes_this_page = page_size - page_offset;
    if (bytes_this_page > remaining)
        bytes_this_page = remaining;
    
    // 2. Issue AXI transfer: current_addr[63:n], page_offset, bytes_this_page
    
    // 3. Update
    remaining   -= bytes_this_page;
    page_offset  = 0;  // All subsequent pages start at offset 0
    
    if (remaining == 0) break;
    
    // 4. Get next page address
    if (!in_list) begin
        // First transition: check whether PRP2 is page or list
        if (this is the first boundary cross 
            && transfer_bytes <= page_size + (page_size - prp1.offset))
            next_addr = prp2;  // Case B: PRP2 is second page
        else begin
            // Case C: PRP2 points to PRP List
            in_list = 1;
            list_page_addr = prp2;
            list_index = 0;
            // Fetch PRP List page from host memory via AXI
            // next_addr = first entry of fetched list
        end
    end else begin
        // Traversing PRP List
        if (list_index == list_entries_per_page - 1) begin
            // Last entry of current list page → chain to next list page
            list_page_addr = current_list_entry;
            list_index = 0;
            // Fetch next PRP List page via AXI
        end else begin
            // Normal PRP entry
            next_addr = current_list_entry;
            list_index++;
        end
    end
    
    current_addr = next_addr;
end
```

### 11.5 PRP Error Cases to Handle

| Error | Condition | Expected Status |
|-------|-----------|----------------|
| PRP Offset Invalid | PRP entry within list has non-zero offset | 0x13 (PRP Offset Invalid) |
| PRP Offset Invalid | PRP list pointer not page-aligned | 0x13 |
| Data Transfer Error | AXI read/write fails during transfer | Depends on transport |

### 11.6 Determining PRP2 Role (Hardware Decision)

```
// Given: transfer_bytes = (NLB + 1) × LBA_size
//         page_size = 2^(12 + CC.MPS)
//         prp1_offset = PRP1[11:0] (for MPS=0)

first_page_capacity = page_size - prp1_offset;

if (transfer_bytes <= first_page_capacity):
    PRP2 = Reserved (not used)
elif (transfer_bytes <= first_page_capacity + page_size):
    PRP2 = Second memory page base address
else:
    PRP2 = PRP List pointer (page-aligned address of first list page)
```

---

## 12. I/O Data Transfer Flow

### 12.1 Read Command Flow (Controller → Host Memory)

```
Phase 1: Command Fetch
  Host: writes SQE to I/O SQ in host memory
  Host: rings SQyTDBL doorbell
  Controller: detects doorbell write → adds credits → fetches SQE via AXI AR/R
  Controller: parses SQE → identifies Read command (OPC=02h)

Phase 2: PRP Walk + Data Buffer Allocation
  Controller: reads PRP1 from SQE bytes 31:24
  Controller: computes transfer_bytes = (NLB+1) × LBA_size
  Controller: determines if PRP2 is page/list/reserved
  Controller: if PRP List needed, fetches first PRP List page via AXI AR/R
  Controller: allocates internal data buffer (depth ≥ AXI read latency × beat_size)

Phase 3: NVM Read
  Controller: issues NVM read for SLBA..SLBA+NLB
  Controller: NVM media returns data into internal buffer

Phase 4: Data Write to Host Memory (PRP-guided AXI Writes)
  For each page from PRP traversal:
    Controller → AXI AW: write addr = page_base + offset, len = min(remaining, page_size-offset)
    Controller → AXI W:  data beats from internal buffer
    Controller ← AXI B:  response
    Advance to next PRP entry

Phase 5: Completion Post
  Controller: builds CQE (CID echoed, SQID, SQHD, Phase Tag, Status=0x00)
  Controller → AXI AW/W: write CQE to CQ slot (cq_base + cq_head × 16)
  Controller: increments CQ head, toggles phase if wrap
  Controller: may generate MSI-X interrupt if IEN enabled
```

### 12.2 Write Command Flow (Host Memory → Controller)

```
Phase 1: Command Fetch (same as Read)
  Controller fetches SQE, identifies Write command (OPC=01h)

Phase 2: PRP Walk + Data Fetch from Host Memory
  Controller: same PRP logic as Read
  For each page from PRP traversal:
    Controller → AXI AR: read addr = page_base + offset, len = min(remaining, page_size-offset)
    Controller ← AXI R:  data beats → internal buffer

Phase 3: NVM Write
  Controller: writes buffered data to NVM media
  If FUA=1: wait for non-volatile commit before proceeding

Phase 4: Completion Post (same as Read)
```

### 12.3 Flush Command Flow

```
Phase 1: Command Fetch (same)
  Controller parses Flush command (OPC=00h)

Phase 2: Commit
  Controller: commits all volatile write cache data to NVM
  No data transfer. No PRP used.

Phase 3: Completion Post (same)
```

### 12.4 AXI Transaction Mapping

| NVMe Operation | AXI Channel | Width | Max Burst Length |
|---------------|-------------|-------|------------------|
| SQE Fetch (64 bytes) | AR/R | 64-bit | 8 beats (64B) |
| CQE Post (16 bytes) | AW/W/B | 64-bit | 2 beats (16B) |
| PRP List Page Fetch (4 KiB) | AR/R | 64/128-bit | 64/32 beats |
| Read Data to Host | AW/W/B | 64/128-bit | Per-page, max 4 KiB |
| Write Data from Host | AR/R | 64/128-bit | Per-page, max 4 KiB |

**Key AXI constraint:** Read data writes (AW/W/B) and Write data fetches (AR/R) target HOST MEMORY addresses from PRP entries. The controller is the AXI master — it initiates all memory transactions.

---

## 13. I/O Command Lifecycle

### 13.1 Complete Flow (Doorbell → CQE)

```
1. Host prepares SQE in I/O SQ memory
2. Host writes SQyTDBL = new_tail
3. Controller: credits += `(new_tail - old_tail) modulo queue_depth`
4. Controller: while (credits > 0 && SQ not empty):
     a. Fetch 64-byte SQE from SQ[head] via AXI AR/R
     b. Parse CDW0 → identify opcode, CID
     c. Parse CDW1 → NSID
     d. Route to appropriate command executor:
        - Read → Read engine
        - Write → Write engine
        - Flush → Flush engine
     e. Executor runs PRP walk + data transfer (see §12)
     f. Executor signals completion
     g. CQE post engine writes CQE to CQ[cq_head]
     h. SQ head++, CQ head++, credits--
     i. If CQ head wraps: toggle phase
5. Host polls CQ, detects new CQE via Phase Tag
6. Host processes CQE, writes CQyHDBL = new_head
```

### 13.2 Multi-Command Concurrency

The Base Spec explicitly allows controllers to execute commands in any order (§2.1). Key implications for RTL:

- **Multiple commands may be in flight simultaneously** — each requires independent state tracking
- **CQE posting order is NOT required to match SQE fetch order** — except where FUA ordering applies
- **CID + SQID uniquely identifies each command's CQE** — the host uses these to match completions to submissions
- **Phase Tag enables polling** — host doesn't need interrupts to detect completions

### 13.3 Outstanding Command Tracking (Design Pattern)

Each in-flight I/O command needs:

| State | Width | Description |
|-------|-------|-------------|
| cmd_valid | 1 | This tracker slot is occupied |
| cid | 16 | Command Identifier (echoed in CQE) |
| sqid | 16 | Source SQ (for CQE.SQID) |
| nsid | 32 | Namespace (for address validation) |
| opcode | 8 | Read/Write/Flush (for data path routing) |
| slba | 64 | Starting LBA (for NVM access) |
| nlb | 16 | Block count (for transfer length) |
| prp_current_addr | 64 | Current PRP page being processed |
| prp_list_addr | 64 | Current PRP List page (if traversing) |
| prp_list_index | 9 | Entry index within PRP List page (0..511) |
| bytes_remaining | 32 | Bytes left to transfer |
| phase | 3 | FSM state: IDLE→FETCH_DATA→POST_CQE→IDLE |

**Design decision:** The number of outstanding command slots determines the controller's I/O depth. For Phase 2, 4-8 slots is a reasonable starting point.

---

## 14. Updated Design Constraints (Phase 2 Additions)

### P4 (Independence) — extended
- Each I/O SQ/CQ pair must have **independent command fetch** and completion post state machines
- Read data path (AXI AW/W/B to host) and Write data path (AXI AR/R from host) must be **independent channels**
- PRP List fetch (AXI AR/R from host) must not block command execution on other queues
- Multiple outstanding commands must not share PRP traversal state

### P2 (FSM Safety) — extended
- PRP traversal FSM: IDLE → FIRST_PAGE → CHECK_PRP2 → (PAGE_TX | LIST_FETCH → LIST_WALK → PAGE_TX) → DONE → POST_CQE
- Must handle: PRP1-only (small transfer), PRP2-as-page (2-page transfer), PRP2-as-list (multi-page transfer)
- List chain termination: detect last list page when last entry before entry[entries_per_page-1] is used and remaining bytes fit
- Abort path: if AXI read/write returns error during data transfer → abort with Data Transfer Error status
- After reset: all outstanding command trackers released, all engines return to IDLE

### P3 (Known Values) — extended
- All PRP traversal registers (current_addr, bytes_remaining, list_index) must have explicit reset
- Outstanding command tracker slots reset to cmd_valid=0
- Internal data buffer pointers reset to empty
- NLB=0 (1 block) must be handled correctly — common off-by-one trap

### P1 (Timing Contract) — extended
- PRP1 offset only applies to the first AXI transaction; all subsequent pages start at offset 0
- SQE parsing is combinational from fetched data
- CQE post must occur AFTER all data transfer completes AND (for Write+FUA) NVM commit
- Data transfer completion = all AXI responses received (B response for Writes, R last beat for Reads)

### P6 (Boundaries) — extended
- Command parser output: structured fields (opcode, CID, NSID, SLBA, NLB, PRP1, PRP2) — not raw bytes
- PRP walker output: sequence of {addr, length} for AXI transactions
- Read data engine output: AXI AW/W transactions to host memory
- Write data engine output: AXI AR/R transactions from host memory
- CQE post engine: same interface as Admin (structured → AXI write)
