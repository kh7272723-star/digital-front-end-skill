# AXI Verification Methodology

## Purpose

AXI-specific verification patterns: BFM (Bus Functional Model) templates, DMA scoreboard methodology, and functional coverage models. These complement the generic verification guidance in `verification-guidance.md`.

## Sources

| ID | Source | Publisher |
|----|--------|-----------|
| PULP-AXI | `axi_test.sv` in `github.com/pulp-platform/axi` | ETH Zurich, Solderpad License |
| Forencich | `verilog-axi` + `cocotbext-axi` | Alex Forencich, MIT License |
| IHI0022E | AMBA AXI and ACE Protocol Specification | ARM |
| Spear | "SystemVerilog for Verification" | Chris Spear, Springer |
| UVM-Cookbook | UVM Verification Methodology | Mentor/Siemens |

---

## 1. AXI BFM (Bus Functional Model)

A BFM drives and monitors AXI transactions in simulation. Use these patterns for testbenches — they are not synthesizable.

### Master BFM tasks (Verilog-2001 compatible)

Derived from PULP Platform `axi_test.sv` driver structure. Parameterize `TA` (application delay, typically 0) and `TT` (test/sample delay, typically `#1`).

```verilog
// AXI Master BFM tasks
// Drive a write address beat with valid/ready handshake
task axi_master_send_aw;
    input [ID_W-1:0]   awid;
    input [ADDR_W-1:0] awaddr;
    input [7:0]        awlen;
    input [2:0]        awsize;
    begin
        m_axi_awid    = awid;
        m_axi_awaddr  = awaddr;
        m_axi_awlen   = awlen;
        m_axi_awsize  = awsize;
        m_axi_awvalid = 1'b1;
        @(posedge clk_i);
        while (!m_axi_awready_i) @(posedge clk_i);
        #TT;
        m_axi_awvalid = 1'b0;
    end
endtask

// Drive a single write data beat
task axi_master_send_w;
    input [DATA_W-1:0] wdata;
    input [STRB_W-1:0] wstrb;
    input              wlast;
    begin
        m_axi_wdata  = wdata;
        m_axi_wstrb  = wstrb;
        m_axi_wlast  = wlast;
        m_axi_wvalid = 1'b1;
        @(posedge clk_i);
        while (!m_axi_wready_i) @(posedge clk_i);
        #TT;
        m_axi_wvalid = 1'b0;
    end
endtask

// Wait for a write response
task axi_master_recv_b;
    output [ID_W-1:0] bid;
    output [1:0]      bresp;
    begin
        m_axi_bready = 1'b1;
        @(posedge clk_i);
        while (!m_axi_bvalid_i) @(posedge clk_i);
        bid   = m_axi_bid_i;
        bresp = m_axi_bresp_i;
        #TT;
        m_axi_bready = 1'b0;
    end
endtask

// Drive a read address beat
task axi_master_send_ar;
    input [ID_W-1:0]   arid;
    input [ADDR_W-1:0] araddr;
    input [7:0]        arlen;
    input [2:0]        arsize;
    begin
        m_axi_arid    = arid;
        m_axi_araddr  = araddr;
        m_axi_arlen   = arlen;
        m_axi_arsize  = arsize;
        m_axi_arvalid = 1'b1;
        @(posedge clk_i);
        while (!m_axi_arready_i) @(posedge clk_i);
        #TT;
        m_axi_arvalid = 1'b0;
    end
endtask

// Wait for a read data beat
task axi_master_recv_r;
    output [DATA_W-1:0] rdata;
    output [1:0]        rresp;
    output              rlast;
    begin
        m_axi_rready = 1'b1;
        @(posedge clk_i);
        while (!m_axi_rvalid_i) @(posedge clk_i);
        rdata = m_axi_rdata_i;
        rresp = m_axi_rresp_i;
        rlast = m_axi_rlast_i;
        #TT;
        // rready stays high for continuous reads; deassert in test if needed
    end
endtask
```

### Slave BFM tasks (simple responder)

