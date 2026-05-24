# DMA / CDMA Examples

## Purpose

Use these patterns for any DMA, memory mover, or CDMA design. They show how to decompose a DMA engine into independently operating AXI channel modules, each with its own FSM, command queue, and flow control.

## Architecture principle: per-channel decomposition

A DMA engine should decompose along AXI channel boundaries, not along functional boundaries (read-engine / write-engine). Each AXI channel gets its own module with its own FSM:

```
dma_top
├── cmd_queue           ← command buffering
├── ar_channel          ← AR channel: cmd FIFO + addr FSM
├── aw_channel          ← AW channel: cmd FIFO + addr FSM (same module, different instance)
├── rd_data_channel     ← R channel → data FIFO
├── wr_data_channel     ← data FIFO → W channel
├── bresp_channel       ← B channel: cmd FIFO + response FSM
└── completion_tracker  ← ordered done/error output
```

Reference: Xilinx CDMA (PG034) uses "separate AXI4 master interfaces for read and write operations" with "an internal data buffer/FIFO sits between the read and write channels, decoupling the two sides."

## Pattern 1: Shared channel FSM template

Both AR and AW channels use the same FSM structure. The FSM reads a command from its local FIFO, calculates burst parameters, and issues AXI transactions.

```verilog
// cdma_channel_fsm — shared by AR and AW address channels
// States: IDLE → LOAD → SEND_BLOCK → SEND_REMAIN
module cdma_channel_fsm(
    input  clk_i,
    input  rst_i,
    input  cmd_fifo_empty_i,
    input  block_present_i,    // full bursts remain
    input  remain_present_i,   // partial burst remains
    input  ready_i,            // AXI ARREADY or AWREADY
    output reg cmd_fifo_rd_en_o,
    output reg load_block_o,
    output reg load_remain_o,
    output reg send_next_o,
    output reg load_addr_o,
    output reg valid_o
);
    localparam S_IDLE        = 4'b0001;
    localparam S_LOAD        = 4'b0010;
    localparam S_SEND_BLOCK  = 4'b0100;
    localparam S_SEND_REMAIN = 4'b1000;
    reg [3:0] cstate, nstate;

    // Process 1: state register
    always @(posedge clk_i) begin
        if (rst_i) cstate <= S_IDLE;
        else       cstate <= nstate;
    end

    // Process 2: next-state + outputs with defaults
    always @(*) begin
        cmd_fifo_rd_en_o = 1'b0;
        load_block_o     = 1'b0;
        load_remain_o    = 1'b0;
        send_next_o      = 1'b0;
        valid_o          = 1'b0;
        load_addr_o      = 1'b0;
        nstate           = S_IDLE;
        case (cstate)
            S_IDLE: begin
                if (!cmd_fifo_empty_i) begin
                    cmd_fifo_rd_en_o = 1'b1;
                    nstate = S_LOAD;
                end
            end
            S_LOAD: begin
                load_addr_o = 1'b1;
                if (block_present_i) begin
                    load_block_o = 1'b1;
                    nstate = S_SEND_BLOCK;
                end else if (remain_present_i) begin
                    load_remain_o = 1'b1;
                    nstate = S_SEND_REMAIN;
                end
            end
            S_SEND_BLOCK: begin
                valid_o = 1'b1;
                if (ready_i) send_next_o = 1'b1;
                if (!block_present_i && remain_present_i) begin
                    load_remain_o = 1'b1;
                    nstate = S_SEND_REMAIN;
                end else if (!block_present_i) begin
                    nstate = S_IDLE;
                end else begin
                    nstate = S_SEND_BLOCK;
                end
            end
            S_SEND_REMAIN: begin
                valid_o = 1'b1;
                if (ready_i) nstate = S_IDLE;
                else         nstate = S_SEND_REMAIN;
            end
            default: nstate = S_IDLE;
        endcase
    end
endmodule
```

Key properties:
- Two-process FSM style (mandatory for multi-stage control)
- All outputs have defaults (no latches)
- `send_next_o` enables burst address increment (outstanding support)
- `block_present_i` / `remain_present_i` separate full bursts from partial

