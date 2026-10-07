// Recovered from the project report, PDF pages 120-126.
// Fuzzification, min/max inference and weighted-singleton defuzzification.
`timescale 1ns / 1ps

module Fuzzy_Control_Unit #(

     parameter DATA_WIDTH = 32,
     parameter MU_WIDTH   = 8,
     parameter SINGLETON_WIDTH = 16,

    parameter NUM_ANG_MFS = 5,
    parameter NUM_VEL_MFS = 2,
    parameter NUM_WID_MFS = 2,

    parameter NUM_RULES = 10,
    parameter NUM_DC_OUTS = 5,
    parameter NUM_LIN_OUTS = 2
)(
    input wire clk,
    input wire rstn,

    input wire signed [DATA_WIDTH-1:0] sensor_angle,
    input wire signed [DATA_WIDTH-1:0] sensor_velocity,
    input wire signed [DATA_WIDTH-1:0] sensor_width,
    input wire                         data_valid,

    input wire        cfg_en,
    input wire [11:0] cfg_addr,
    input wire [31:0] cfg_data,

    output wire signed [31:0] crisp_dc_out,
    output wire signed [31:0] crisp_lin_out,
    output wire               output_valid
);

    wire cs_fuzz   = cfg_en && (cfg_addr[11:8] == 4'h0);
    wire cs_inf    = cfg_en && (cfg_addr[11:8] == 4'h1);
    wire cs_defuzz = cfg_en && (cfg_addr[11:8] == 4'h2);

    wire [7:0] local_addr = cfg_addr[7:0];

    wire [3:0] reg_index_addr = local_addr[5:2];

    wire [NUM_ANG_MFS*MU_WIDTH-1:0] w_mu_ang;
    wire [NUM_VEL_MFS*MU_WIDTH-1:0] w_mu_vel;
    wire [NUM_WID_MFS*MU_WIDTH-1:0] w_mu_wid;
    wire w_valid_fuzz;

    wire [NUM_DC_OUTS*MU_WIDTH-1:0]  w_mu_dc_agg;
    wire [NUM_LIN_OUTS*MU_WIDTH-1:0] w_mu_lin_agg;
    wire w_valid_inf;

    wire val_dc, val_lin;

    assign output_valid = val_dc && val_lin;

    Fuzzifier #(
        .DATA_WIDTH(DATA_WIDTH),
        .MU_WIDTH(MU_WIDTH),
        .NUM_ANG_MFS(NUM_ANG_MFS),
        .NUM_VEL_MFS(NUM_VEL_MFS),
        .NUM_WID_MFS(NUM_WID_MFS)
    ) u_fuzzifier (
        .clk(clk),
        .rstn(rstn),

        .i_valid(data_valid),
        .o_valid(w_valid_fuzz),

        .s_axi_wen(cs_fuzz),
        .s_axi_waddr(local_addr),
        .s_axi_wdata(cfg_data),

        .angle_in(sensor_angle),
        .width_in(sensor_width),

        .mu_ang_bus(w_mu_ang),
        .mu_vel_bus(w_mu_vel),
        .mu_wid_bus(w_mu_wid)
    );

    Inference_Engine #(
        .MU_WIDTH(MU_WIDTH),
        .NUM_RULES(NUM_RULES),
        .NUM_ANG_MFS(NUM_ANG_MFS),
        .NUM_VEL_MFS(NUM_VEL_MFS),
        .NUM_DC_OUTS(NUM_DC_OUTS),
        .NUM_WID_MFS(NUM_WID_MFS),
        .NUM_LIN_OUTS(NUM_LIN_OUTS)
    ) u_inference (
        .clk(clk),
        .rstn(rstn),

        .i_valid(w_valid_fuzz),
        .o_valid(w_valid_inf),

        .mu_ang_bus(w_mu_ang),
        .mu_vel_bus(w_mu_vel),
        .mu_wid_bus(w_mu_wid),

        .cfg_cs(cs_inf),
        .cfg_addr(reg_index_addr),
        .cfg_data(cfg_data[2:0]),

        .dc_out_bus(w_mu_dc_agg),
        .lin_out_bus(w_mu_lin_agg)
    );

    Defuzzifier #(
        .MU_WIDTH(MU_WIDTH),
        .SINGLETON_WIDTH(SINGLETON_WIDTH),
        .NUM_DC_INPUTS(NUM_DC_OUTS),
        .NUM_LIN_INPUTS(NUM_LIN_OUTS)
    ) u_defuzzifier (
        .clk(clk),
        .rstn(rstn),

        .i_valid(w_valid_inf),
        .valid_dc(val_dc),
        .valid_lin(val_lin),

        .mu_dc_bus(w_mu_dc_agg),
        .mu_lin_bus(w_mu_lin_agg),

        .cfg_cs(cs_defuzz),
        .cfg_addr(reg_index_addr),
        .cfg_data(cfg_data[SINGLETON_WIDTH-1:0]),

         .crisp_dc_out(crisp_dc_out),
         .crisp_lin_out(crisp_lin_out)
     );

endmodule
