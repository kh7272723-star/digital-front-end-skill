`default_nettype none
// Pipeline register with ready/valid handshaking
// BUG: payload changes during downstream stall (H1 violation)
module pipeline_reg #(
    parameter DATA_W = 32
) (
    input  wire              clk_i,
    input  wire              rst_i,
    // Upstream interface
    input  wire              s_valid_i,
    output wire              s_ready_o,
    input  wire [DATA_W-1:0] s_data_i,
    // Downstream interface
    output reg               m_valid_o,
    input  wire              m_ready_i,
    output reg  [DATA_W-1:0] m_data_o
);

    // H1 fix: payload must be stable when valid_o=1 && ready_i=0.
    // Data only updates when input is accepted (valid_i && ready_o).
    wire accept_output;
    wire accept_input;

    assign accept_output = m_valid_o && m_ready_i;
    assign s_ready_o     = !m_valid_o || accept_output;
    assign accept_input  = s_valid_i && s_ready_o;

    always @(posedge clk_i) begin
        if (rst_i) begin
            m_valid_o <= 1'b0;
        end else if (s_ready_o) begin
            m_valid_o <= s_valid_i;
            if (accept_input)
                m_data_o <= s_data_i;
        end
    end

endmodule
`default_nettype wire
