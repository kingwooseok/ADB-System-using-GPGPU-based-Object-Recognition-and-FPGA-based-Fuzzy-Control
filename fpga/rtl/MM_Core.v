// Recovered from the project report, PDF pages 139-140.
// Combinational minimum/maximum operator.
`timescale 1ns / 1ps

module MM_Core #(
     parameter MU_WIDTH = 8
 )(

     input wire [MU_WIDTH-1:0] a,
     input wire [MU_WIDTH-1:0] b,
     input wire mode,

     output wire [MU_WIDTH-1:0] out
     );

     wire [MU_WIDTH-1:0] min_val = (a < b) ? a : b;
     wire [MU_WIDTH-1:0] max_val = (a > b) ? a : b;

     assign out = (mode == 1'b1) ? max_val : min_val;

endmodule
