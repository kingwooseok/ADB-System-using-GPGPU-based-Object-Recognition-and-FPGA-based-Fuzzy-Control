`timescale 1ns / 1ps
// Simulation-only stand-in for the externally generated AMD divider IP.
// This models the wrapper's signed arithmetic and 36-cycle valid pipeline.
// Do not add this file to the Vivado synthesis source set.
module div_gen_0 (
    input wire aclk,
    input wire s_axis_divisor_tvalid,
    input wire signed [15:0] s_axis_divisor_tdata,
    input wire s_axis_dividend_tvalid,
    input wire signed [31:0] s_axis_dividend_tdata,
    output wire m_axis_dout_tvalid,
    output wire [47:0] m_axis_dout_tdata
);
    reg [35:0] valid_pipe = 0;
    reg signed [31:0] quotient_pipe [0:35];
    integer i;
    initial begin
        for (i = 0; i < 36; i = i + 1) quotient_pipe[i] = 0;
    end
    always @(posedge aclk) begin
        valid_pipe <= {valid_pipe[34:0],
                       s_axis_divisor_tvalid && s_axis_dividend_tvalid};
        quotient_pipe[0] <= s_axis_dividend_tdata / s_axis_divisor_tdata;
        for (i = 1; i < 36; i = i + 1)
            quotient_pipe[i] <= quotient_pipe[i-1];
    end
    assign m_axis_dout_tvalid = valid_pipe[35];
    assign m_axis_dout_tdata = {quotient_pipe[35], 16'd0};
endmodule
