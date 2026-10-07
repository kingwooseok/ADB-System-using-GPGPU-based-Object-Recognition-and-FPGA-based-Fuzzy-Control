// Recovered from the project report, PDF pages 138-139.
// Configurable action indices for ten angle/velocity and two width rules.
`timescale 1ns / 1ps

module Rule_Memory(
     input wire clk, rstn,

     input wire cfg_cs,
     input wire [3:0] cfg_addr,
     input wire [2:0] cfg_data,

     output wire [29:0] rule_dc_flat,
     output wire [1:0] rule_lin_flat
     );

     reg [2:0] rules_dc [0:9];
     reg [0:0] rules_lin [0:1];

     wire dc_wen;
     wire lin_wen;

     assign dc_wen = cfg_cs && (cfg_addr < 10);
     assign lin_wen = cfg_cs && (cfg_addr >= 10 && cfg_addr < 12);

     wire [3:0] addr_lin_offset = cfg_addr - 4'd10;

     integer i;
     always @(posedge clk, negedge rstn) begin
         if (!rstn) begin
             for (i = 0; i < 10; i = i+1) rules_dc[i] <= 0;
             for (i = 0; i < 2; i = i+1) rules_lin[i] <= 0;
         end
         else begin

             if (dc_wen) rules_dc[cfg_addr] <= cfg_data;

             if (lin_wen) rules_lin[addr_lin_offset] <= cfg_data[0];
         end
     end

     genvar j;
     generate

         for (j = 0; j < 10; j = j+1) begin : dc_pack
             assign rule_dc_flat[(j+1)*3-1:j*3] = rules_dc[j];
         end

         for (j = 0; j < 2; j = j+1) begin : lin_pack
             assign rule_lin_flat[j] = rules_lin[j];
         end
     endgenerate

endmodule
