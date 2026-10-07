// Recovered from the project report, PDF pages 130-134.
// Three-stage trapezoidal membership pipeline with Q8 slope coefficients.
`timescale 1ns / 1ps

module MF_Core #(
     parameter DATA_WIDTH = 16,
     parameter MU_WIDTH = 8
 )(
     input wire clk, rstn,
     input wire signed [DATA_WIDTH-1:0] x,

     input wire i_valid,
     output reg o_valid,

     input wire cfg_cs,
    input wire [2:0] cfg_addr,
    input wire [DATA_WIDTH-1:0] cfg_data,

    output reg [MU_WIDTH-1:0] mu_out
);

    reg signed [DATA_WIDTH-1:0] param_a, param_b, param_c, param_d;
    reg [DATA_WIDTH-1:0] slope_ab, slope_dc;

    reg signed [DATA_WIDTH-1:0] r1_diff_x;
    reg [1:0] r1_region;

    reg signed [2*DATA_WIDTH-1:0] r2_mul_result;
    reg [1:0] r2_region;

    reg [1:0] valid_pipe;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            valid_pipe <= 2'b0;
            o_valid <= 1'b0;
        end else begin

            valid_pipe <= {valid_pipe[0], i_valid};

            o_valid <= valid_pipe[1];
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            r1_region <= 0;
            r1_diff_x <= 0;
        end else begin

            // Include the plateau first so a=b and c=d shoulder endpoints
            // retain full membership at the configured input limits.
            if (x >= param_b && x <= param_c) begin
                r1_region <= 2;
                r1_diff_x <= 0;
            end
            else if (x <= param_a || x >= param_d) begin
                r1_region <= 0;
                r1_diff_x <= 0;
            end
            else if (x < param_b) begin
                r1_region <= 1;
                r1_diff_x <= x - param_a;
            end
            else begin
                r1_region <= 3;
                r1_diff_x <= param_d - x;
            end
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            r2_mul_result <= 0;
            r2_region <= 0;
        end else begin
            r2_region <= r1_region;

            case (r1_region)
                1: r2_mul_result <= r1_diff_x * $signed({1'b0, slope_ab});
                3: r2_mul_result <= r1_diff_x * $signed({1'b0, slope_dc});
                default: r2_mul_result <= 0;
            endcase
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            mu_out <= 0;
        end else begin
            case (r2_region)
                0: mu_out <= 0;
                1, 3: begin

                    if (r2_mul_result[31:8] > 255)
                        mu_out <= 255;
                    else
                        mu_out <= r2_mul_result[15:8];
                end
                2: mu_out <= 255;
                default: mu_out <= 0;
            endcase
         end
     end

     always @(posedge clk or negedge rstn) begin
         if (!rstn) begin
             param_a <= 0; param_b <= 0; param_c <= 0; param_d <= 0;
             slope_ab <= 0; slope_dc <= 0;
         end else if (cfg_cs) begin
             case (cfg_addr)
                 3'd0: param_a <= $signed(cfg_data);
                 3'd1: param_b <= $signed(cfg_data);
                 3'd2: param_c <= $signed(cfg_data);
                 3'd3: param_d <= $signed(cfg_data);
                 3'd4: slope_ab <= cfg_data;
                 3'd5: slope_dc <= cfg_data;
             endcase
         end
     end

endmodule
