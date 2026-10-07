// Recovered from the project report, PDF pages 126-130.
// Parallel membership functions with a registered input stage.
`timescale 1ns / 1ps

module Fuzzifier #(
     parameter DATA_WIDTH = 16,
     parameter MU_WIDTH = 8,
     parameter NUM_ANG_MFS = 5,
     parameter NUM_VEL_MFS = 2,
     parameter NUM_WID_MFS = 2
 )(
     input wire clk, rstn,

     input wire i_valid,
     output wire o_valid,

     input wire signed [DATA_WIDTH-1:0] angle_in,
     input wire signed [DATA_WIDTH-1:0] width_in,

     input wire s_axi_wen,
     input wire [7:0] s_axi_waddr,
     input wire [DATA_WIDTH-1:0] s_axi_wdata,

     output wire [NUM_ANG_MFS*MU_WIDTH-1:0] mu_ang_bus,
    output wire [NUM_VEL_MFS*MU_WIDTH-1:0] mu_vel_bus,
    output wire [NUM_WID_MFS*MU_WIDTH-1:0] mu_wid_bus
);

    // The report firmware configures velocity membership in transparent mode.
    // This retains the report's per-clock angle-difference implementation.
    reg signed [DATA_WIDTH-1:0] angle_prev;

    reg signed [DATA_WIDTH-1:0] p_angle_in;
    reg signed [DATA_WIDTH-1:0] p_velocity_in;
    reg signed [DATA_WIDTH-1:0] p_width_in;

    reg p_valid;

    always @(posedge clk, negedge rstn) begin
        if (!rstn) begin
            angle_prev <= 0;
            p_angle_in <= 0;
            p_velocity_in <= 0;
            p_width_in <= 0;
            p_valid <= 0;
        end else begin

            angle_prev <= angle_in;

            if ((angle_in - angle_prev) < 0)
                p_velocity_in <= -(angle_in - angle_prev);
            else
                p_velocity_in <= (angle_in - angle_prev);

            p_angle_in <= angle_in;
            p_width_in <= width_in;

            p_valid <= i_valid;
        end
    end

    genvar i;
    generate
        for (i = 0; i < NUM_ANG_MFS; i = i+1) begin : gen_ang_mfs
            localparam [7:0] BASE_ADDR = i * 24;
            localparam [7:0] END_ADDR = BASE_ADDR + 23;
            wire cs = s_axi_wen && (s_axi_waddr >= BASE_ADDR) && (s_axi_waddr <= END_ADDR);
            wire [2:0] reg_idx = (s_axi_waddr - BASE_ADDR) >> 2;

            wire mf_valid_out;

            MF_Core #(.DATA_WIDTH(DATA_WIDTH), .MU_WIDTH(MU_WIDTH)) mf_ang (
                .clk(clk), .rstn(rstn),
                .x(p_angle_in),
                .i_valid(p_valid),
                .o_valid(mf_valid_out),
                .cfg_cs(cs), .cfg_addr(reg_idx), .cfg_data(s_axi_wdata),
                .mu_out(mu_ang_bus[(i+1)*MU_WIDTH - 1:i*MU_WIDTH])
            );

            if (i == 0) assign o_valid = mf_valid_out;
        end
    endgenerate

    localparam [7:0] VEL_START_ADDR = NUM_ANG_MFS * 24;
    genvar j;
    generate
        for (j = 0; j < NUM_VEL_MFS; j = j+1) begin : gen_vel_mfs
            localparam [7:0] BASE_ADDR = VEL_START_ADDR + (j * 24);
            localparam [7:0] END_ADDR = BASE_ADDR + 23;
            wire cs = s_axi_wen && (s_axi_waddr >= BASE_ADDR) && (s_axi_waddr <= END_ADDR);
            wire [2:0] reg_idx = (s_axi_waddr - BASE_ADDR) >> 2;

            MF_Core #(.DATA_WIDTH(DATA_WIDTH), .MU_WIDTH(MU_WIDTH)) mf_vel (
                .clk(clk), .rstn(rstn),
                .x(p_velocity_in),
                .i_valid(p_valid),
                .o_valid(),
                .cfg_cs(cs), .cfg_addr(reg_idx), .cfg_data(s_axi_wdata),
                .mu_out(mu_vel_bus[(j+1)*MU_WIDTH - 1:j*MU_WIDTH])
            );
        end
    endgenerate

    localparam [7:0] WID_START_ADDR = VEL_START_ADDR + (NUM_VEL_MFS * 24);
    genvar k;
    generate
        for (k = 0; k < NUM_WID_MFS; k = k+1) begin : gen_wid_mfs
            localparam [7:0] BASE_ADDR = WID_START_ADDR + (k * 24);
             localparam [7:0] END_ADDR  = BASE_ADDR + 23;
             wire cs = s_axi_wen && (s_axi_waddr >= BASE_ADDR) && (s_axi_waddr <= END_ADDR);
             wire [2:0] reg_idx = (s_axi_waddr - BASE_ADDR) >> 2;

             MF_Core #(.DATA_WIDTH(DATA_WIDTH), .MU_WIDTH(MU_WIDTH)) mf_wid (
                 .clk(clk), .rstn(rstn),
                 .x(p_width_in),
                 .i_valid(p_valid),
                 .o_valid(),
                 .cfg_cs(cs), .cfg_addr(reg_idx), .cfg_data(s_axi_wdata),
                 .mu_out(mu_wid_bus[(k+1)*MU_WIDTH - 1:k*MU_WIDTH])
             );
         end
     endgenerate

endmodule
