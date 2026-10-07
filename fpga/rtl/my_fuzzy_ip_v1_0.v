// Recovered from the project report, PDF pages 107-112.
// AXI configuration/stream wrapper, fuzzy pipeline and two 50 Hz PWM outputs.
`timescale 1ns / 1ps

// AXI-Lite and AXI-Stream clocks must use the same 50 MHz clock domain.
module my_fuzzy_ip_v1_0 #
 (
     parameter integer C_S00_AXI_DATA_WIDTH = 32,
     parameter integer C_S00_AXI_ADDR_WIDTH = 12,
     parameter integer C_S00_AXIS_TDATA_WIDTH = 32
 )
 (

     output wire signed [31:0] o_crisp_angle,
     output wire signed [31:0] o_crisp_width,

     output wire o_pwm_steer,
     output wire o_pwm_speed,

    input wire  s00_axi_aclk,
    input wire  s00_axi_aresetn,
    input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
    input wire [2 : 0] s00_axi_awprot,
    input wire  s00_axi_awvalid,
    output wire  s00_axi_awready,
    input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
    input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
    input wire  s00_axi_wvalid,
    output wire  s00_axi_wready,
    output wire [1 : 0] s00_axi_bresp,
    output wire  s00_axi_bvalid,
    input wire  s00_axi_bready,
    input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
    input wire [2 : 0] s00_axi_arprot,
    input wire  s00_axi_arvalid,
    output wire  s00_axi_arready,
    output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
    output wire [1 : 0] s00_axi_rresp,
    output wire  s00_axi_rvalid,
    input wire  s00_axi_rready,

    input wire  s00_axis_aclk,
    input wire  s00_axis_aresetn,
    output wire  s00_axis_tready,
    input wire [C_S00_AXIS_TDATA_WIDTH-1 : 0] s00_axis_tdata,
    input wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0] s00_axis_tstrb,
    input wire  s00_axis_tlast,
    input wire  s00_axis_tvalid
);

    wire        w_cfg_en;
    wire [11:0] w_cfg_addr;
    wire [31:0] w_cfg_data;

    wire signed [31:0] w_sensor_angle;
    wire signed [31:0] w_sensor_velocity;
    wire signed [31:0] w_sensor_width;
    wire               w_data_valid;

    wire signed [31:0] w_crisp_dc;
    wire signed [31:0] w_crisp_lin;
    wire               w_raw_output_valid;
    wire               w_output_valid;

    // The divider IP has no reset port and retains in-flight transactions.
    // Match the 36-cycle latency checked by package_fuzzy_ip.tcl; suppress
    // stale results for both PWM and AXI readback after a reset.
    localparam integer DIVIDER_LATENCY_CYCLES = 36;
    reg [5:0] divider_flush_remaining;

    always @(posedge s00_axi_aclk or negedge s00_axi_aresetn) begin
        if (!s00_axi_aresetn)
            divider_flush_remaining <= DIVIDER_LATENCY_CYCLES;
        else if (divider_flush_remaining != 0)
            divider_flush_remaining <= divider_flush_remaining - 1'b1;
    end

    assign w_output_valid = s00_axi_aresetn &&
                            (divider_flush_remaining == 0) && w_raw_output_valid;

    // Keep the last complete result while the divider output is not valid.
    // PWM captures this stable target at its next period boundary.
    reg signed [31:0] held_pwm_angle;
    reg signed [31:0] held_pwm_width;

    always @(posedge s00_axi_aclk or negedge s00_axi_aresetn) begin
        if (!s00_axi_aresetn) begin
            held_pwm_angle <= 32'sd0;
            held_pwm_width <= 32'sd0;
        end else if (w_output_valid) begin
            held_pwm_angle <= w_crisp_dc;
            held_pwm_width <= w_crisp_lin;
        end
    end

    assign o_crisp_angle = w_crisp_dc;
    assign o_crisp_width = w_crisp_lin;

    my_fuzzy_ip_slave_lite_v1_0_S00_AXI # (
        .C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
    ) my_fuzzy_ip_slave_lite_v1_0_S00_AXI_inst (

        .i_monitor_angle (w_crisp_dc),
        .i_monitor_width (w_crisp_lin),
        .i_monitor_valid (w_output_valid),

        .o_cfg_en   (w_cfg_en),
        .o_cfg_addr (w_cfg_addr),
        .o_cfg_data (w_cfg_data),

        .S_AXI_ACLK(s00_axi_aclk),
        .S_AXI_ARESETN(s00_axi_aresetn),
        .S_AXI_AWADDR(s00_axi_awaddr),
        .S_AXI_AWPROT(s00_axi_awprot),
        .S_AXI_AWVALID(s00_axi_awvalid),
        .S_AXI_AWREADY(s00_axi_awready),
        .S_AXI_WDATA(s00_axi_wdata),
        .S_AXI_WSTRB(s00_axi_wstrb),
        .S_AXI_WVALID(s00_axi_wvalid),
        .S_AXI_WREADY(s00_axi_wready),
        .S_AXI_BRESP(s00_axi_bresp),
        .S_AXI_BVALID(s00_axi_bvalid),
        .S_AXI_BREADY(s00_axi_bready),
        .S_AXI_ARADDR(s00_axi_araddr),
        .S_AXI_ARPROT(s00_axi_arprot),
        .S_AXI_ARVALID(s00_axi_arvalid),
        .S_AXI_ARREADY(s00_axi_arready),
        .S_AXI_RDATA(s00_axi_rdata),
        .S_AXI_RRESP(s00_axi_rresp),
        .S_AXI_RVALID(s00_axi_rvalid),
        .S_AXI_RREADY(s00_axi_rready)
    );

    my_fuzzy_ip_slave_stream_v1_0_S00_AXIS # (
        .C_S_AXIS_TDATA_WIDTH(C_S00_AXIS_TDATA_WIDTH)
    ) my_fuzzy_ip_slave_stream_v1_0_S00_AXIS_inst (
        .o_angle      (w_sensor_angle),
        .o_velocity   (w_sensor_velocity),
        .o_width      (w_sensor_width),
        .o_data_valid (w_data_valid),
        .S_AXIS_ACLK(s00_axis_aclk),
        .S_AXIS_ARESETN(s00_axis_aresetn),
        .S_AXIS_TREADY(s00_axis_tready),
        .S_AXIS_TDATA(s00_axis_tdata),
        .S_AXIS_TSTRB(s00_axis_tstrb),
        .S_AXIS_TLAST(s00_axis_tlast),
        .S_AXIS_TVALID(s00_axis_tvalid)
    );

    Fuzzy_Control_Unit #(
        .DATA_WIDTH(32),
        .MU_WIDTH(8),
        .SINGLETON_WIDTH(16)
    ) u_fuzzy_core (
        .clk        (s00_axi_aclk),
        .rstn       (s00_axi_aresetn),

        .sensor_angle   (w_sensor_angle),
        .sensor_velocity(w_sensor_velocity),
        .sensor_width   (w_sensor_width),
        .data_valid     (w_data_valid),

        .cfg_en     (w_cfg_en),
        .cfg_addr   (w_cfg_addr),
        .cfg_data   (w_cfg_data),

        .crisp_dc_out   (w_crisp_dc),
        .crisp_lin_out  (w_crisp_lin),
        .output_valid   (w_raw_output_valid)
    );

     PWM_Generator #(
         .CLK_HZ(50000000),
         .REVERSE(0)
     ) u_pwm_steer (
         .deg_in(held_pwm_angle),
         .clk(s00_axi_aclk),
         .rstn(s00_axi_aresetn),
         .pwm_out(o_pwm_steer),
         .nsleep()
     );

     PWM_Generator #(
         .CLK_HZ(50000000),
         .REVERSE(0)
     ) u_pwm_speed (
         .deg_in(held_pwm_width),
         .clk(s00_axi_aclk),
         .rstn(s00_axi_aresetn),
         .pwm_out(o_pwm_speed),
         .nsleep()
     );

endmodule
