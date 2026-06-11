# AXI Channel Split Template

## Purpose

When a design needs to present a unified AXI4 master/slave interface but
the internal logic benefits from processing each AXI channel independently,
split the interface into five per-channel sub-modules. This is the
standard pattern derived from real-world FPGA projects where AW, W, B, AR,
and R channels have independent controllers, backpressure, and data paths.

## When to Use

- Multi-beat AXI4 bursts with independent channel flow control
- Designs where read and write paths have different pipeline depths
- Subsystems where different modules own different channels (e.g., a
  command decoder owns AW/AR, a data mover owns W, a response handler
  owns B/R)
- Whenever channel cross-coupling would complicate the FSM or
  verification

## Architecture

```
<name>_axi_top (wrapper)
├── <name>_axi_aw   (Write Address channel)
├── <name>_axi_w    (Write Data channel)
├── <name>_axi_b    (Write Response channel)
├── <name>_axi_ar   (Read Address channel)
└── <name>_axi_r    (Read Data channel)
```

The top-level wrapper is a pure structural module — it only instantiates
the five sub-modules and wires them to the unified AXI interface. No
logic, no FSM, no `always` blocks in the wrapper.

## Top-Level Wrapper Template

```verilog
module <name>_axi_top #(
    parameter AXI_DATA_WIDTH  = 512,
    parameter AXI_ADDR_WIDTH  = 36,
    parameter ID_WIDTH        = 4
)(
    input  wire                     clk_i,
    input  wire                     rst_i,

    // ---- AXI Write Address ----
    output wire                     m_axi_awvalid_o,
    output wire [ID_WIDTH-1:0]      m_axi_awid_o,
    input  wire                     m_axi_awready_i,
    output wire [7:0]               m_axi_awlen_o,
    output wire [2:0]               m_axi_awsize_o,
    output wire [1:0]               m_axi_awburst_o,
    output wire [AXI_ADDR_WIDTH-1:0] m_axi_awaddr_o,

    // ---- AXI Write Data ----
    output wire                     m_axi_wvalid_o,
    output wire [AXI_DATA_WIDTH-1:0] m_axi_wdata_o,
    output wire                     m_axi_wlast_o,
    input  wire                     m_axi_wready_i,
    output wire [AXI_DATA_WIDTH/8-1:0] m_axi_wstrb_o,

    // ---- AXI Write Response ----
    input  wire                     m_axi_bvalid_i,
    output wire                     m_axi_bready_o,
    input  wire [1:0]               m_axi_bresp_i,
    input  wire [ID_WIDTH-1:0]      m_axi_bid_i,

    // ---- AXI Read Address ----
    output wire [ID_WIDTH-1:0]      m_axi_arid_o,
    output wire                     m_axi_arvalid_o,
    output wire [1:0]               m_axi_arburst_o,
    output wire [2:0]               m_axi_arsize_o,
    output wire [7:0]               m_axi_arlen_o,
    input  wire                     m_axi_arready_i,
    output wire [AXI_ADDR_WIDTH-1:0] m_axi_araddr_o,

    // ---- AXI Read Data ----
    input  wire [ID_WIDTH-1:0]      m_axi_rid_i,
    input  wire                     m_axi_rvalid_i,
    output wire                     m_axi_rready_o,
    input  wire [1:0]               m_axi_rresp_i,
    input  wire [AXI_DATA_WIDTH-1:0] m_axi_rdata_i,
    input  wire                     m_axi_rlast_i,

    // ---- Internal command/data interfaces (project-specific) ----
    // These connect to your actual logic (DMA engine, buffer manager, etc.)
    // Define project-specific ports here
);

    // ---- Channel sub-module instantiations ----
    // Each sub-module owns exactly one AXI channel.
    // Cross-channel coordination happens through the project-specific
    // internal interfaces, not through the AXI channels directly.

    <name>_axi_aw #(
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .ID_WIDTH       (ID_WIDTH)
    ) inst_axi_aw (
        .clk_i              (clk_i),
        .rst_i              (rst_i),
        .m_axi_awvalid_o    (m_axi_awvalid_o),
        .m_axi_awid_o       (m_axi_awid_o),
        .m_axi_awready_i    (m_axi_awready_i),
        .m_axi_awlen_o      (m_axi_awlen_o),
        .m_axi_awsize_o     (m_axi_awsize_o),
        .m_axi_awburst_o    (m_axi_awburst_o),
        .m_axi_awaddr_o     (m_axi_awaddr_o),
        // ... project-specific internal ports
    );

    <name>_axi_w #(
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH)
    ) inst_axi_w (
        .clk_i              (clk_i),
        .rst_i              (rst_i),
        .m_axi_wvalid_o     (m_axi_wvalid_o),
        .m_axi_wdata_o      (m_axi_wdata_o),
        .m_axi_wlast_o      (m_axi_wlast_o),
        .m_axi_wready_i     (m_axi_wready_i),
        .m_axi_wstrb_o      (m_axi_wstrb_o),
        // ... project-specific internal ports
    );

    <name>_axi_b #(
        .ID_WIDTH (ID_WIDTH)
    ) inst_axi_b (
        .clk_i              (clk_i),
        .rst_i              (rst_i),
        .m_axi_bvalid_i     (m_axi_bvalid_i),
        .m_axi_bready_o     (m_axi_bready_o),
        .m_axi_bresp_i      (m_axi_bresp_i),
        .m_axi_bid_i        (m_axi_bid_i),
        // ... project-specific internal ports
    );

    <name>_axi_ar #(
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .ID_WIDTH       (ID_WIDTH)
    ) inst_axi_ar (
        .clk_i              (clk_i),
        .rst_i              (rst_i),
        .m_axi_arid_o       (m_axi_arid_o),
        .m_axi_arvalid_o    (m_axi_arvalid_o),
        .m_axi_arburst_o    (m_axi_arburst_o),
        .m_axi_arsize_o     (m_axi_arsize_o),
        .m_axi_arlen_o      (m_axi_arlen_o),
        .m_axi_arready_i    (m_axi_arready_i),
        .m_axi_araddr_o     (m_axi_araddr_o),
        // ... project-specific internal ports
    );

    <name>_axi_r #(
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .ID_WIDTH       (ID_WIDTH)
    ) inst_axi_r (
        .clk_i              (clk_i),
        .rst_i              (rst_i),
        .m_axi_rid_i        (m_axi_rid_i),
        .m_axi_rvalid_i     (m_axi_rvalid_i),
        .m_axi_rready_o     (m_axi_rready_o),
        .m_axi_rresp_i      (m_axi_rresp_i),
        .m_axi_rdata_i      (m_axi_rdata_i),
        .m_axi_rlast_i      (m_axi_rlast_i),
        // ... project-specific internal ports
    );

endmodule
```

