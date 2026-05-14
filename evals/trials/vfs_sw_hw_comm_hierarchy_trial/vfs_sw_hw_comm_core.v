module vfs_sw_hw_comm_core #(
    parameter ADDR_W = 32,
    parameter PTR_W = 2,
    parameter COUNT_W = 3,
    parameter BYTE_W = 16,
    parameter TIMEOUT_W = 4,
    parameter ENTRY_BYTES = 64,
    parameter MAX_BURST_ENTRIES = 2
) (
    input  wire                   clk_i,
    input  wire                   rst_i,

    input  wire [ADDR_W-1:0]      sq_base_addr_i,
    input  wire                   sq_tail_db_wr_en_i,
    input  wire [PTR_W-1:0]       sq_tail_db_i,
    output wire [PTR_W-1:0]       sq_head_o,
    output wire [COUNT_W-1:0]     sq_pending_o,

    output wire                   sq_cmd_valid_o,
    input  wire                   sq_cmd_ready_i,
    output wire [ADDR_W-1:0]      sq_cmd_addr_o,
    output wire [COUNT_W-1:0]     sq_cmd_len_o,

    input  wire [ADDR_W-1:0]      cq_base_addr_i,
    input  wire                   cq_head_db_wr_en_i,
    input  wire [PTR_W-1:0]       cq_head_db_i,
    output wire [PTR_W-1:0]       cq_tail_o,
    output wire [COUNT_W-1:0]     cq_pending_o,
    output wire                   cq_full_o,

    input  wire                   cpl_valid_i,
    output wire                   cpl_ready_o,
    input  wire [BYTE_W-1:0]      cpl_bytes_i,

    output wire                   cq_cmd_valid_o,
    input  wire                   cq_cmd_ready_i,
    output wire [ADDR_W-1:0]      cq_cmd_addr_o,
    output wire [COUNT_W-1:0]     cq_cmd_len_o,
    output wire                   cq_cmd_phase_o,
    input  wire                   cq_write_done_i,

    input  wire [COUNT_W-1:0]     irq_cqe_threshold_i,
    input  wire [BYTE_W-1:0]      irq_byte_threshold_i,
    input  wire [TIMEOUT_W-1:0]   irq_timeout_threshold_i,
    output wire                   irq_pulse_o,
    output wire [1:0]             irq_reason_o
);

    wire cpl_commit_valid;
    wire [BYTE_W-1:0] cpl_commit_bytes;

    sqe_read_cmd_gen #(
        .ADDR_W(ADDR_W),
        .PTR_W(PTR_W),
        .COUNT_W(COUNT_W),
        .ENTRY_BYTES(ENTRY_BYTES),
        .MAX_BURST_ENTRIES(MAX_BURST_ENTRIES)
    ) u_sqe_read_cmd_gen (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .sq_base_addr_i(sq_base_addr_i),
        .sq_tail_db_wr_en_i(sq_tail_db_wr_en_i),
        .sq_tail_db_i(sq_tail_db_i),
        .sq_head_o(sq_head_o),
        .sq_tail_o(),
        .sq_pending_o(sq_pending_o),
        .cmd_valid_o(sq_cmd_valid_o),
        .cmd_ready_i(sq_cmd_ready_i),
        .cmd_addr_o(sq_cmd_addr_o),
        .cmd_len_o(sq_cmd_len_o)
    );

    cqe_write_cmd_gen #(
        .ADDR_W(ADDR_W),
        .PTR_W(PTR_W),
        .COUNT_W(COUNT_W),
        .BYTE_W(BYTE_W),
        .ENTRY_BYTES(ENTRY_BYTES)
    ) u_cqe_write_cmd_gen (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .cq_base_addr_i(cq_base_addr_i),
        .cq_head_db_wr_en_i(cq_head_db_wr_en_i),
        .cq_head_db_i(cq_head_db_i),
        .cq_head_o(),
        .cq_tail_o(cq_tail_o),
        .cq_pending_o(cq_pending_o),
        .cq_full_o(cq_full_o),
        .cpl_valid_i(cpl_valid_i),
        .cpl_ready_o(cpl_ready_o),
        .cpl_bytes_i(cpl_bytes_i),
        .cmd_valid_o(cq_cmd_valid_o),
        .cmd_ready_i(cq_cmd_ready_i),
        .cmd_addr_o(cq_cmd_addr_o),
        .cmd_len_o(cq_cmd_len_o),
        .cmd_phase_o(cq_cmd_phase_o),
        .write_done_i(cq_write_done_i),
        .cpl_commit_valid_o(cpl_commit_valid),
        .cpl_commit_bytes_o(cpl_commit_bytes)
    );

    irq_aggregator #(
        .COUNT_W(COUNT_W),
        .BYTE_W(BYTE_W),
        .TIMEOUT_W(TIMEOUT_W)
    ) u_irq_aggregator (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .cpl_commit_valid_i(cpl_commit_valid),
        .cpl_commit_bytes_i(cpl_commit_bytes),
        .irq_cqe_threshold_i(irq_cqe_threshold_i),
        .irq_byte_threshold_i(irq_byte_threshold_i),
        .irq_timeout_threshold_i(irq_timeout_threshold_i),
        .irq_pulse_o(irq_pulse_o),
        .irq_reason_o(irq_reason_o),
        .irq_cqe_count_o(),
        .irq_byte_count_o()
    );

endmodule
