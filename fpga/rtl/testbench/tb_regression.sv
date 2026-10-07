`timescale 1ns / 1ps
module tb_regression;
    reg clk = 0;
    always #10 clk = ~clk;
    reg rstn = 0;

    task automatic check(input bit condition, input string message);
        if (!condition) $fatal(1, "%s", message);
    endtask

    reg signed [31:0] mf_x = 0;
    reg mf_input_valid = 0;
    wire mf_output_valid;
    reg cfg_cs = 0;
    reg [2:0] cfg_addr = 0;
    reg [31:0] cfg_data = 0;
    wire [7:0] mu;
    MF_Core #(.DATA_WIDTH(32)) mf (
        .clk(clk), .rstn(rstn), .x(mf_x),
        .i_valid(mf_input_valid), .o_valid(mf_output_valid),
        .cfg_cs(cfg_cs), .cfg_addr(cfg_addr), .cfg_data(cfg_data),
        .mu_out(mu)
    );

    task automatic configure_mf(input [2:0] addr, input signed [31:0] value);
        @(negedge clk); cfg_cs = 1; cfg_addr = addr; cfg_data = value;
        @(negedge clk); cfg_cs = 0;
    endtask

    task automatic sample_mf(input signed [31:0] value, input [7:0] expected);
        @(negedge clk); mf_x = value; mf_input_valid = 1;
        @(posedge clk); #1; check(!mf_output_valid, "MF valid arrived at stage 1");
        @(negedge clk); mf_x = 10000; mf_input_valid = 0;
        @(posedge clk); #1; check(!mf_output_valid, "MF valid arrived at stage 2");
        @(posedge clk); #1;
        check(mf_output_valid, "MF valid missing at stage 3");
        check(mu === expected, "MF sample and valid are misaligned");
        @(posedge clk); #1; check(!mf_output_valid, "MF valid did not clear");
    endtask

    reg signed [31:0] dividend = 0;
    reg signed [15:0] divisor = 1;
    reg divider_valid = 0;
    wire signed [31:0] quotient;
    wire quotient_valid;
    Divider_Wrapper divider (
        .clk(clk), .dividend(dividend), .divisor(divisor),
        .input_valid(divider_valid), .quotient(quotient),
        .output_valid(quotient_valid)
    );
    task automatic sample_divider(input signed [31:0] n,
                                  input signed [15:0] d,
                                  input signed [31:0] expected);
        @(negedge clk); dividend = n; divisor = d; divider_valid = 1;
        @(negedge clk); divider_valid = 0;
        wait (quotient_valid); #1;
        check(quotient === expected, "Divider result mismatch");
        @(negedge clk);
    endtask

    reg awvalid = 0, wvalid = 0, bready = 0;
    reg arvalid = 0, rready = 0;
    reg [11:0] araddr = 0;
    wire awready, wready, bvalid, arready, rvalid;
    wire [31:0] rdata;
    my_fuzzy_ip_slave_lite_v1_0_S00_AXI axil (
        .S_AXI_ACLK(clk), .S_AXI_ARESETN(rstn),
        .i_monitor_angle(32'sd25), .i_monitor_width(-32'sd70),
        .i_monitor_valid(1'b1), .o_cfg_en(), .o_cfg_addr(), .o_cfg_data(),
        .S_AXI_AWADDR(12'h200), .S_AXI_AWPROT(3'd0),
        .S_AXI_AWVALID(awvalid), .S_AXI_AWREADY(awready),
        .S_AXI_WDATA(32'd25), .S_AXI_WSTRB(4'hf),
        .S_AXI_WVALID(wvalid), .S_AXI_WREADY(wready),
        .S_AXI_BRESP(), .S_AXI_BVALID(bvalid), .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr), .S_AXI_ARPROT(3'd0),
        .S_AXI_ARVALID(arvalid), .S_AXI_ARREADY(arready),
        .S_AXI_RDATA(rdata), .S_AXI_RRESP(),
        .S_AXI_RVALID(rvalid), .S_AXI_RREADY(rready)
    );

    initial begin
        repeat (4) @(negedge clk);
        rstn = 1;
        configure_mf(0, -1000);
        configure_mf(1, -1000);
        configure_mf(2, -650);
        configure_mf(3, -300);
        configure_mf(4, 0);
        configure_mf(5, (255*256)/350);
        sample_mf(-1000, 255);
        sample_mf(-650, 255);
        sample_mf(-300, 0);
        configure_mf(0, 300);
        configure_mf(1, 650);
        configure_mf(2, 1000);
        configure_mf(3, 1000);
        sample_mf(1000, 255);
        sample_divider(1234, 0, 0);
        sample_divider(-2550, 255, -10);

        @(negedge clk); awvalid = 1; wvalid = 1;
        wait (awready && wready);
        @(negedge clk);
        wait (bvalid);
        repeat (5) begin
            @(posedge clk); #1;
            check(!awready && !wready, "AXI write accepted with response pending");
            check(bvalid, "AXI write response lost under backpressure");
        end
        @(negedge clk); awvalid = 0; wvalid = 0; bready = 1;
        @(negedge clk); bready = 0; arvalid = 1;
        wait (rvalid); #1;
        check(rdata === 32'd25, "AXI readback mismatch");
        repeat (5) begin
            @(posedge clk); #1;
            check(!arready, "AXI read accepted with response pending");
            check(rvalid && rdata === 32'd25, "AXI read response changed under backpressure");
        end
        @(negedge clk); arvalid = 0; rready = 1;
        @(negedge clk);
        rready = 0; araddr = 12'h100; arvalid = 1;
        wait (rvalid); #1;
        check(rdata === 32'd0, "AXI configuration address aliased to result register");
        $display("PASS: MF pipeline/shoulder boundaries, divider zero/signed input, AXI backpressure/address decode");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Regression timeout");
    end
endmodule
