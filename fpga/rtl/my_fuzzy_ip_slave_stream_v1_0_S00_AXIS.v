// Recovered from the project report, PDF pages 117-120.
// Unpacks three 32-bit stream words: angle, velocity and width.
`timescale 1ns / 1ps

module my_fuzzy_ip_slave_stream_v1_0_S00_AXIS #
 (

    parameter integer C_S_AXIS_TDATA_WIDTH = 32
)
(

    output reg signed [31:0] o_angle,
    output reg signed [31:0] o_velocity,
    output reg signed [31:0] o_width,
    output reg               o_data_valid,

    input wire  S_AXIS_ACLK,

    input wire  S_AXIS_ARESETN,

    output wire  S_AXIS_TREADY,

    input wire [C_S_AXIS_TDATA_WIDTH-1 : 0] S_AXIS_TDATA,

    input wire [(C_S_AXIS_TDATA_WIDTH/8)-1 : 0] S_AXIS_TSTRB,

    input wire  S_AXIS_TLAST,

    input wire  S_AXIS_TVALID
);

    reg [1:0] write_pointer;

    assign S_AXIS_TREADY = 1'b1;

    always @(posedge S_AXIS_ACLK) begin
        if (!S_AXIS_ARESETN) begin

            write_pointer <= 2'd0;
            o_angle       <= 32'd0;
            o_velocity    <= 32'd0;
            o_width       <= 32'd0;
            o_data_valid  <= 1'b0;
        end
        else begin

            o_data_valid <= 1'b0;

            if (S_AXIS_TVALID && S_AXIS_TREADY) begin

                case (write_pointer)
                    2'd0: begin
                        o_angle <= S_AXIS_TDATA;
                        write_pointer <= 2'd1;
                    end

                    2'd1: begin
                        o_velocity <= S_AXIS_TDATA;
                        write_pointer <= 2'd2;
                    end

                    2'd2: begin
                         o_width <= S_AXIS_TDATA;

                         o_data_valid <= 1'b1;

                         write_pointer <= 2'd0;
                     end

                     default: write_pointer <= 2'd0;
                 endcase

                 if (S_AXIS_TLAST) begin
                     write_pointer <= 2'd0;
                 end
             end
         end
     end

endmodule