## Pattern 2: Address channel with local command FIFO

Each address channel (AR or AW) has its own command FIFO, allowing independent flow control:

```verilog
module addr_channel #(
    parameter ADDR_WIDTH = 32,
    parameter BURST_SIZE = 128
)(
    input  wire                  clk_i,
    input  wire                  rst_i,
    // Command FIFO input
    input  wire [71:0]           fifo_din_i,    // {addr, len}
    input  wire                  fifo_wr_en_i,
    output wire                  fifo_full_o,
    // AXI address channel
    output wire [ADDR_WIDTH-1:0] m_axi_araddr_o,
    output reg  [7:0]            m_axi_arlen_o,
    output wire                  m_axi_arvalid_o,
    input  wire                  m_axi_arready_i
);
    localparam LP_BLOCK = $clog2(BURST_SIZE);

    wire        cmd_fifo_rd_en;
    wire [71:0] cmd_fifo_dout;
    wire        cmd_fifo_empty;
    reg  [39:0] cmd_addr;
    reg  [ADDR_WIDTH-LP_BLOCK-1:0] axi_addr;
    reg  [31-LP_BLOCK:0] block_num;
    reg  [LP_BLOCK-7:0]  remain_len;

    wire load_block, load_remain, send_next, block_present, remain_present, load_addr;

    assign m_axi_araddr_o = {axi_addr, {LP_BLOCK{1'b0}}};
    assign block_present  = (block_num != 0);
    assign remain_present = (remain_len != 0);

    // Address register
    always @(posedge clk_i) begin
        if (cmd_fifo_rd_en) cmd_addr <= cmd_fifo_dout[71:32];
    end

    // Block counter (full bursts remaining)
    always @(posedge clk_i) begin
        if (cmd_fifo_rd_en)      block_num <= cmd_fifo_dout[31:LP_BLOCK];
        else if (send_next)      block_num <= block_num - 1'b1;
    end

    // Remain register (partial burst length)
    always @(posedge clk_i) begin
        if (cmd_fifo_rd_en) remain_len <= cmd_fifo_dout[LP_BLOCK-1:6];
    end

    // Address increment
    always @(posedge clk_i) begin
        if (load_addr)      axi_addr <= cmd_addr[ADDR_WIDTH-1:LP_BLOCK];
        else if (send_next) axi_addr <= axi_addr + 1'b1;
    end

    // ARLEN register
    always @(posedge clk_i) begin
        if (load_block)      m_axi_arlen_o <= BURST_SIZE/(DATA_WIDTH/8) - 1;
        else if (load_remain) m_axi_arlen_o <= remain_len - 1'b1;
    end

    // Local command FIFO (async: cmd_clk_i → clk_i)
    // dist_fifo_72bx32_fwft inst_cmd_fifo (...);

    // Shared FSM
    cdma_channel_fsm inst_fsm (
        .clk_i(clk_i), .rst_i(rst_i),
        .cmd_fifo_empty_i(cmd_fifo_empty),
        .block_present_i(block_present),
        .remain_present_i(remain_present),
        .ready_i(m_axi_arready_i),
        .cmd_fifo_rd_en_o(cmd_fifo_rd_en),
        .load_block_o(load_block),
        .load_remain_o(load_remain),
        .load_addr_o(load_addr),
        .send_next_o(send_next),
        .valid_o(m_axi_arvalid_o)
    );
endmodule
```

Key properties:
- Local command FIFO decouples command input from AXI timing
- Block/remain decomposition handles non-aligned lengths
- Address auto-increments per burst (`send_next`)
- Same module instantiated twice: once for AR, once for AW

## Pattern 3: Read data channel (R → FIFO)

The read data channel is a simple passthrough from AXI R to the data FIFO:

