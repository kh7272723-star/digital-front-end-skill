# System Contract — NVMe Admin Command Engine (L2 Subsystem)

## System Overview

A minimal NVMe controller control path that handles host initialization, admin command fetch, admin command execution, and completion posting. Supports: Identify Controller, Create I/O CQ, Create I/O SQ. Uses simplified AXI memory interface instead of PCIe TLP.

```
                     ┌──────────────────────────────────────┐
  AXI (host mem) ◄──►│  nvme_ctrl_top                       │
                     │                                      │
   APB (config)  ◄──►│  ┌──────────────────────────────┐   │
                     │  │ nvme_reg_file (BAR0 + doorbell)│   │
                     │  │ CAP, VS, CC, CSTS, AQA, ASQ,  │   │
                     │  │ ACQ, doorbell shadow registers │   │
                     │  └──────────┬───────────────────┘   │
                     │             │ doorbell events        │
                     │  ┌──────────▼───────────────────┐   │
                     │  │ nvme_sq_fetch (SQ engine)     │   │
                     │  │ head/tail/credits per queue   │   │
                     │  │ AXI MRd → parse SQE           │   │
                     │  └──────────┬───────────────────┘   │
                     │             │ parsed command         │
                     │  ┌──────────▼───────────────────┐   │
                     │  │ nvme_admin_exec               │   │
                     │  │ Identify/Create CQ/Create SQ  │   │
                     │  └──────────┬───────────────────┘   │
                     │             │ completion data        │
                     │  ┌──────────▼───────────────────┐   │
                     │  │ nvme_cq_post (CQ engine)      │   │
                     │  │ Phase tag + AXI MWr           │   │
                     │  └──────────────────────────────┘   │
                     │                                      │
                     │  ┌──────────────────────────────┐   │
                     │  │ nvme_axi_adapter              │   │
                     │  │ AXI-Lite master → AR/AW/W/R   │   │
                     │  └──────────────────────────────┘   │
                     └──────────────────────────────────────┘
```

**Classification:** L2 Subsystem (5 modules, ~800 total lines, multi-module, new protocol)

## Design Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| MAX_QUEUES | 5 | Maximum supported queues (1 admin + 4 I/O) |
| MAX_QUEUE_DEPTH | 256 | Max entries per queue |
| AXI_DATA_W | 64 | AXI data width (64-bit for 64-byte SQE in 8 beats) |
| AXI_ADDR_W | 64 | AXI address width (64-bit host physical address) |
| PAGE_SIZE | 4096 | Memory page size (4KB, CC.MPS=0) |

## Module Interfaces

### 1. nvme_reg_file (BAR0 Register File)

**Ports:**

| Signal | Width | Dir | Description |
|--------|-------|-----|-------------|
| clk_i | 1 | in | Clock |
| rst_ni | 1 | in | Async active-low reset |
| psel_i | 1 | in | APB select |
| penable_i | 1 | in | APB enable |
| paddr_i | 16 | in | APB address (BAR0 offset) |
| pwrite_i | 1 | in | APB write=1 |
| pwdata_i | 32 | in | APB write data |
| prdata_o | 32 | out | APB read data |
| pready_o | 1 | out | APB ready |
| pslverr_o | 1 | out | APB error on invalid offset |
| ctrl_ready_o | 1 | out | Controller ready (CSTS.RDY) |
| admin_sq_base_o | 64 | out | Admin SQ base address (from ASQ register) |
| admin_cq_base_o | 64 | out | Admin CQ base address (from ACQ register) |
| admin_sq_depth_o | 16 | out | Admin SQ size + 1 (from AQA[27:16]) |
| admin_cq_depth_o | 16 | out | Admin CQ size + 1 (from AQA[11:0]) |
| doorbell_valid_o | 1 | out | Pulse: doorbell write detected |
| doorbell_qid_o | 8 | out | Queue ID for doorbell |
| doorbell_is_sq_o | 1 | out | 1=SQ tail, 0=CQ head |
| doorbell_value_o | 16 | out | New tail/head value |

**Register Implementation:**

