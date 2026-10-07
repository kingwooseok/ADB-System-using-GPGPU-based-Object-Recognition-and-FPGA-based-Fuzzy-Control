// Recovered from the project report, PDF pages 113-117.
// Full-word configuration writes and sample-and-hold result readback.
`timescale 1ns / 1ps

module my_fuzzy_ip_slave_lite_v1_0_S00_AXI #
(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 12
)
(

    input wire signed [31:0] i_monitor_angle,
    input wire signed [31:0] i_monitor_width,
    input wire               i_monitor_valid,

    output wire        o_cfg_en,
    output wire [11:0] o_cfg_addr,
    output wire [31:0] o_cfg_data,

    input wire  S_AXI_ACLK,
    input wire  S_AXI_ARESETN,
    input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
    input wire [2 : 0] S_AXI_AWPROT,
    input wire  S_AXI_AWVALID,
    output wire  S_AXI_AWREADY,
    input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
    input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
    input wire  S_AXI_WVALID,
    output wire  S_AXI_WREADY,
    output wire [1 : 0] S_AXI_BRESP,
    output wire  S_AXI_BVALID,
    input wire  S_AXI_BREADY,
    input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
    input wire [2 : 0] S_AXI_ARPROT,
    input wire  S_AXI_ARVALID,
    output wire  S_AXI_ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
    output wire [1 : 0] S_AXI_RRESP,
    output wire  S_AXI_RVALID,
    input wire  S_AXI_RREADY
);

    reg axi_awready;
    reg axi_wready;
    reg axi_bvalid;
    reg axi_arready;
    reg axi_rvalid;
    reg [C_S_AXI_DATA_WIDTH-1 : 0] axi_rdata;

    reg [C_S_AXI_ADDR_WIDTH-1 : 0] axi_awaddr;
    reg [C_S_AXI_ADDR_WIDTH-1 : 0] axi_araddr;

    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = 2'b00;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = 2'b00;
    assign S_AXI_RVALID  = axi_rvalid;

    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_awready <= 1'b0;
            axi_wready  <= 1'b0;
            axi_bvalid  <= 1'b0;
            axi_awaddr  <= 0;
        end
        else begin
            if (~axi_awready && ~axi_bvalid && S_AXI_AWVALID && S_AXI_WVALID) begin
                axi_awready <= 1'b1;
                axi_awaddr  <= S_AXI_AWADDR;
            end else begin
                axi_awready <= 1'b0;
            end

            if (~axi_wready && ~axi_bvalid && S_AXI_WVALID && S_AXI_AWVALID) begin
                axi_wready <= 1'b1;
            end else begin
                axi_wready <= 1'b0;
            end

            if (axi_awready && axi_wready && ~axi_bvalid) begin
                axi_bvalid <= 1'b1;
            end else if (S_AXI_BREADY && axi_bvalid) begin
                axi_bvalid <= 1'b0;
            end
        end
    end

    wire slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;
    assign o_cfg_en   = slv_reg_wren;
    assign o_cfg_data = S_AXI_WDATA;
    assign o_cfg_addr = axi_awaddr[11:0];

    reg signed [31:0] captured_angle;
    reg signed [31:0] captured_width;

    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            captured_angle <= 32'd0;
            captured_width <= 32'd0;
        end
        else begin

            if (i_monitor_valid == 1'b1) begin
                captured_angle <= i_monitor_angle;
                captured_width <= i_monitor_width;
            end
        end
    end

    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_arready <= 1'b0;
            axi_rvalid  <= 1'b0;
            axi_araddr  <= 0;
            axi_rdata   <= 0;
        end
        else begin

            if (~axi_arready && ~axi_rvalid && S_AXI_ARVALID) begin
                axi_arready <= 1'b1;
                axi_araddr  <= S_AXI_ARADDR;
            end else begin
                axi_arready <= 1'b0;
             end

             if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
                 axi_rvalid <= 1'b1;

                 case (axi_araddr)
                     12'h000: axi_rdata <= captured_angle;
                     12'h004: axi_rdata <= captured_width;
                     default: axi_rdata <= 32'd0;
                 endcase

             end else if (axi_rvalid && S_AXI_RREADY) begin
                 axi_rvalid <= 1'b0;
             end
         end
     end

endmodule
