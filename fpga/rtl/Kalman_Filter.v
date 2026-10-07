// Recovered from the project report, PDF pages 101-103.
// Two independent threshold filters for angle and width channels.
`timescale 1ns / 1ps

module Kalman_Filter #(

   parameter [15:0] CH0_SPIKE_TH = 16'd800,
  parameter [15:0] CH1_SPIKE_TH = 16'd800,

  parameter [15:0] DEV_TH   = 16'd200,
  parameter [15:0] MAX_STEP = 16'd50,
  parameter [3:0]  SAME_N   = 4'd5
)(
  input  wire        clk,
  input  wire        rstn,

  input  wire        ps_valid,
  input  wire [15:0] ps_z0,
  input  wire [15:0] ps_z1,
  output wire        ps_ready,

  output wire        x0_update,
  output wire [15:0] x0_u16,
  output wire        x1_update,
  output wire [15:0] x1_u16
);

  assign ps_ready = 1'b1;
  wire ps_fire = ps_valid;

  KM_Core #(
    .T1      (DEV_TH),
    .T2      (CH0_SPIKE_TH),
    .MAX_STEP(MAX_STEP),
    .SAME_N  (SAME_N)
  ) u_core0 (
    .clk(clk), .rstn(rstn),
    .z_valid(ps_fire),
    .z_data ($signed(ps_z0)),
    .z_ready(),
    .x_update(x0_update),
     .x_u16_hold(x0_u16)
   );

   KM_Core #(
     .T1      (DEV_TH),
     .T2      (CH1_SPIKE_TH),
     .MAX_STEP(MAX_STEP),
     .SAME_N  (SAME_N)
   ) u_core1 (
     .clk(clk), .rstn(rstn),
     .z_valid(ps_fire),
     .z_data ($signed(ps_z1)),
     .z_ready(),
     .x_update(x1_update),
     .x_u16_hold(x1_u16)
   );

endmodule
