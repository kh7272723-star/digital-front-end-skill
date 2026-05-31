`default_nettype none
// ============================================================================
// axi_stream_pipeline — N-stage Feed-Forward Pipeline with Backpressure
//
// Validates: pipeline-design-patterns.md §1 (Feed-Forward)
//            performance-analysis.md §1 (Throughput), §3 (Backpressure)
//            memory-hierarchy.md §1 (Buffer Sizing)
//
// Parameters:
//   STAGES = pipeline depth (default 3)
//   DW     = data width (default 64)
//
// Latency: STAGES cycles
// Throughput (ideal): 1 beat/cycle
// Throughput (stalled): 1/(1 + stall_ratio)
// ============================================================================
module axi_stream_pipeline #(
    parameter STAGES = 3,
    parameter DW     = 64
) (
    input  wire         clk_i,
    input  wire         rst_ni,
    input  wire         s_axis_tvalid_i,
    output wire         s_axis_tready_o,
    input  wire [DW-1:0] s_axis_tdata_i,
    output wire         m_axis_tvalid_o,
    input  wire         m_axis_tready_i,
    output wire [DW-1:0] m_axis_tdata_o
);
    // Pipeline registers: v_q[0]=input capture, v_q[STAGES]=output
    reg  [STAGES:0]            v_q;
    reg  [STAGES:0] [DW-1:0]  d_q;
    wire [STAGES:0]            rdy;

    // Backpressure chain: each stage is ready if downstream is ready or empty
    assign rdy[STAGES] = m_axis_tready_i;
    genvar g;
    generate for (g = 0; g < STAGES; g = g + 1) begin : bp_chain
        assign rdy[g] = rdy[g+1] || !v_q[g+1];
    end endgenerate

    // Pipeline shift registers
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            v_q <= {STAGES+1{1'b0}};
            d_q <= {STAGES+1{{DW{1'b0}}}};
        end else begin
            // Each stage captures previous stage if ready
            if (rdy[0]) begin v_q[0] <= s_axis_tvalid_i; d_q[0] <= s_axis_tdata_i; end
            if (STAGES >= 1 && rdy[1]) begin v_q[1] <= v_q[0]; d_q[1] <= d_q[0]; end
            if (STAGES >= 2 && rdy[2]) begin v_q[2] <= v_q[1]; d_q[2] <= d_q[1]; end
            if (STAGES >= 3 && rdy[3]) begin v_q[3] <= v_q[2]; d_q[3] <= d_q[2]; end
            if (STAGES >= 4 && rdy[4]) begin v_q[4] <= v_q[3]; d_q[4] <= d_q[3]; end
            if (STAGES >= 5 && rdy[5]) begin v_q[5] <= v_q[4]; d_q[5] <= d_q[4]; end
            if (STAGES >= 6 && rdy[6]) begin v_q[6] <= v_q[5]; d_q[6] <= d_q[5]; end
            if (STAGES >= 7 && rdy[7]) begin v_q[7] <= v_q[6]; d_q[7] <= d_q[6]; end
            if (STAGES >= 8 && rdy[8]) begin v_q[8] <= v_q[7]; d_q[8] <= d_q[7]; end
        end
    end

    assign s_axis_tready_o = rdy[0];
    assign m_axis_tvalid_o = v_q[STAGES];
    assign m_axis_tdata_o  = d_q[STAGES];

endmodule
`default_nettype wire