| Offset | Name | Type | Reset | Description |
|--------|------|------|-------|-------------|
| 0x00 | CAP[31:0] | RO | MQES(255)<<16 \| DSTRD(0)<<32? No, CAP is 64-bit | CAP low: bits 31:0. MQES at bits 15:0 = 255 |
| 0x04 | CAP[63:32] | RO | 0 | CAP high: DSTRD at bits 3:0 = 0 |
| 0x08 | VS | RO | 0x00010400 | Version 1.4.0 |
| 0x14 | CC | RW | 0 | [0]=EN, [19:16]=MPS, [23:20]=CSS |
| 0x1C | CSTS | RO | 0 | [0]=RDY (set when CC.EN=1 and queues configured), [2]=NSSRO |
| 0x24 | AQA | RW | 0 | [11:0]=CQ size, [27:16]=SQ size |
| 0x28 | ASQ[31:0] | RW | 0 | Admin SQ base addr low |
| 0x2C | ASQ[63:32] | RW | 0 | Admin SQ base addr high |
| 0x30 | ACQ[31:0] | RW | 0 | Admin CQ base addr low |
| 0x34 | ACQ[63:32] | RW | 0 | Admin CQ base addr high |

**Doorbell detection:** APB writes to offset >= 0x1000 are doorbell writes. Decode:
- `offset = paddr_i - 16'h1000`
- `stride = 4` (DSTRD=0)
- `queue_id = offset / (2*stride) = offset / 8`
- `is_sq = (offset % (2*stride) < stride) = ((offset % 8) < 4)`
- `value = pwdata_i[15:0]`

**CSTS.RDY logic:** RDY=1 when CC.EN=1 AND ASQ!=0 AND ACQ!=0 AND AQA.SQSIZE!=0 AND AQA.CQSIZE!=0.

### 2. nvme_sq_fetch (SQ Fetch Engine)

**Ports:**

| Signal | Width | Dir | Description |
|--------|-------|-----|-------------|
| clk_i | 1 | in | Clock |
| rst_ni | 1 | in | Async active-low reset |
| sq_base_i | 64 | in | SQ base physical address |
| sq_depth_i | 16 | in | SQ entries (1-based, e.g., 256) |
| credits_i | 16 | in | New credits from doorbell monitor |
| credits_valid_i | 1 | in | Pulse: credits_i is valid |
| cq_id_i | 8 | in | Associated CQ ID (for routing completion) |

| axi_ar_valid_o | 1 | out | AXI Read Address valid |
| axi_ar_ready_i | 1 | in | AXI Read Address ready |
| axi_ar_addr_o | 64 | out | Read address (sq_base + head*64) |
| axi_ar_len_o | 8 | out | Burst length (7 for 8-beat, 64-byte read) |
| axi_ar_size_o | 3 | out | Burst size (3 for 8-byte beats) |

| axi_r_valid_i | 1 | in | AXI Read Data valid |
| axi_r_ready_o | 1 | out | AXI Read Data ready |
| axi_r_data_i | 64 | in | Read data (8 bytes per beat) |
| axi_r_last_i | 1 | in | Read last beat |

| cmd_valid_o | 1 | out | Pulse: parsed command available |
| cmd_ready_i | 1 | in | Downstream ready |
| cmd_opcode_o | 8 | out | SQE DW0[7:0] |
| cmd_cid_o | 16 | out | SQE DW0[31:16] |
| cmd_nsid_o | 32 | out | SQE DW1 |
| cmd_prp1_o | 64 | out | SQE DW6-7 |
| cmd_prp2_o | 64 | out | SQE DW8-9 |
| cmd_cdw10_o | 32 | out | SQE DW10 |
| cmd_cdw11_o | 32 | out | SQE DW11 |
| cmd_sqid_o | 8 | out | This SQ's ID |
| head_update_o | 16 | out | Updated SQ head after fetch |
| head_update_valid_o | 1 | out | Pulse: new head value |

**Internal State (per instantiated queue):**

| Register | Width | Reset | Description |
|----------|-------|-------|-------------|
| head_q | 16 | 0 | Current SQ head pointer |
| credits_q | 16 | 0 | Accumulated fetch credits |
| fetch_buf | 512 | — | 64-byte assembled SQE from 8×64-bit beats |

**FSM:** IDLE → (credits > 0) → AR_REQ → R_DATA_0..7 → PARSE → CMD_OUT → IDLE (or AR_REQ if more credits)

**Credits:** credits_q increments by credits_i on credits_valid_i pulse. Decremented by 1 when AR_REQ accepted (ar_valid && ar_ready).

### 3. nvme_admin_exec (Admin Command Executor)

**Ports:**

