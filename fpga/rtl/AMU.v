// Recovered from the project report, PDF pages 141-142.
// Masks rule weights by action index and aggregates each output channel.
`timescale 1ns / 1ps

module AMU #(
     parameter MU_WIDTH = 8,
     parameter NUM_RULES = 10,
     parameter NUM_OUTS = 5,
     parameter ACTION_WIDTH = 3
 )(
     input wire [NUM_RULES*MU_WIDTH-1:0] rule_weights_bus,
     input wire [NUM_RULES*ACTION_WIDTH-1:0] rule_actions_bus,
     output wire [NUM_OUTS*MU_WIDTH-1:0] agg_out_bus
     );

     wire [MU_WIDTH-1:0] weights [0:NUM_RULES-1];
     wire [ACTION_WIDTH-1:0] actions [0:NUM_RULES-1];

     genvar i;
     generate
         for (i = 0; i < NUM_RULES; i = i+1) begin : unpack
             assign weights[i] = rule_weights_bus[(i+1)*MU_WIDTH-1:i*MU_WIDTH];
             assign actions[i] = rule_actions_bus[(i+1)*ACTION_WIDTH-1:i*ACTION_WIDTH];
         end
     endgenerate

     wire [NUM_RULES*MU_WIDTH-1:0] channel_inputs [0:NUM_OUTS-1];

     genvar j, k;
     generate
         for (j = 0; j < NUM_OUTS; j = j+1) begin : channels
             for (k = 0; k < NUM_RULES; k = k+1) begin : mask
                 wire [MU_WIDTH-1:0] masked_val = (actions[k] == j) ? weights[k] : {MU_WIDTH{1'b0}};
                 assign channel_inputs[j][(k+1)*MU_WIDTH-1:k*MU_WIDTH] = masked_val;
             end
         end
     endgenerate

     generate
         for (j = 0; j < NUM_OUTS; j = j+1) begin : output_agg

             Max_Tree_Generic #(
                 .MU_WIDTH(MU_WIDTH), .NUM_INPUTS(NUM_RULES)
             ) g_tree (
                 .in_bus(channel_inputs[j]),
                 .out_max(agg_out_bus[(j+1)*MU_WIDTH-1:j*MU_WIDTH])
             );
         end
     endgenerate

endmodule
