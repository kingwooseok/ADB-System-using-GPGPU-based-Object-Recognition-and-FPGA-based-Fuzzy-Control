// Recovered from the project report, PDF pages 154-156.
// 50 Hz PWM with bounded angle input and period-boundary pulse latching.
`timescale 1ns / 1ps

module PWM_Generator #(
     parameter integer CLK_HZ = 50000000,
     parameter integer REVERSE = 0
 )(
     input  wire signed [31:0] deg_in,
     input  wire               clk,
     input  wire               rstn,
     output reg                pwm_out,
     output wire               nsleep
 );

     assign nsleep = 1'b1;

     localparam integer PERIOD_TICKS = CLK_HZ / 50;
     localparam integer PULSE_MIN    = CLK_HZ / 1000;
     localparam integer PULSE_MAX    = CLK_HZ / 500;
     localparam integer PULSE_MID    = (PULSE_MIN + PULSE_MAX) / 2;
     localparam integer HALF_RANGE   = (PULSE_MAX - PULSE_MIN) / 2;
     localparam signed [31:0] DEG_MAX = 32'sd90;

    localparam integer TICKS_PER_DEG = HALF_RANGE / 90;

    wire signed [31:0] deg_used = (REVERSE != 0) ? -deg_in : deg_in;
    reg signed [31:0] deg_clamped;

    always @(*) begin
        if (deg_used > DEG_MAX)       deg_clamped = DEG_MAX;
        else if (deg_used < -DEG_MAX) deg_clamped = -DEG_MAX;
        else                          deg_clamped = deg_used;
    end

    wire signed [31:0] delta = deg_clamped * $signed(TICKS_PER_DEG);

    wire signed [31:0] pulse_raw = $signed(PULSE_MID) + delta;

    wire [31:0] pulse_final =
        (pulse_raw < $signed(PULSE_MIN)) ? PULSE_MIN :
        (pulse_raw > $signed(PULSE_MAX)) ? PULSE_MAX :
                                           pulse_raw[31:0];

     reg [31:0] period_cnt;
     reg [31:0] pulse_latched;

     always @(posedge clk or negedge rstn) begin
         if (!rstn) begin
             period_cnt    <= 32'd0;
             pulse_latched <= PULSE_MID;
             pwm_out       <= 1'b0;
         end else begin
             if (period_cnt == 32'd0)
                 pulse_latched <= pulse_final;

             pwm_out <= (period_cnt < pulse_latched);

             if (period_cnt >= (PERIOD_TICKS - 1))
                 period_cnt <= 32'd0;
             else
                 period_cnt <= period_cnt + 32'd1;
         end
     end

endmodule
