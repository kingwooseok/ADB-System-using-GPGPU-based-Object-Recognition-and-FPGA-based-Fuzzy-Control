// Recovered from the project report, PDF pages 152-154.
// Signed Divider Generator adapter with zero-denominator protection.
`timescale 1ns / 1ps

module Divider_Wrapper (
     input wire clk,

     input wire signed [31:0] dividend,
     input wire signed [15:0] divisor,
     input wire               input_valid,

     output wire signed [31:0] quotient,
     output wire               output_valid
 );

     wire signed [15:0] safe_divisor;
    wire signed [31:0] safe_dividend;

    assign safe_divisor  = (divisor == 16'd0) ? 16'd1 : divisor;
    assign safe_dividend = (divisor == 16'd0) ? 32'd0 : dividend;

    wire [47:0] m_axis_dout_tdata;

    div_gen_0 u_div_ip (
        .aclk(clk),

        .s_axis_divisor_tvalid(input_valid),
        .s_axis_divisor_tdata(safe_divisor),

        .s_axis_dividend_tvalid(input_valid),
        .s_axis_dividend_tdata(safe_dividend),

        .m_axis_dout_tvalid(output_valid),
        .m_axis_dout_tdata(m_axis_dout_tdata)
    );

     // Divider Generator remainder format: quotient[47:16], remainder[15:0].
    assign quotient = m_axis_dout_tdata[47:16];

endmodule
