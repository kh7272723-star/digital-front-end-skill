`default_nettype none

// Async FIFO with gray-coded pointers for CDC crossing.
//
// Write domain: wr_clk_i, wr_rst_i
// Read domain:  rd_clk_i, rd_rst_i
//
// DEPTH: number of entries (must be power of 2)
// DATA_WIDTH: width of data path
//
// FWFT (First-Word-Fall-Through): data appears on rdata_o combinationally
// when the FIFO is non-empty. rd_en_i advances to the next entry.
//
// Synchronization:
//   - Write pointer (gray) -> 2FF synchronizer -> read domain (for empty)
//   - Read pointer (gray)  -> 2FF synchronizer -> write domain (for full)
//   - Each synchronizer uses the destination domain's clock and reset.
//
// Full detection: compare wr_gray_next (next write gray code) against
//   synchronized rd_gray with MSB inverted. Full means write would
//   exceed capacity.
//
// Empty detection: compare rd_gray (current read gray code) against
//   synchronized wr_gray. Empty means no data available.
//
// Reference: Clifford Cummings, "Simulation and Synthesis Techniques
// for Asynchronous FIFO Design", SNUG 2002.

module async_fifo #(
    parameter DATA_WIDTH = 192,
    parameter DEPTH      = 8
) (
    // Write domain
    input  wire                  wr_clk_i,
    input  wire                  wr_rst_i,
    input  wire                  wr_en_i,
    input  wire [DATA_WIDTH-1:0] wdata_i,
    output wire                  full_o,
    // Read domain
    input  wire                  rd_clk_i,
    input  wire                  rd_rst_i,
    input  wire                  rd_en_i,
    output wire [DATA_WIDTH-1:0] rdata_o,
    output wire                  empty_o
);

    // Parameter validation
    // synthesis translate_off
    initial begin
        if (DEPTH < 2 || (DEPTH & (DEPTH - 1)) != 0)
            $error("async_fifo: DEPTH must be >= 2 and power of 2, got %0d", DEPTH);
    end
    // synthesis translate_on

    localparam ADDR_W = $clog2(DEPTH);       // addressing bits
    localparam PTR_W  = ADDR_W + 1;          // pointer bits (+1 for wrap detection)

    // -----------------------------------------------------------
    // Memory (register-based for small depths)
    // -----------------------------------------------------------
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // -----------------------------------------------------------
    // Write pointer (wr_clk domain)
    // -----------------------------------------------------------
    reg  [PTR_W-1:0] wr_ptr_q;
    wire [PTR_W-1:0] wr_ptr_next;
    wire             wr_do;

    assign wr_do   = wr_en_i && !full_o;
    assign wr_ptr_next = wr_ptr_q + (PTR_W'(wr_do));

    always @(posedge wr_clk_i) begin
        if (wr_rst_i) begin
            wr_ptr_q <= {PTR_W{1'b0}};
        end else begin
            wr_ptr_q <= wr_ptr_next;
        end
    end

    // Memory write
    always @(posedge wr_clk_i) begin
        if (wr_do) begin
            mem[wr_ptr_q[ADDR_W-1:0]] <= wdata_i;
        end
    end

    // -----------------------------------------------------------
    // Read pointer (rd_clk domain)
    // -----------------------------------------------------------
    reg  [PTR_W-1:0] rd_ptr_q;
    wire [PTR_W-1:0] rd_ptr_next;
    wire             rd_do;

    assign rd_do   = rd_en_i && !empty_o;
    assign rd_ptr_next = rd_ptr_q + (PTR_W'(rd_do));

    always @(posedge rd_clk_i) begin
        if (rd_rst_i) begin
            rd_ptr_q <= {PTR_W{1'b0}};
        end else begin
            rd_ptr_q <= rd_ptr_next;
        end
    end

    // Memory read (FWFT: combinational)
    assign rdata_o = mem[rd_ptr_q[ADDR_W-1:0]];

    // -----------------------------------------------------------
    // Gray code conversion
    // -----------------------------------------------------------
    function [PTR_W-1:0] bin2gray;
        input [PTR_W-1:0] bin;
        begin
            bin2gray = bin ^ (bin >> 1);
        end
    endfunction

    // Current gray codes
    wire [PTR_W-1:0] wr_gray = bin2gray(wr_ptr_q);
    wire [PTR_W-1:0] rd_gray = bin2gray(rd_ptr_q);

    // Next gray codes (for full detection)
    wire [PTR_W-1:0] wr_gray_next = bin2gray(wr_ptr_next);
    wire [PTR_W-1:0] rd_gray_next = bin2gray(rd_ptr_next);

    // -----------------------------------------------------------
    // Synchronizer: rd_gray -> wr_clk domain (for full detection)
    // -----------------------------------------------------------
    (* ASYNC_REG = "TRUE" *)
    reg [PTR_W-1:0] rd_gray_sync_q;
    (* ASYNC_REG = "TRUE" *)
    reg [PTR_W-1:0] rd_gray_sync_2q;

    always @(posedge wr_clk_i) begin
        if (wr_rst_i) begin
            rd_gray_sync_q  <= {PTR_W{1'b0}};
            rd_gray_sync_2q <= {PTR_W{1'b0}};
        end else begin
            rd_gray_sync_q  <= rd_gray;
            rd_gray_sync_2q <= rd_gray_sync_q;
        end
    end

    // -----------------------------------------------------------
    // Synchronizer: wr_gray -> rd_clk domain (for empty detection)
    // -----------------------------------------------------------
    (* ASYNC_REG = "TRUE" *)
    reg [PTR_W-1:0] wr_gray_sync_q;
    (* ASYNC_REG = "TRUE" *)
    reg [PTR_W-1:0] wr_gray_sync_2q;

    always @(posedge rd_clk_i) begin
        if (rd_rst_i) begin
            wr_gray_sync_q  <= {PTR_W{1'b0}};
            wr_gray_sync_2q <= {PTR_W{1'b0}};
        end else begin
            wr_gray_sync_q  <= wr_gray;
            wr_gray_sync_2q <= wr_gray_sync_q;
        end
    end

    // -----------------------------------------------------------
    // Full / Empty generation (registered outputs to break combinational loops)
    // -----------------------------------------------------------
    // Full: write pointer wrapped around and caught up to read pointer.
    // Uses CURRENT write gray (not next) to avoid combinational feedback
    // through wr_do -> wr_ptr_next -> wr_gray_next -> full -> wr_do.
    // In gray code: invert top TWO bits of synchronized read pointer.
    wire full_next = (wr_gray[PTR_W-1:PTR_W-2] == ~rd_gray_sync_2q[PTR_W-1:PTR_W-2]) &&
                     (wr_gray[PTR_W-3:0]       == rd_gray_sync_2q[PTR_W-3:0]);

    reg full_q;
    always @(posedge wr_clk_i) begin
        if (wr_rst_i) full_q <= 1'b0;
        else          full_q <= full_next;
    end
    assign full_o = full_q;

    // Empty: read pointer matches synchronized write pointer (current values).
    // Registered to avoid combinational loop through rd_do.
    wire empty_next = (rd_gray == wr_gray_sync_2q);

    reg empty_q;
    always @(posedge rd_clk_i) begin
        if (rd_rst_i) empty_q <= 1'b1;  // FIFO empty after reset
        else          empty_q <= empty_next;
    end
    assign empty_o = empty_q;

endmodule

`default_nettype wire