| Signal | Width | Dir | Description |
|--------|-------|-----|-------------|
| clk_i | 1 | in | Clock |
| rst_ni | 1 | in | Async active-low reset |
| cmd_valid_i | 1 | in | Command input valid |
| cmd_ready_o | 1 | out | Ready for command |
| cmd_opcode_i | 8 | in | Opcode |
| cmd_cid_i | 16 | in | Command ID |
| cmd_nsid_i | 32 | in | Namespace ID |
| cmd_prp1_i | 64 | in | PRP1 data pointer |
| cmd_prp2_i | 64 | in | PRP2 data pointer |
| cmd_cdw10_i | 32 | in | CDW10 |
| cmd_cdw11_i | 32 | in | CDW11 |
| cmd_sqid_i | 8 | in | Source SQ ID |

| cq_data_wr_o | 1 | out | Request to write CQ data (for Identify) |
| cq_data_addr_o | 64 | out | Physical address for data write |
| cq_data_o | 64 | out | Data word (8 bytes) |
| cq_data_valid_o | 1 | out | Data word valid |
| cq_data_last_o | 1 | out | Last data word |
| cq_data_ready_i | 1 | in | Write channel ready |

| cpl_valid_o | 1 | out | Completion ready |
| cpl_ready_i | 1 | in | CQ post engine ready |
| cpl_sqid_o | 8 | out | SQ ID for routing |
| cpl_sqhd_o | 16 | out | SQ Head at completion |
| cpl_cid_o | 16 | out | Command ID (echoed) |
| cpl_status_o | 16 | out | {reserved[15:8], DNR, M, SCT[2:0], SC[7:0]} |
| cpl_has_data_o | 1 | out | This completion has associated data write |

| queue_alloc_o | 1 | out | Pulse: allocate new queue |
| queue_id_o | 8 | out | Queue ID being created |
| queue_depth_o | 16 | out | Queue depth (1-based) |
| queue_is_sq_o | 1 | out | 1=SQ, 0=CQ |
| queue_cqid_o | 8 | out | Associated CQ (for SQ creation) |

**Supported Commands:**

| Opcode | Command | Processing |
|--------|---------|------------|
| 0x06 | Identify | CNS=01h: return 4096-byte controller data via cq_data. CNS=00h: return namespace data. Other CNS: error. |
| 0x05 | Create I/O CQ | Validate QID, QSIZE, PC. Allocate internal CQ state. Post completion. |
| 0x01 | Create I/O SQ | Validate QID, QSIZE, CQID exists. Allocate internal SQ state. Post completion. |
| Other | — | Post completion with Invalid Opcode (SC=0x01) |

**Identify Controller Data (minimal, 4096 bytes):**

| Offset | Bytes | Value | Field |
|--------|-------|-------|-------|
| 0x000 | 2 | 0xCA5E | VID (Vendor ID — placeholder) |
| 0x004 | 20 | "NVMe SSD" | SN (Serial Number, padded) |
| 0x018 | 40 | "Digital Front-End NVMe Ctrl" | MN (Model Number, padded) |
| 0x050 | 8 | "v1.0" | FR (Firmware Revision, padded) |
| 0x100 | 1 | 64 | SQES (SQ Entry Size = 2^6 = 64) |
| 0x101 | 1 | 16 | CQES (CQ Entry Size = 2^4 = 16) |
| 0x200 | 4 | MAX_QUEUES | NN (Number of Namespaces) — we only support 1 namespace, but this field is for max queues |

### 4. nvme_cq_post (CQ Post Engine)

**Ports:**

| Signal | Width | Dir | Description |
|--------|-------|-----|-------------|
| clk_i | 1 | in | Clock |
| rst_ni | 1 | in | Async active-low reset |
| cq_base_i | 64 | in | CQ base address |
| cq_depth_i | 16 | in | CQ depth (1-based) |

| cpl_valid_i | 1 | in | Completion from admin executor |
| cpl_ready_o | 1 | out | Ready for completion |
| cpl_sqid_i | 8 | in | SQ ID |
| cpl_sqhd_i | 16 | in | SQ head at completion |
| cpl_cid_i | 16 | in | Command ID |
| cpl_status_i | 16 | in | Status field |
| cpl_has_data_i | 1 | in | Has associated data (Identify) |

| cq_data_done_i | 1 | in | Identify data write complete |
| cq_data_head_i | 16 | in | CQ head for the data-associated completion |