```verilog
module rd_data_channel #(
    parameter DATA_WIDTH = 512
)(
    input  wire                  clk_i,
    input  wire                  rst_i,
    // Data FIFO read interface
    input  wire                  data_fifo_rd_en_i,
    output wire                  data_fifo_empty_o,
    output wire [DATA_WIDTH:0]   data_fifo_dout_o,  // {rlast, rdata}
    // Error
    output reg  [1:0]            rresp_err_o,
    // AXI R channel
    input  wire [DATA_WIDTH-1:0] m_axi_rdata_i,
    input  wire [1:0]            m_axi_rresp_i,
    input  wire                  m_axi_rlast_i,
    input  wire                  m_axi_rvalid_i,
    output wire                  m_axi_rready_o
);
    wire data_fifo_full;

    assign m_axi_rready_o = ~data_fifo_full;

    // Error capture: first non-OKAY response
    always @(posedge clk_i) begin
        if (rst_i)
            rresp_err_o <= 2'b00;
        else if (m_axi_rvalid_i & m_axi_rready_o & (m_axi_rresp_i != 2'b00))
            rresp_err_o <= m_axi_rresp_i;
    end

    // Data FIFO: carries {rlast, rdata} — WLAST is derived from RLAST
    // fifo_513bx512_fwft inst_rd_data_fifo (
    //     .din({m_axi_rlast_i, m_axi_rdata_i}),
    //     .wr_en(m_axi_rvalid_i & m_axi_rready_o),
    //     .rd_en(data_fifo_rd_en_i),
    //     .dout(data_fifo_dout_o),
    //     .full(data_fifo_full),
    //     .empty(data_fifo_empty_o)
    // );
endmodule
```

Key properties:
- RREADY = ~FIFO_FULL — backpressure through FIFO
- RLAST stored alongside RDATA — WLAST derived from FIFO output
- Error captured on first non-OKAY response
- No FSM needed — pure datapath

## Pattern 4: Write data channel (FIFO → W)

The write data channel reads from the data FIFO and drives the AXI W channel:

```verilog
module wr_data_channel #(
    parameter DATA_WIDTH = 512
)(
    input  wire                  clk_i,
    input  wire                  rst_i,
    // Data FIFO
    output wire                  data_fifo_rd_en_o,
    input  wire                  data_fifo_empty_i,
    input  wire [DATA_WIDTH:0]   data_fifo_dout_i,  // {wlast, wdata}
    // AXI W channel
    output wire [DATA_WIDTH-1:0] m_axi_wdata_o,
    output wire                  m_axi_wlast_o,
    output wire                  m_axi_wvalid_o,
    input  wire                  m_axi_wready_i
);
    assign m_axi_wdata_o = data_fifo_dout_i[DATA_WIDTH-1:0];
    assign m_axi_wlast_o = data_fifo_dout_i[DATA_WIDTH];

    // W channel FSM: IDLE → SEND
    wr_data_channel_fsm inst_fsm (
        .clk_i(clk_i), .rst_i(rst_i),
        .data_fifo_rd_en_o(data_fifo_rd_en_o),
        .data_fifo_empty_i(data_fifo_empty_i),
        .axi_wvalid_o(m_axi_wvalid_o),
        .axi_wready_i(m_axi_wready_i)
    );
endmodule

module wr_data_channel_fsm(
    input  clk_i, rst_i,
    output reg data_fifo_rd_en_o,
    input      data_fifo_empty_i,
    output reg axi_wvalid_o,
    input      axi_wready_i
);
    localparam S_IDLE = 2'b01;
    localparam S_SEND = 2'b10;
    reg [1:0] cstate, nstate;

    always @(posedge clk_i) begin
        if (rst_i) cstate <= S_IDLE;
        else       cstate <= nstate;
    end

    always @(*) begin
        data_fifo_rd_en_o = 1'b0;
        axi_wvalid_o      = 1'b0;
        nstate            = S_IDLE;
        case (cstate)
            S_IDLE: begin
                if (!data_fifo_empty_i) begin
                    data_fifo_rd_en_o = 1'b1;
                    nstate = S_SEND;
                end
            end
            S_SEND: begin
                axi_wvalid_o = 1'b1;
                if (axi_wready_i) begin
                    if (!data_fifo_empty_i) begin
                        data_fifo_rd_en_o = 1'b1;
                        nstate = S_SEND;
                    end else begin
                        nstate = S_IDLE;
                    end
                end else begin
                    nstate = S_SEND;
                end
            end
            default: nstate = S_IDLE;
        endcase
    end
endmodule
```