## Per-Channel Sub-Module Guidelines

### AW (Write Address)

Owns: AWVALID, AWADDR, AWLEN, AWSIZE, AWBURST, AWID
Receives: AWREADY
Responsibility: accept write command from internal logic, present to AXI
interconnect, hold until AWREADY handshake. Must track outstanding write
commands if the design supports multiple in-flight.

### W (Write Data)

Owns: WVALID, WDATA, WSTRB, WLAST
Receives: WREADY
Responsibility: stream data beats from internal buffer/FIFO to AXI.
Beat counter advances only on `WVALID && WREADY`. WLAST must coincide
with the final accepted beat. See `axi-dma-channel-guidelines.md` for
continuous vs. elastic W mode policy.

### B (Write Response)

Receives: BVALID, BRESP, BID
Owns: BREADY
Responsibility: accept write responses, check BRESP for errors,
propagate completion status to internal logic. Must be ready to accept
responses to avoid stalling the AXI interconnect.

### AR (Read Address)

Owns: ARVALID, ARADDR, ARLEN, ARSIZE, ARBURST, ARID
Receives: ARREADY
Responsibility: symmetric to AW but for read commands. Must track
outstanding read commands to avoid exceeding the read data reorder
depth.

### R (Read Data)

Receives: RVALID, RDATA, RRESP, RLAST, RID
Owns: RREADY
Responsibility: accept read data beats, check RRESP for errors, pass
data to internal buffer/FIFO. RLAST signals end of burst.

## Verification Notes

Each per-channel sub-module can be verified independently:
- AW: drive AWREADY with backpressure patterns, check AWVALID hold
- W: drive WREADY with stalls, check WLAST coincidence, check beat count
- B: inject BRESP errors, check propagation
- AR: same pattern as AW
- R: inject RRESP errors, check RLAST, check data integrity

Integration test: connect all five sub-modules, run multi-beat reads and
writes, verify ordering rules and completion semantics.

## Relation to Other Skill References

- `axi-dma-channel-guidelines.md`: handshake rules, ordering, burst accounting
- `axi-full-guidelines.md`: full AXI4 protocol coverage
- `rtl-coding-standards.md`: naming conventions (N1-N4, N11)
