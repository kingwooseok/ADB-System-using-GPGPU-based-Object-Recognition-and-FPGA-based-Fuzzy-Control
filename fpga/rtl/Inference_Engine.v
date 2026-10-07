// Recovered from the project report, PDF pages 134-138.
// Parallel rule evaluation and maximum aggregation per output action.
`timescale 1ns / 1ps

module Inference_Engine #(
     parameter MU_WIDTH = 8,
     parameter NUM_RULES = 10,
     parameter NUM_ANG_MFS = 5,
     parameter NUM_VEL_MFS = 2,
    parameter NUM_DC_OUTS = 5,
    parameter NUM_WID_MFS = 2,
    parameter NUM_LIN_OUTS = 2,
    parameter DC_ACTION_WIDTH = 3,
    parameter LIN_ACTION_WIDTH = 1
)(

    input wire clk, rstn,

    input wire i_valid,
    output reg o_valid,

    input wire [NUM_ANG_MFS*MU_WIDTH-1:0] mu_ang_bus,
    input wire [NUM_VEL_MFS*MU_WIDTH-1:0] mu_vel_bus,
    input wire [NUM_WID_MFS*MU_WIDTH-1:0] mu_wid_bus,

    input wire cfg_cs,
    input wire [3:0] cfg_addr,
    input wire [2:0] cfg_data,

    output reg [NUM_DC_OUTS*MU_WIDTH-1:0] dc_out_bus,
    output reg [NUM_LIN_OUTS*MU_WIDTH-1:0] lin_out_bus
    );

    wire [NUM_RULES*MU_WIDTH-1:0] w_dc_weights;
    wire [NUM_RULES*DC_ACTION_WIDTH-1:0] w_dc_actions;
    wire [NUM_DC_OUTS*MU_WIDTH-1:0] w_dc_amu_result;

    wire [NUM_LIN_OUTS*LIN_ACTION_WIDTH-1:0] w_lin_actions;
    wire [NUM_WID_MFS*MU_WIDTH-1:0] w_lin_amu_result;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            o_valid <= 1'b0;
        end else begin

            o_valid <= i_valid;
        end
    end

    genvar i;
    generate
        for (i = 0; i < NUM_RULES; i = i+1) begin : gen_dc_ant
            localparam ANG_IDX = i / 2;
            localparam VEL_IDX = i % 2;
            MM_Core #(
                .MU_WIDTH(MU_WIDTH)
            ) min_core (
                .a(mu_ang_bus[(ANG_IDX+1)*MU_WIDTH-1:ANG_IDX*MU_WIDTH]),
                .b(mu_vel_bus[(VEL_IDX+1)*MU_WIDTH-1:VEL_IDX*MU_WIDTH]),
                .mode(1'b0),
                .out(w_dc_weights[(i+1)*MU_WIDTH-1:i*MU_WIDTH])
            );
        end
    endgenerate

    Rule_Memory mem_inst (
        .clk(clk),
        .rstn(rstn),
        .cfg_cs(cfg_cs),
        .cfg_addr(cfg_addr),
        .cfg_data(cfg_data),
        .rule_dc_flat(w_dc_actions),
        .rule_lin_flat(w_lin_actions)
    );

    AMU #(
        .NUM_RULES(NUM_RULES),
        .NUM_OUTS(NUM_DC_OUTS),
        .ACTION_WIDTH(DC_ACTION_WIDTH)
    ) amu_dc (
        .rule_weights_bus(w_dc_weights),
        .rule_actions_bus(w_dc_actions),
        .agg_out_bus(w_dc_amu_result)
    );

    AMU #(
        .NUM_RULES(NUM_WID_MFS),
        .NUM_OUTS(NUM_LIN_OUTS),
        .ACTION_WIDTH(LIN_ACTION_WIDTH)
    ) amu_lin (
        .rule_weights_bus(mu_wid_bus),
        .rule_actions_bus(w_lin_actions),
        .agg_out_bus(w_lin_amu_result)
    );

    always @(posedge clk, negedge rstn) begin
        if (!rstn) begin
            dc_out_bus <= 0;
            lin_out_bus <= 0;
        end
         else begin
             dc_out_bus <= w_dc_amu_result;
             lin_out_bus <= w_lin_amu_result;
         end
     end

endmodule