```verilog
// AXI Slave BFM: accept write address, collect write data, send response
task axi_slave_respond_write;
    input [1:0] bresp_val;  // 2'b00=OKAY, 2'b10=SLVERR, 2'b11=DECERR
    reg [7:0] beat_cnt;
    begin
        // Accept AW
        s_axi_awready = 1'b1;
        @(posedge clk_i);
        while (!s_axi_awvalid_i) @(posedge clk_i);
        #TT;
        s_axi_awready = 1'b0;

        // Accept all W beats
        beat_cnt = 0;
        s_axi_wready = 1'b1;
        forever begin
            @(posedge clk_i);
            if (s_axi_wvalid_i) begin
                beat_cnt = beat_cnt + 1;
                if (s_axi_wlast_i) begin
                    #TT;
                    s_axi_wready = 1'b0;
                    disable axi_slave_respond_write;
                end
            end
        end

        // Send B response (after configurable delay)
        repeat (B_RESP_DELAY) @(posedge clk_i);
        s_axi_bid    = {ID_W{1'b0}};
        s_axi_bresp  = bresp_val;
        s_axi_bvalid = 1'b1;
        @(posedge clk_i);
        while (!s_axi_bready_i) @(posedge clk_i);
        #TT;
        s_axi_bvalid = 1'b0;
    end
endtask
```

### High-level burst task (wraps individual beats)

```verilog
// Send a complete write burst: AW + N W beats + wait for B
task axi_master_write_burst;
    input [ADDR_W-1:0] addr;
    input [7:0]        len;     // AXI len = beats - 1
    input [DATA_W-1:0] data[];  // array of beat data
    input [STRB_W-1:0] strb[];  // array of per-beat strobes
    reg [1:0] bresp;
    reg [ID_W-1:0] bid;
    integer i;
    begin
        fork
            axi_master_send_aw({ID_W{1'b0}}, addr, len, $clog2(DATA_W/8));
            begin
                for (i = 0; i <= len; i = i + 1) begin
                    axi_master_send_w(data[i], strb[i], (i == len));
                end
            end
        join
        axi_master_recv_b(bid, bresp);
        if (bresp != 2'b00)
            $display("ERROR: B response = %0d at time %0t", bresp, $time);
    end
endtask

// Send a complete read burst: AR + collect N R beats
task axi_master_read_burst;
    input  [ADDR_W-1:0] addr;
    input  [7:0]        len;
    output [DATA_W-1:0] data[];
    reg [1:0] rresp;
    reg       rlast;
    integer i;
    begin
        axi_master_send_ar({ID_W{1'b0}}, addr, len, $clog2(DATA_W/8));
        for (i = 0; i <= len; i = i + 1) begin
            axi_master_recv_r(data[i], rresp, rlast);
            if (rresp != 2'b00)
                $display("ERROR: R response = %0d at beat %0d at time %0t", rresp, i, $time);
        end
        if (!rlast)
            $display("ERROR: Expected RLAST on beat %0d", len);
    end
endtask
```

### 4KB boundary check (PULP pattern)

AXI spec IHI0022E A4.3: bursts must not cross a 4KB boundary. Include this check in any testbench that generates bursts:

```verilog
task check_4kb_boundary;
    input [ADDR_W-1:0] addr;
    input [7:0]        len;
    input [2:0]        size;
    reg [ADDR_W-1:0] end_addr;
    begin
        end_addr = addr + ((len + 1) << size) - 1;
        if (addr[11:0] + ((len + 1) << size) - 1 > 12'hFFF) begin
            $display("ERROR: Burst crosses 4KB boundary: addr=%h len=%0d size=%0d",
                     addr, len, size);
            $finish;
        end
    end
endtask
```

---

## 2. DMA Scoreboard

### Architecture (derived from PULP `axi_scoreboard`)

```
┌──────────────────────────────────────────┐
│           Golden Memory Model            │
│  byte_mem [addr] = queue of byte values  │
└──────────┬───────────────────┬───────────┘
           │                   │
    ┌──────▼──────┐    ┌───────▼──────┐
    │ Write Monitor│    │ Read Monitor │
    │ (AW+W+B)    │    │ (AR+R)       │
    └──────┬──────┘    └───────┬──────┘
           │                   │
    ┌──────▼──────┐    ┌───────▼──────┐
    │ Apply WSTRB │    │ Compare R    │
    │ to golden   │    │ data vs      │
    │ memory      │    │ golden       │
    └─────────────┘    └──────────────┘
```

### Scoreboard logic (Verilog-2001 procedural)

For simpler testbenches that cannot use SystemVerilog classes, use a procedural scoreboard:

```verilog
// DMA Scoreboard: tracks data integrity across read→write path
// Monitors read data from source, write data to destination, compares

reg [7:0] golden_mem [0:MEM_SIZE-1];  // byte-addressed golden memory
integer   rd_desc_issued;
integer   rd_desc_completed;
integer   wr_desc_issued;
integer   wr_desc_completed;
integer   data_mismatch_cnt;

// Capture read data into golden memory (source side)
always @(posedge clk_i) begin
    if (m_axi_rvalid_i && m_axi_rready_o) begin
        // Store each byte of read data at the beat address
        for (integer b = 0; b < BUS_BYTES; b = b + 1) begin
            golden_mem[rd_beat_addr + b] = m_axi_rdata_i[b*8 +: 8];
        end
        if (m_axi_rlast_i)
            rd_desc_completed = rd_desc_completed + 1;
    end
end

// Check write data against golden memory (destination side)
always @(posedge clk_i) begin
    if (m_axi_wvalid_o && m_axi_wready_i) begin
        for (integer b = 0; b < BUS_BYTES; b = b + 1) begin
            if (m_axi_wstrb_o[b]) begin
                if (golden_mem[wr_beat_addr + b] !== 8'hxx &&
                    golden_mem[wr_beat_addr + b] !== m_axi_wdata_o[b*8 +: 8]) begin
                    $display("SCOREBOARD MISMATCH: addr=%h expected=%h actual=%h at %0t",
                             wr_beat_addr + b,
                             golden_mem[wr_beat_addr + b],
                             m_axi_wdata_o[b*8 +: 8], $time);
                    data_mismatch_cnt = data_mismatch_cnt + 1;
                end
            end
        end
        if (m_axi_wlast_o)
            wr_desc_completed = wr_desc_completed + 1;
    end
end

// Transaction count check
always @(posedge clk_i) begin
    if (test_done) begin
        if (rd_desc_issued != rd_desc_completed)
            $display("SCOREBOARD: Read descriptors: issued=%0d completed=%0d",
                     rd_desc_issued, rd_desc_completed);
        if (wr_desc_issued != wr_desc_completed)
            $display("SCOREBOARD: Write descriptors: issued=%0d completed=%0d",
                     wr_desc_issued, wr_desc_completed);
        if (data_mismatch_cnt == 0 &&
            rd_desc_issued == rd_desc_completed &&
            wr_desc_issued == wr_desc_completed)
            $display("SCOREBOARD: PASS — all data matches, all descriptors complete");
        else
            $display("SCOREBOARD: FAIL — %0d mismatches", data_mismatch_cnt);
    end
end
```

### DMA verification checklist

For any DMA design, the testbench must verify:

| Check | Method | Pass criterion |
|-------|--------|----------------|
| Data integrity | Scoreboard byte compare | Zero mismatches |
| Transaction count | issued == completed (both RD and WR) | Counts match |
| Completion ordering | done_o pulses in descriptor accept order | Order preserved |
| Error capture | Inject SLVERR/DECERR, check error_o | Error reported on done_o |
| Zero-length transfer | data_len=0 | done_o pulse, no AXI traffic |
| Unaligned address | addr not aligned to bus width | WSTRB masks correct bytes |
| 4KB boundary | Burst at boundary edge | Split into correct sub-bursts |
| Outstanding saturation | MAX_OUTSTANDING+1 commands | No deadlock, all complete |
| Backpressure | Stall AWREADY/WREADY/BREADY/ARREADY/RREADY | No data loss, no deadlock |

---

## 3. AXI Functional Coverage

### Essential coverage points (derived from IHI0022E)

