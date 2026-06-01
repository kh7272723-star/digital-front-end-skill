# Step 2a — P4+P6 Principle Review (Independence & Boundaries)

**Complexity:** L2 Subsystem (4 new modules + 3 reused, ~850 new RTL, multi-module, AXI multi-source)
**Timing:** Contract stage — before any RTL

---

## P4: Independence

### Q1. What independent concerns exist in this design? Are they actually decoupled?

**Five independent concerns identified:**

| Concern | Modules | Coupling Risk |
|---------|---------|:---:|
| SQ command fetch | nvme_sq_fetch (reused) | AXI AR shared with PRP list fetch |
| CQE completion post | nvme_cq_post (reused) | AXI AW/W shared with read engine |
| PRP address traversal | nvme_prp_walker (new) | Must not block command fetch indefinitely |
| Data transfer (NVM→host) | nvme_read_engine (new) | Uses AXI AW/W/B independently |
| Command tracking | nvme_cmd_tracker (new) | Each slot independent; issue is serialized |

**Analysis:** The critical coupling point is the AXI adapter — 4 sources sharing 2 channel pairs (AR+R, AW+W+B). Fixed-priority arbitration is chosen. But P4 demands we verify:

- **AR channel:** PRP list fetch (S2) > SQ fetch (S0). PRP list fetch is a single 512-beat burst, bounded to ~2.05 μs @ 250MHz. SQ fetch can tolerate this — SQ depth is typically large and commands queue up.
- **AW/W channel:** Read engine (S3) > CQ post (S1). Read engine may be active for a long multi-page transfer. CQ post is only 2 beats — but must wait for read engine to finish. **Risk: CQE posting delayed by long data transfer.** Mitigation: read engine yields AW between pages (deasserts AWVALID after each page's last WLAST). CQ post can interleave between pages.

**Decision:** Document the AW inter-page yield behavior explicitly in read_engine: after `page_done_o`, deassert all AW/W signals, allowing CQ post to grab the bus. This is the P4 compliance fix.

### Q2. Can a transaction on one interface accidentally consume or corrupt data on another?

**AXI adapter R channel demux:** R responses from host memory must be routed to the correct source (S0=SQ fetch or S2=PRP walker). The demux uses `ar_source_q[1:0]` register to track who issued the pending AR.

**Risk:** If a new AR is issued before the previous AR's R response completes, `ar_source_q` could be overwritten. **Analysis:** SQ fetch issues 8-beat bursts, PRP walker issues 512-beat bursts. Both must complete before issuing a new AR. Each source naturally serializes its own ARs (SQ fetch FSM waits for RLAST; PRP walker FSM also waits for RLAST). No interleaving is possible — the next source waits for the current R burst to complete.

**Verdict:** Safe. The AR channel is naturally serialized by the burst protocol. No data corruption risk.

**AXI adapter W channel mux:** S3 (read engine) and S1 (CQ post) share AW/W. The adapter must not mix S1 W data into S3's burst or vice versa. The mux uses `aw_source_q` to keep W aligned with AW.

**Verdict:** Safe. W data is muxed by the same source select as AW. Both sources use sequential W beats (no interleaving).

### Q3. Are AXI AW, W, B channels independently controlled?

**Status:** The contract mandates three independent controllers in nvme_read_engine (P13 compliance). The existing sq_fetch (AR+R) and cq_post (AW+W+B) already use independent channel controllers from Phase 1.

**Specific concern — Read Engine:** The AW controller computes burst_len and issues AWVALID. The W controller manages WVALID = w_active_q only. The B controller tracks b_outstanding. The contract explicitly says "w_active_q set on burst start, cleared on WLAST" — no FIFO state dependency mid-burst (P12).

**Verdict:** Contract design is P13-compliant. Need to verify during RTL review that the implementation doesn't couple AW/W/B.

### Q4. Can the PRP walker's AXI AR (list fetch) deadlock with the read engine's AXI AW/W?

**Scenario:** PRP walker issues AR for PRP list fetch. Read engine simultaneously tries to issue AW for data write. Both go to the same AXI adapter, which routes them to different master channels (AR vs AW) — these are independent AXI channels.

**Analysis:** AR and AW are independent AXI channels. The adapter handles them separately. No deadlock possible at the adapter level.

**Verdict:** Safe — P4 compliance verified at the AXI specification level. The only shared resource is the AXI adapter's combinational mux, which doesn't block.

### Q5. Are read and write command paths decoupled?

**Status:** Phase 3 only implements Read. No Write path exists yet. But the architecture must not preclude adding Write later.

**Analysis:** The PRP walker is read/write agnostic (emits page addresses). The read_engine consumes page addresses and drives AXI AW/W/B. A future write_engine would consume the same page addresses and drive AXI AR/R. Since AR and AW/W/B are independent AXI channels, read and write can coexist without coupling.

**Decision:** The PRP walker's `page_addr/page_bytes/page_valid` interface is deliberately generic — it doesn't know whether the consumer is read or write engine. This enables Phase 3b extension without refactoring.

---

## P6: Boundaries

### Q1. Does every module boundary have an explicit contract?

**Status:** system-contract.md defines port lists, timing contracts, and invariants for all 4 new modules. Reused modules (sq_fetch, cq_post, reg_file) have existing contracts from Phase 1.

**Missing:** The NVM SRAM interface (nvm_addr_o, nvm_rd_en_o, nvm_rdata_i, nvm_rvalid_i) is defined in the contract but its read latency (1 cycle) and width (64-bit) are assumptions. The testbench must match.

**Decision:** Document NVM SRAM timing contract explicitly:
- `nvm_rd_en_o` asserted → `nvm_rdata_i` valid on NEXT cycle (1-cycle read latency)
- `nvm_rvalid_i` = 1 on the cycle data is valid
- Read engine drives `nvm_rready_o` = 1 during active transfer
- 64-bit aligned access only (nvm_addr_o[2:0]=0)

### Q2. Do producer and consumer port widths match exactly?

**Cross-module width audit:**

| Producer Signal | Width | Consumer Signal | Width | Match? |
|-----------------|-------|-----------------|-------|:---:|
| cmd_tracker.prp_prp1_o | 64 | prp_walker.prp1_i | 64 | ✅ |
| cmd_tracker.prp_prp2_o | 64 | prp_walker.prp2_i | 64 | ✅ |
| cmd_tracker.prp_transfer_bytes_o | 32 | prp_walker.transfer_bytes_i | 32 | ✅ |
| cmd_tracker.rd_slba_o | 64 | read_engine.slba_i | 64 | ✅ |
| cmd_tracker.rd_total_bytes_o | 32 | read_engine.total_bytes_i | 32 | ✅ |
| prp_walker.page_addr_o | 64 | read_engine.page_addr_i | 64 | ✅ |
| prp_walker.page_bytes_o | 16 | read_engine.page_bytes_i | 16 | ✅ |
| read_engine.nvm_addr_o | 64 | nvme_io_top.nvm_addr_o | 64 | ✅ |
| read_engine.axi_aw_addr_o | 64 | axi_adapter.s3_aw_addr_i | 64 | ✅ |
| cmd_tracker.cpl_sqhd_o | 16 | cq_post.cpl_sqhd_i | 16 | ✅ |

**All widths match.** No implicit truncation. All addresses are 64-bit (NVMe physical address width).

### Q3. Are all errors propagated from sub-modules to a completion/error output? (DP5)

**Error paths:**

| Error | Detected By | Propagated Via | Reaches CQE? |
|-------|-------------|----------------|:---:|
| PRP Offset Invalid (list entry offset≠0) | prp_walker → error_o, error_status_o=0x13 | cmd_tracker → cpl_status_o | ✅ |
| PRP list chain broken (list entry=0 but bytes remain) | prp_walker → error_o | cmd_tracker → cpl_status_o | ✅ |
| AXI B response error (BRESP≠OKAY) | read_engine → handled internally | B response tracked per burst | ⚠️ NEEDS DESIGN |

**Gap identified:** The read_engine contract says `axi_b_resp_i` is an input, and `BREADY=1` always, but doesn't specify how B errors propagate to CQE. **Fix before RTL:** Add `b_error_o` output from read_engine to cmd_tracker. When BRESP≠OKAY for any B response in a command, `b_error_o` pulses. cmd_tracker captures it and sets `cpl_status_o` to Data Transfer Error.

### Q4. Is the completion signal style (pulse vs level) consistent across the integration chain?

**Signal type audit:**

| Signal | Module | Contract Type | Implementation Type |
|--------|--------|:---:|:---:|
| prp_start_o | cmd_tracker | Pulse (1 cycle) | FSM transition edge |
| prp_done_i | prp_walker | Pulse (1 cycle) | DONE state → IDLE transition |
| rd_start_o | cmd_tracker | Pulse (1 cycle) | Delayed from prp_done_i |
| rd_done_i | read_engine | Pulse (1 cycle) | All pages + all B done |
| cpl_valid_o | cmd_tracker | Level (held until cpl_ready_i) | Registered flag |
| page_valid_o | prp_walker | Pulse (1 cycle) | PAGE_TX state entry |
| page_done_o | read_engine | Pulse (1 cycle) | Page's last B response received |

**Consistency check:** All inter-module control signals use pulse or level consistently. 

- `cpl_valid_o` is the only LEVEL signal — correct for a valid/ready handshake to cq_post.
- `prp_done_i` and `rd_done_i` are PULSES — cmd_tracker latches them in its internal state.

**Risk identified:** If `prp_done_i` (pulse) and `rd_start_o` (pulse) occur in rapid succession, cmd_tracker might miss one. **Mitigation:** cmd_tracker FSM uses explicit handshake — deasserts prp_start_o only after prp_done_i is received, then asserts rd_start_o. States: ISSUE_PRP → wait prp_done → ISSUE_RD → wait rd_done.

### Q5. Does reset clear all valid-like outputs across all modules?

| Module | Outputs Cleared by Reset |
|--------|--------------------------|
| cmd_tracker | slot_valid_q=0, cpl_valid_q=0, wr_ptr=0, rd_ptr=0, processing_q=0 |
| prp_walker | state_q=IDLE, page_valid_o=0, list_ar_valid_o=0 |
| read_engine | aw_active_q=0, w_active_q=0, b_outstanding_q=0, page_active_q=0, done_q=0 |
| axi_adapter | ar_source_q=0, aw_source_q=0 (combinational mux — no valid registers) |

**Verdict:** ✅ All modules reset to safe state with no spurious valid assertions.

### Q6. Is the command demux routing unambiguous?

**Opcode routing:**
- OPC=02h (NVM Read) → cmd_tracker
- OPC=06h, 05h, 01h (Admin) → admin_exec (reused)
- All other OPC → Invalid Opcode → generate CQE with status=0x01 directly

**Backpressure interaction:** If cmd_tracker is full (`!cmd_ready_o`), sq_fetch backpressures (cmd_ready_i from sq_fetch = 0). This correctly propagates back to the SQ fetch engine, which stalls on `CMD_OUT` state.

**Verdict:** ✅ Routing unambiguous. Backpressure correctly propagates.

---

## Review Result

**P4 (Independence):** ⚠️ PASS WITH ONE ACTION
- **Action:** Document AW inter-page yield in read_engine (deassert AW/W between pages to allow CQ post interleaving)

**P6 (Boundaries):** ⚠️ PASS WITH TWO ACTIONS
- **Action 1:** Add `b_error_o` from read_engine to propagate AXI B response errors to CQE (DP5 gap)
- **Action 2:** Document NVM SRAM read latency contract (1 cycle, 64-bit aligned)

**All other checks PASS.** No fundamental architecture issues found. 3 actions to address before RTL.