Key properties:
- WLAST comes from FIFO (carried from RLAST) — no separate tracking
- WVALID = FIFO not empty — data-driven, not command-driven
- Simple 2-state FSM — only needs to handle FIFO-to-W transfer
- No dependency on AW channel timing

## Pattern 5: B response channel with completion tracking

The B response channel has its own command FIFO to track expected responses:

```verilog
module bresp_channel #(
    parameter ADDR_WIDTH = 32,
    parameter BURST_SIZE = 128
)(
    input  wire       clk_i,
    input  wire       rst_i,
    // Command FIFO (tracks expected B responses per DMA command)
    input  wire [31:0] fifo_din_i,
    input  wire        fifo_wr_en_i,
    output wire        fifo_full_o,
    // AXI B channel
    input  wire [1:0]  m_axi_bresp_i,
    input  wire        m_axi_bvalid_i,
    output wire        m_axi_bready_o,
    // Completion
    output wire        cmd_done_o,
    output reg  [1:0]  bresp_err_o
);
    localparam LP_BLOCK = $clog2(BURST_SIZE);

    wire cmd_fifo_rd_en;
    wire [31:0] cmd_fifo_dout;
    wire cmd_fifo_empty;
    wire block_present, remain_present;
    reg [31-LP_BLOCK:0] block_num;
    reg [LP_BLOCK-7:0]  remain_len;
    wire cmd_done;

    assign block_present  = (block_num != 0);
    assign remain_present = (remain_len != 0);

    // Block counter: decrements on each B response
    always @(posedge clk_i) begin
        if (cmd_fifo_rd_en)      block_num <= cmd_fifo_dout[31:LP_BLOCK];
        else if (m_axi_bvalid_i & m_axi_bready_o) block_num <= block_num - 1'b1;
    end

    // Remain register
    always @(posedge clk_i) begin
        if (cmd_fifo_rd_en) remain_len <= cmd_fifo_dout[LP_BLOCK-1:6];
    end

    // Error capture
    always @(posedge clk_i) begin
        if (rst_i) bresp_err_o <= 2'b00;
        else if (m_axi_bvalid_i & m_axi_bready_o & (m_axi_bresp_i != 2'b00))
            bresp_err_o <= m_axi_bresp_i;
    end

    // Done edge detection (cmd_done is in AXI clock domain)
    reg cmd_done_r0, cmd_done_r1, cmd_done_r2;
    always @(posedge clk_i) begin
        if (rst_i) begin
            cmd_done_r0 <= 1'b0; cmd_done_r1 <= 1'b0; cmd_done_r2 <= 1'b0;
        end else begin
            cmd_done_r0 <= cmd_done;
            cmd_done_r1 <= cmd_done_r0;
            cmd_done_r2 <= cmd_done_r1;
        end
    end
    assign cmd_done_o = cmd_done_r1 & ~cmd_done_r2;  // rising edge

    // B response FSM
    bresp_channel_fsm inst_fsm (
        .clk_i(clk_i), .rst_i(rst_i),
        .cmd_fifo_empty_i(cmd_fifo_empty),
        .block_present_i(block_present),
        .remain_present_i(remain_present),
        .valid_i(m_axi_bvalid_i),
        .cmd_fifo_rd_en_o(cmd_fifo_rd_en),
        .ready_o(m_axi_bready_o),
        .cmd_done_o(cmd_done)
    );
endmodule
```

Key properties:
- B channel has its own command FIFO — completely independent from AW/W
- Block counter tracks expected B responses per DMA command
- Completion when all B responses received (block_num == 0 && remain == 0)
- Done is edge-detected for clean single-cycle pulse

## Pattern 6: Top-level integration (fully decoupled)

