module irq_aggregator #(
    parameter COUNT_W = 3,
    parameter BYTE_W = 16,
    parameter TIMEOUT_W = 4
) (
    input  wire                  clk_i,
    input  wire                  rst_i,

    input  wire                  cpl_commit_valid_i,
    input  wire [BYTE_W-1:0]     cpl_commit_bytes_i,

    input  wire [COUNT_W-1:0]    irq_cqe_threshold_i,
    input  wire [BYTE_W-1:0]     irq_byte_threshold_i,
    input  wire [TIMEOUT_W-1:0]  irq_timeout_threshold_i,

    output reg                   irq_pulse_o,
    output reg  [1:0]            irq_reason_o,
    output wire [COUNT_W-1:0]    irq_cqe_count_o,
    output wire [BYTE_W-1:0]     irq_byte_count_o
);

    localparam [1:0] IRQ_REASON_NONE = 2'd0;
    localparam [1:0] IRQ_REASON_COUNT = 2'd1;
    localparam [1:0] IRQ_REASON_BYTES = 2'd2;
    localparam [1:0] IRQ_REASON_TIMEOUT = 2'd3;

    localparam [COUNT_W-1:0] ONE_COUNT = {{(COUNT_W-1){1'b0}}, 1'b1};

    reg [COUNT_W-1:0] irq_cqe_count_q;
    reg [BYTE_W-1:0] irq_byte_count_q;
    reg [TIMEOUT_W-1:0] irq_timer_q;

    wire [COUNT_W-1:0] count_after_commit;
    wire [BYTE_W-1:0] bytes_after_commit;
    wire count_threshold_hit;
    wire byte_threshold_hit;
    wire timeout_threshold_hit;

    assign count_after_commit = irq_cqe_count_q + ONE_COUNT;
    assign bytes_after_commit = irq_byte_count_q + cpl_commit_bytes_i;

    assign count_threshold_hit = (irq_cqe_threshold_i != {COUNT_W{1'b0}}) &&
                                 (count_after_commit >= irq_cqe_threshold_i);
    assign byte_threshold_hit = (irq_byte_threshold_i != {BYTE_W{1'b0}}) &&
                                (bytes_after_commit >= irq_byte_threshold_i);
    assign timeout_threshold_hit = (irq_timeout_threshold_i != {TIMEOUT_W{1'b0}}) &&
                                   (irq_cqe_count_q != {COUNT_W{1'b0}}) &&
                                   (irq_timer_q >= (irq_timeout_threshold_i - {{(TIMEOUT_W-1){1'b0}}, 1'b1}));

    assign irq_cqe_count_o = irq_cqe_count_q;
    assign irq_byte_count_o = irq_byte_count_q;

    always @(posedge clk_i) begin
        if (rst_i) begin
            irq_cqe_count_q <= {COUNT_W{1'b0}};
            irq_byte_count_q <= {BYTE_W{1'b0}};
            irq_timer_q <= {TIMEOUT_W{1'b0}};
            irq_pulse_o <= 1'b0;
            irq_reason_o <= IRQ_REASON_NONE;
        end else begin
            irq_pulse_o <= 1'b0;
            irq_reason_o <= IRQ_REASON_NONE;

            if (cpl_commit_valid_i) begin
                if (count_threshold_hit) begin
                    irq_cqe_count_q <= {COUNT_W{1'b0}};
                    irq_byte_count_q <= {BYTE_W{1'b0}};
                    irq_timer_q <= {TIMEOUT_W{1'b0}};
                    irq_pulse_o <= 1'b1;
                    irq_reason_o <= IRQ_REASON_COUNT;
                end else if (byte_threshold_hit) begin
                    irq_cqe_count_q <= {COUNT_W{1'b0}};
                    irq_byte_count_q <= {BYTE_W{1'b0}};
                    irq_timer_q <= {TIMEOUT_W{1'b0}};
                    irq_pulse_o <= 1'b1;
                    irq_reason_o <= IRQ_REASON_BYTES;
                end else begin
                    irq_cqe_count_q <= count_after_commit;
                    irq_byte_count_q <= bytes_after_commit;
                    irq_timer_q <= {{(TIMEOUT_W-1){1'b0}}, 1'b1};
                end
            end else if (irq_cqe_count_q != {COUNT_W{1'b0}}) begin
                if (timeout_threshold_hit) begin
                    irq_cqe_count_q <= {COUNT_W{1'b0}};
                    irq_byte_count_q <= {BYTE_W{1'b0}};
                    irq_timer_q <= {TIMEOUT_W{1'b0}};
                    irq_pulse_o <= 1'b1;
                    irq_reason_o <= IRQ_REASON_TIMEOUT;
                end else begin
                    irq_timer_q <= irq_timer_q + {{(TIMEOUT_W-1){1'b0}}, 1'b1};
                end
            end
        end
    end

endmodule
