// Recovered from the project report, PDF pages 143-146.
// Independent weighted-singleton pipelines for angle and width outputs.
`timescale 1ns / 1ps

module Defuzzifier #(
    parameter MU_WIDTH = 8,
    parameter SINGLETON_WIDTH = 16,

    parameter NUM_DC_INPUTS = 5,

    parameter NUM_LIN_INPUTS = 2
)(
    input wire clk, rstn,

    input wire i_valid,
    output wire valid_dc,
    output wire valid_lin,

    input wire [NUM_DC_INPUTS*MU_WIDTH-1:0]  mu_dc_bus,
    input wire [NUM_LIN_INPUTS*MU_WIDTH-1:0] mu_lin_bus,

    input wire        cfg_cs,
    input wire [3:0] cfg_addr,
    input wire [SINGLETON_WIDTH-1:0] cfg_data,

    output wire signed [31:0] crisp_dc_out,
    output wire signed [31:0] crisp_lin_out
);

    wire dc_cfg_en;
    wire lin_cfg_en;
    wire [3:0] lin_cfg_addr_mapped;

    assign dc_cfg_en = cfg_cs && (cfg_addr < NUM_DC_INPUTS);

    assign lin_cfg_en = cfg_cs && (cfg_addr >= NUM_DC_INPUTS) && (cfg_addr < NUM_DC_INPUTS
+ NUM_LIN_INPUTS);

    assign lin_cfg_addr_mapped = cfg_addr - NUM_DC_INPUTS;

    wire signed [31:0] w_dc_num;
    wire [15:0]        w_dc_den;
    wire               w_mac_dc_valid;

    MAC_Core #(
        .NUM_INPUTS(NUM_DC_INPUTS),
        .MU_WIDTH(MU_WIDTH),
        .SINGLETON_WIDTH(SINGLETON_WIDTH)
    ) u_mac_dc (
        .clk(clk),
        .rstn(rstn),
        .i_valid(i_valid),
        .o_valid(w_mac_dc_valid),
        .mu_bus(mu_dc_bus),

        .cfg_cs(dc_cfg_en),
        .cfg_addr(cfg_addr),
        .cfg_data(cfg_data),

        .sum_numerator(w_dc_num),
        .sum_denominator(w_dc_den)
    );

    Divider_Wrapper u_div_dc (
        .clk(clk),
        .dividend(w_dc_num),
        .divisor(w_dc_den),
        .input_valid(w_mac_dc_valid),

        .quotient(crisp_dc_out),
        .output_valid(valid_dc)
    );

    wire signed [31:0] w_lin_num;
    wire [15:0]        w_lin_den;
    wire               w_mac_lin_valid;

    MAC_Core #(
        .NUM_INPUTS(NUM_LIN_INPUTS),
        .MU_WIDTH(MU_WIDTH),
        .SINGLETON_WIDTH(SINGLETON_WIDTH)
    ) u_mac_lin (
        .clk(clk),
        .rstn(rstn),
         .i_valid(i_valid),
         .o_valid(w_mac_lin_valid),
         .mu_bus(mu_lin_bus),

         .cfg_cs(lin_cfg_en),
         .cfg_addr(lin_cfg_addr_mapped),
         .cfg_data(cfg_data),

         .sum_numerator(w_lin_num),
         .sum_denominator(w_lin_den)
     );

     Divider_Wrapper u_div_lin (
         .clk(clk),
         .dividend(w_lin_num),
         .divisor(w_lin_den),
         .input_valid(w_mac_lin_valid),

         .quotient(crisp_lin_out),
         .output_valid(valid_lin)
     );

endmodule
