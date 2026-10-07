// Recovered from the project report, PDF pages 140-141.
// Recursive balanced maximum reduction.
`timescale 1ns / 1ps

module Max_Tree_Generic #(
     parameter MU_WIDTH = 8,
     parameter NUM_INPUTS = 10
 )(
     input wire [NUM_INPUTS*MU_WIDTH-1:0] in_bus,
     output wire [MU_WIDTH-1:0] out_max
     );

     generate

         if (NUM_INPUTS == 1) begin : leaf_node
             assign out_max = in_bus;
         end

         else begin : branch_node
             localparam N_LEFT = NUM_INPUTS / 2;
             localparam N_RIGHT = NUM_INPUTS - N_LEFT;

             wire [MU_WIDTH-1:0] max_left;
             wire [MU_WIDTH-1:0] max_right;

             Max_Tree_Generic #(
                 .MU_WIDTH(MU_WIDTH), .NUM_INPUTS(N_LEFT)
             ) left_tree (
                 .in_bus(in_bus[N_LEFT*MU_WIDTH-1:0]),
                 .out_max(max_left)
             );

             Max_Tree_Generic #(
                 .MU_WIDTH(MU_WIDTH), .NUM_INPUTS(N_RIGHT)
             ) right_tree (
                 .in_bus(in_bus[NUM_INPUTS*MU_WIDTH-1:N_LEFT*MU_WIDTH]),
                 .out_max(max_right)
             );

             MM_Core #(
                 .MU_WIDTH(MU_WIDTH)
             ) max_core (
                 .a(max_left),
                 .b(max_right),
                 .mode(1'd1),
                 .out(out_max)
             );
         end
     endgenerate

endmodule
