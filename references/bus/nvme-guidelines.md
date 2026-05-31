# NVMe Controller Design Guidelines

## Purpose

This document defines the NVMe (NVM Express) protocol concepts needed for RTL design. It covers the queue model, doorbell mechanism, command format, and completion posting — the minimum set required to implement an NVMe controller's control path.

**Scope:** NVMe Base Spec 1.4c, PCIe transport only. Admin command set. Single controller, single namespace.

**Authority:** NVM Express Base Specification Revision 1.4c (2019), NVM Express PCIe Transport Specification.

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

**Empty condition:** `head == tail`
**Full condition (SQ):** `(tail + 1) % depth == head` (one slot unused as guard band)

Tail is NOT incremented modulo in the usual way. The tail pointer advances linearly and only wraps when reaching `2*depth` for CQ (due to Phase Tag). See Phase Tag section.

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
1. `delta = new_tail - old_tail` (number of new commands submitted)
2. Controller adds `delta` credits to internal credit accumulator for queue `y`
3. SQ Fetch Engine consumes credits when issuing Memory Read TLP for each command slot

When host writes a new head value to CQyHDBL:
1. Controller releases completed slots up to `new_head - 1`
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
| queue_depth | 16 | Number of entries (0-based: QSIZE) |
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
- CQE post is sequential: write DW0 → DW1 → DW2 → DW3 (ordered for Phase/CID visibility)

### P6 (Boundaries)
- NVMe-specific module outputs: fetched commands (structured, not raw 64-byte)
- Admin executor outputs: completion data + status
- CQ post engine input: structured CQE fields, output: AXI write transactions