```systemverilog
covergroup axi_write_cg @(posedge clk_i);
    // Burst length
    cp_len: coverpoint awlen {
        bins single    = {0};
        bins short     = {[1:15]};
        bins medium    = {[16:127]};
        bins long_128  = {127};
        bins max_256   = {255};
    }

    // Transfer size
    cp_size: coverpoint awsize {
        bins byte1  = {0};
        bins byte2  = {1};
        bins byte4  = {2};
        bins byte8  = {3};
        bins byte16 = {4};
        bins byte32 = {5};
        bins byte64 = {6};
    }

    // Address alignment (first beat)
    cp_align: coverpoint awaddr[2:0] {
        bins aligned   = {0};
        bins unaligned = {[1:7]};
    }

    // 4KB boundary crossing attempt (should be split by burst planner)
    cp_4kb_cross: coverpoint crosses_4kb {
        bins no  = {0};
        bins yes = {1};  // assertion should prevent this
    }

    // B response codes
    cp_bresp: coverpoint bresp {
        bins okay   = {2'b00};
        bins exokay = {2'b01};
        bins slverr = {2'b10};
        bins decerr = {2'b11};
    }

    // Outstanding depth
    cp_outstanding: coverpoint b_outstanding {
        bins depth1     = {1};
        bins depth2_4   = {[2:4]};
        bins depth5_16  = {[5:16]};
    }

    // WVALID behavior (P12): normative per-beat hold plus local mode coverage.
    cp_wvalid_wait_violation: coverpoint wvalid_or_payload_changed_while_waiting {
        bins none = {0};  // required
        bins seen = {1};  // AXI violation
    }

    cp_wdata_mode: coverpoint wdata_mode {
        bins continuous = {0};  // local policy: no WVALID gaps before WLAST
        bins elastic    = {1};  // local policy: legal bubbles between accepted beats
    }

    cp_elastic_gap: coverpoint wvalid_gap_between_accepted_beats {
        bins no_gap = {0};
        bins gap    = {1};  // legal only in elastic mode
    }

    // Key crosses
    cx_len_size:    cross cp_len, cp_size;
    cx_align_size:  cross cp_align, cp_size;
    cx_resp_len:    cross cp_bresp, cp_len;
endgroup

covergroup axi_read_cg @(posedge clk_i);
    cp_len: coverpoint arlen {
        bins single = {0};
        bins short  = {[1:15]};
        bins medium = {[16:127]};
        bins max_256 = {255};
    }

    cp_rresp: coverpoint rresp {
        bins okay   = {2'b00};
        bins slverr = {2'b10};
        bins decerr = {2'b11};
    }

    cp_outstanding: coverpoint ar_outstanding {
        bins depth1     = {1};
        bins depth2_4   = {[2:4]};
        bins depth5_16  = {[5:16]};
    }
endgroup
```

### Coverage collection strategy

1. **During directed tests**: Instantiate covergroups, run all directed tests, review coverage report. Identify uncovered bins.
2. **For uncovered bins**: Write targeted directed tests. E.g., if `cp_len.max_256` is uncovered, add a test with len=255.
3. **For cross coverage**: Use constrained random or enumerate key combinations manually.
4. **Coverage closure criterion**: All bins hit, all crosses have at least one hit per relevant combination.

### Coverage-driven test plan template

| Test ID | Scenario | Coverage targets |
|---------|----------|-----------------|
| T01 | Single beat, aligned | cp_len.single, cp_align.aligned |
| T02 | Max burst (256 beats) | cp_len.max_256 |
| T03 | Unaligned address | cp_align.unaligned |
| T04 | 4KB boundary split | cx_len_size + boundary check |
| T05 | Error injection (SLVERR) | cp_bresp.slverr |
| T06 | Backpressure all channels | cp_outstanding.depth1 + stall |
| T07 | Maximum outstanding | cp_outstanding.depth5_16 |
| T08 | Zero-length transfer | completion without AXI traffic |
| T09 | Narrow transfer (size < bus) | cp_size.byte1 with full bus |
| T10 | W beat stability while stalled | cp_wvalid_wait_violation.none |
| T11 | W data mode coverage | cp_wdata_mode.continuous + cp_wdata_mode.elastic; cp_elastic_gap.gap only in elastic mode |

---

## How to apply

1. **For any AXI module testbench:** Use the BFM tasks (section 1) to drive/monitor transactions. Start with `axi_master_write_burst` and `axi_master_read_burst` for basic functionality.

2. **For DMA designs:** Add the scoreboard (section 2) to verify data integrity, but do not stop there. Also check expected AW/AR transaction count, address sequence, burst lengths, WSTRB masks, WLAST/RLAST positions, B/R response error propagation, completion-after-response ordering, and independent backpressure on all AXI channels. Captured data matching by itself can false-pass a broken DMA.

3. **For coverage closure:** Instantiate the covergroups (section 3), run directed tests, then fill uncovered bins with targeted tests. Use the coverage-driven test plan template.

4. **For formal verification:** Use the SVA properties from `formal-properties.md` with `bind` statements to attach them to the DUT without modifying RTL.