```verilog
module dma_top #(...)(
    // ... AXI ports ...
    input  wire cmd_fifo_wr_en_i,
    output wire cmd_fifo_full_o,
    output wire cmd_done_o,
    output wire [1:0] rresp_err_o,
    output wire [1:0] bresp_err_o
);
    wire ar_full, aw_full, b_full;
    assign cmd_fifo_full_o = ar_full | aw_full | b_full;

    // AR channel: independent command FIFO + FSM
    addr_channel #(...) inst_ar_channel (
        .fifo_din_i({src_addr, data_len}),
        .fifo_wr_en_i(cmd_fifo_wr_en_i),
        .fifo_full_o(ar_full),
        .m_axi_araddr_o(m_axi_araddr),
        .m_axi_arlen_o(m_axi_arlen),
        .m_axi_arvalid_o(m_axi_arvalid),
        .m_axi_arready_i(m_axi_arready)
    );

    // AW channel: same module, different instance
    addr_channel #(...) inst_aw_channel (
        .fifo_din_i({dst_addr, data_len}),
        .fifo_wr_en_i(cmd_fifo_wr_en_i),
        .fifo_full_o(aw_full),
        .m_axi_araddr_o(m_axi_awaddr),  // reused port names
        .m_axi_arlen_o(m_axi_awlen),
        .m_axi_arvalid_o(m_axi_awvalid),
        .m_axi_arready_i(m_axi_awready)
    );

    // R channel → data FIFO
    rd_data_channel #(...) inst_rd_data (...);

    // data FIFO → W channel
    wr_data_channel #(...) inst_wr_data (...);

    // B channel: independent tracking
    bresp_channel #(...) inst_bresp (
        .fifo_din_i(data_len),
        .fifo_wr_en_i(cmd_fifo_wr_en_i),
        .fifo_full_o(b_full),
        .cmd_done_o(cmd_done_o),
        .bresp_err_o(bresp_err_o)
    );
endmodule
```

Key properties:
- Read and write paths are fully decoupled (no shared burst_ready)
- Each channel has its own command FIFO
- cmd_fifo_full_o = OR of all three FIFO fulls (backpressure)
- Data FIFO naturally decouples R and W timing

## Anti-pattern: coupled read/write engine

**DO NOT USE:**
```verilog
// Shared burst planner with coupled ready
assign burst_ready = burst_ready_rd & burst_ready_wr;
// Single FSM managing AW+W+B
// Completion tracker with three independent pointers
```

This couples read and write at the command level, blocking the fast side when the slow side stalls.

## Completion model

The reference design uses a per-command B response counter:
- Each DMA command gets a FIFO entry with expected B count
- B responses decrement the counter
- Done pulses when counter reaches zero
- Simple, ordered, no multi-pointer synchronization

Compare with: tracking burst_count per completion queue entry (cdma_completion in skill trials). Both work; the FIFO-based approach is simpler for single-ID designs.

## Module/FSM encapsulation pattern

The reference design separates each AXI channel into two layers:

1. **Channel module** (datapath): registers, counters, FIFO connections, AXI output assignments
2. **FSM submodule** (control): state transitions, output enables, handshake logic

```
addr_channel (datapath)
├── cmd FIFO
├── address register
├── block counter
├── remain register
└── cdma_channel_fsm (control)
    ├── state register
    ├── next-state logic
    └── output enables (cmd_fifo_rd_en, load_block, send_next, valid)
```

Why this matters:
- **FSM reuse**: the same `cdma_channel_fsm` module is instantiated for both AR and AW channels
- **Testability**: FSM can be verified independently with simple stimulus
- **Readability**: datapath registers and control logic are visually separated
- **Maintainability**: changing burst calculation doesn't touch FSM; changing FSM doesn't touch datapath

This is a specific instance of the general "two-process FSM" rule, but applied at the module boundary level: the FSM is a separate module, not just a separate always block.

## Sources

- Xilinx CDMA (PG034): separate read/write master interfaces, internal FIFO decoupling
- ARM PL330 (DDI 0441): independent RD/WD half-channels, concurrent operation
- Linux DMAengine: per-channel descriptor queues, direction per-channel