| axi_aw_valid_o | 1 | out | AXI Write Address valid |
| axi_aw_ready_i | 1 | in | AXI Write Address ready |
| axi_aw_addr_o | 64 | out | Write address (cq_base + head*16) |
| axi_w_valid_o | 1 | out | AXI Write Data valid |
| axi_w_ready_i | 1 | in | AXI Write Data ready |
| axi_w_data_o | 64 | out | Write data (2 beats of 64-bit for 16-byte CQE) |
| axi_w_strb_o | 8 | out | Write strobe (all 1s) |
| axi_w_last_o | 1 | out | Last beat |

**Internal State:**

| Register | Width | Reset | Description |
|----------|-------|-------|-------------|
| head_q | 16 | 0 | Current CQ head pointer |
| phase_q | 1 | 0 | Current Phase Tag value |

**CQE Assembly (16 bytes):**
- DW0[31:0] = 0 (command-specific, admin commands return 0)
- DW1[31:0] = 0 (reserved)
- DW2[31:16] = cpl_sqid_i, DW2[15:0] = cpl_sqhd_i
- DW3[31:17] = cpl_status_i, DW3[16] = phase_q, DW3[15:0] = cpl_cid_i

**Phase toggle:** After writing CQE at position `head_q == depth_q - 1`, toggle `phase_q` on next wrap.

### 5. nvme_axi_adapter (Simplified AXI Adapter)

This module provides shared AXI-Lite master interface for all NVMe modules. It arbitrates read/write requests from SQ fetch engines and CQ post engines.

**Ports:**

| Signal | Width | Dir | Description |
|--------|-------|-----|-------------|
| clk_i | 1 | in | Clock |
| rst_ni | 1 | in | Reset |
| ar_req_valid_i | * | in | Per-source AR valid (bit-vector or single, muxed externally) |
| ar_req_ready_o | * | out | Per-source AR ready |
| ar_req_addr_i | 64×N | in | Read addresses |
| rsp_valid_o | * | out | Per-source R valid |
| rsp_data_o | 64×N | out | Read data |
| aw_req_valid_i | * | in | AW valid |
| aw_req_ready_o | * | out | AW ready |
| aw_req_addr_i | 64×N | in | Write addresses |
| w_req_valid_i | * | in | W valid |
| w_req_ready_o | * | out | W ready |
| w_req_data_i | 64×N | in | Write data |
| w_req_last_i | * | in | W last |
| axi_*_o | — | out | Standard AXI-Lite master ports |

**Simplification for Phase 1:** Since we only have 2 sources (1 SQ fetch + 1 CQ post for admin queue), the adapter can be a simple mux rather than full arbitration. The SQ fetch and CQ post won't operate simultaneously at this scale.

### 6. nvme_ctrl_top (Integration Top)

Minimal wiring module. Instantiates all sub-modules, connects:
- reg_file → sq_fetch (queue base/depth/credits)
- reg_file → cq_post (CQ base/depth)
- sq_fetch → admin_exec (parsed commands)
- admin_exec → cq_post (completions)
- sq_fetch, cq_post → axi_adapter → AXI master ports
- reg_file → external APB slave port

## Key Timing Contracts

### SQ Fetch → Command Parse Pipeline
- SQ fetch reads 8×64-bit beats → assembles 64-byte SQE → combinatorial parse → cmd_valid pulse
- Latency: 8 AXI R beats + 1 cycle for assembly
- Backpressure: cmd_ready_i gates cmd_valid_o

### Admin Command → Completion Pipeline
- Command received → execute (combinational for simple commands, multi-cycle for Identify data) → cpl_valid pulse
- For Identify: cq_data_wr_o drives ~512 beats of 64-bit data (4096 bytes / 8 bytes per beat)

### CQ Post → AXI Write Pipeline
- Completion received → assemble CQE → 2 AXI W beats (16 bytes / 8 bytes per beat)
- Phase tag updated after each CQE post

## Testbench Contract

The testbench simulates a host driver:
1. Write BAR0 registers (APB) to configure controller
2. Enable controller (CC.EN=1)
3. Place SQ entries in a simulated host memory array
4. Write SQ0 Tail Doorbell
5. Wait for CQE in simulated host memory (poll CQ memory)
6. Verify CQE fields (CID, status, phase)
7. Update CQ Head Doorbell

Host memory is a 64-bit wide array addressable by 64-bit physical addresses.
