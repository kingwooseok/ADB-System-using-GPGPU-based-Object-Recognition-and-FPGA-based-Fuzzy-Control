// Recovered from the project report, PDF pages 146-151.
// Parallel signed products and balanced sum trees; two-cycle latency.
`timescale 1ns / 1ps

module MAC_Core #(
     parameter NUM_INPUTS = 5,
     parameter MU_WIDTH = 8,
    parameter SINGLETON_WIDTH = 16
)(
    input wire clk, rstn,

    input wire i_valid,
    output reg o_valid,

    input wire [NUM_INPUTS*MU_WIDTH-1:0] mu_bus,

    input wire cfg_cs,
    input wire [3:0] cfg_addr,
    input wire [SINGLETON_WIDTH-1:0] cfg_data,

    output reg signed [2*SINGLETON_WIDTH-1:0] sum_numerator,
    output reg [SINGLETON_WIDTH-1:0] sum_denominator
    );

    reg valid_d1;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            valid_d1 <= 1'b0;
            o_valid  <= 1'b0;
        end else begin
            valid_d1 <= i_valid;
            o_valid  <= valid_d1;
        end
    end

    reg signed [SINGLETON_WIDTH-1:0] singleton_mem [0:NUM_INPUTS-1];

    integer i;
    always @(posedge clk, negedge rstn) begin
        if (!rstn) begin
            for (i = 0; i < NUM_INPUTS; i = i+1) singleton_mem[i] <= 0;
        end
        else if (cfg_cs) begin
            if (cfg_addr < NUM_INPUTS) begin
                singleton_mem[cfg_addr] <= $signed(cfg_data);
            end
        end
    end

    wire [MU_WIDTH-1:0] mu [0:NUM_INPUTS-1];

    genvar j;
    generate
        for (j = 0; j < NUM_INPUTS; j = j+1) begin : unpack
            assign mu[j] = mu_bus[(j+1)*MU_WIDTH-1:j*MU_WIDTH];
        end
    endgenerate

    wire [NUM_INPUTS*(MU_WIDTH+SINGLETON_WIDTH)-1 : 0] product_bus;
    wire [NUM_INPUTS*MU_WIDTH-1 : 0] mu_delayed_bus;

    reg signed [MU_WIDTH+SINGLETON_WIDTH-1:0] products [0:NUM_INPUTS-1];
    reg [MU_WIDTH-1:0] mu_reg [0:NUM_INPUTS-1];

    integer k;
    always @(posedge clk, negedge rstn) begin
        if (!rstn) begin
            for (k = 0; k < NUM_INPUTS; k = k+1) begin
                products[k] <= 0;
                mu_reg[k] <= 0;
            end
        end
        else begin
            for (k = 0; k < NUM_INPUTS; k = k+1) begin
                products[k] <= $signed({1'b0, mu[k]}) * singleton_mem[k];
                mu_reg[k] <= mu[k];
            end
        end
    end

    genvar m;
    generate
        for (m = 0; m < NUM_INPUTS; m = m+1) begin : pack_tree
            assign
product_bus[(m+1)*(MU_WIDTH+SINGLETON_WIDTH)-1:m*(MU_WIDTH+SINGLETON_WIDTH)] =
products[m];
            assign mu_delayed_bus[(m+1)*MU_WIDTH-1:m*MU_WIDTH] = mu_reg[m];
        end
    endgenerate

    wire signed [2*SINGLETON_WIDTH-1:0] tree_sum_num;
    wire signed [SINGLETON_WIDTH-1:0] tree_sum_den;

    Adder_Tree_Generic #(
        .NUM_INPUTS(NUM_INPUTS),
        .DATA_WIDTH(MU_WIDTH+SINGLETON_WIDTH),
        .OUT_WIDTH(2*SINGLETON_WIDTH)
    ) num_tree (
        .in_bus(product_bus),
        .out_sum(tree_sum_num)
    );

    wire [NUM_INPUTS*(MU_WIDTH+1)-1:0] mu_bus_padded;
    generate
        for (m = 0; m < NUM_INPUTS; m = m+1) begin : pad_mu

            assign mu_bus_padded[(m+1)*(MU_WIDTH+1)-1:m*(MU_WIDTH+1)] = {1'b0, mu_reg[m]};
        end
    endgenerate

    wire [2*SINGLETON_WIDTH-1:0] tree_sum_den_extended;

    Adder_Tree_Generic #(
        .NUM_INPUTS(NUM_INPUTS),
        .DATA_WIDTH(MU_WIDTH+1),
        .OUT_WIDTH(2*SINGLETON_WIDTH)
    ) den_tree (
        .in_bus(mu_bus_padded),
        .out_sum(tree_sum_den_extended)
    );

    assign tree_sum_den = tree_sum_den_extended[SINGLETON_WIDTH-1:0];

    always @(posedge clk, negedge rstn) begin
        if (!rstn) begin
            sum_numerator <= 0;
            sum_denominator <= 0;
        end
        else begin
            sum_numerator <= tree_sum_num;
            sum_denominator <= tree_sum_den;
         end
     end

endmodule
