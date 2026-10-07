// Recovered from the project report, PDF pages 103-107.
// Spike rejection, slew limiting and stable-input rearming for signed samples.
`timescale 1ns / 1ps

module KM_Core #(
   parameter [15:0] T1       = 16'd200,
   parameter [15:0] T2       = 16'd800,
   parameter [15:0] MAX_STEP = 16'd50,
   parameter [3:0]  SAME_N   = 4'd5
 )(
   input  wire               clk,
   input  wire               rstn,

   input  wire               z_valid,
   input  wire signed [15:0] z_data,
   output wire               z_ready,

   output reg                x_update,
   output reg  signed [15:0] x_u16_hold
 );
  assign z_ready = 1'b1;
  wire z_fire = z_valid & z_ready;

  reg signed [15:0] in_hold;
  reg               init_done;
  reg [3:0]         same_cnt;
  reg               armed;

  function [15:0] abs16s;
    input signed [15:0] a;
    input signed [15:0] b;
    reg   signed [16:0] d;
    reg   [16:0]        mag;
    begin
      d = $signed({a[15], a}) - $signed({b[15], b});
      if (d < 0) mag = (~d) + 17'd1;
      else       mag = d[16:0];
      abs16s = mag[15:0];
    end
  endfunction

  wire [15:0] diff_in  = abs16s(z_data, in_hold);
  wire [15:0] diff_out = abs16s(z_data, x_u16_hold);
  wire        same_as_prev = (z_data == in_hold);

  reg  signed [16:0] step;
  reg  signed [16:0] step_lim;
  reg  signed [16:0] x_next_s;
  reg  signed [15:0] x_next_sat;

  always @(*) begin

    step = $signed({z_data[15], z_data}) - $signed({x_u16_hold[15], x_u16_hold});

    if (step >  $signed({1'b0, MAX_STEP}))      step_lim =  $signed({1'b0, MAX_STEP});
    else if (step < -$signed({1'b0, MAX_STEP})) step_lim = -$signed({1'b0, MAX_STEP});
    else                                        step_lim = step;

    x_next_s = $signed({x_u16_hold[15], x_u16_hold}) + step_lim;

    if (x_next_s >  17'sd32767)      x_next_sat = 16'sh7FFF;
    else if (x_next_s < -17'sd32768) x_next_sat = 16'sh8000;
    else                             x_next_sat = x_next_s[15:0];
  end

  always @(posedge clk) begin
    if (!rstn) begin
      x_u16_hold <= 16'sd0;
      in_hold    <= 16'sd0;
      init_done  <= 1'b0;
      x_update   <= 1'b0;
      same_cnt   <= 4'd0;
      armed      <= 1'b0;
    end else begin
      x_update <= 1'b0;

      if (z_fire) begin

        if (!init_done) begin
          x_u16_hold <= z_data;
          in_hold    <= z_data;
          init_done  <= 1'b1;
          same_cnt   <= 4'd1;
          armed      <= 1'b0;
          x_update   <= 1'b1;
        end else begin

          if (same_as_prev) begin
            if (same_cnt != 4'hF) same_cnt <= same_cnt + 4'd1;
          end else begin
            same_cnt <= 4'd0;
          end

          if (same_as_prev && ((same_cnt + 4'd1) >= SAME_N))
            armed <= 1'b1;

          if (armed && !same_as_prev) begin
            x_u16_hold <= z_data;
            in_hold    <= z_data;
            x_update   <= 1'b1;
            armed      <= 1'b0;
            same_cnt   <= 4'd0;
          end else begin

            if (diff_out >= T2) begin
              x_update <= 1'b0;

            end else begin

              if (diff_in <= T1) begin
                x_u16_hold <= z_data;
                 in_hold    <= z_data;
                 x_update   <= 1'b1;
               end else begin

                 x_u16_hold <= x_next_sat;
                 in_hold    <= z_data;
                 x_update   <= 1'b1;
               end
             end
           end
         end
       end
     end
   end

endmodule
