// Recovered from the project report, PDF pages 151-152.
// Recursive sign-extending sum reduction.
`timescale 1ns / 1ps

module Adder_Tree_Generic #(
     parameter NUM_INPUTS = 5,
     parameter DATA_WIDTH = 24,
     parameter OUT_WIDTH  = 32
 )(
     input wire [NUM_INPUTS*DATA_WIDTH-1:0] in_bus,
     output wire [OUT_WIDTH-1:0] out_sum
 );

     generate

         if (NUM_INPUTS == 1) begin : leaf_node

             assign out_sum = { {(OUT_WIDTH-DATA_WIDTH){in_bus[DATA_WIDTH-1]}}, in_bus };
         end

         else begin : branch_node
             localparam N_LEFT  = NUM_INPUTS / 2;
             localparam N_RIGHT = NUM_INPUTS - N_LEFT;

             wire [OUT_WIDTH-1:0] sum_left;
             wire [OUT_WIDTH-1:0] sum_right;

             Adder_Tree_Generic #(
                 .NUM_INPUTS(N_LEFT),
                 .DATA_WIDTH(DATA_WIDTH),
                 .OUT_WIDTH(OUT_WIDTH)
             ) left_tree (
                 .in_bus(in_bus[N_LEFT*DATA_WIDTH-1 : 0]),
                 .out_sum(sum_left)
             );

             Adder_Tree_Generic #(
                 .NUM_INPUTS(N_RIGHT),
                 .DATA_WIDTH(DATA_WIDTH),
                 .OUT_WIDTH(OUT_WIDTH)
             ) right_tree (
                 .in_bus(in_bus[NUM_INPUTS*DATA_WIDTH-1 : N_LEFT*DATA_WIDTH]),
                 .out_sum(sum_right)
             );

             assign out_sum = sum_left + sum_right;
         end
     endgenerate

endmodule
