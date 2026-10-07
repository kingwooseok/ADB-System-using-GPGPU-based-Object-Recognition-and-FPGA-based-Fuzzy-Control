`timescale 1ns / 1ps
// Board-free integration test. Uses the simulation-only div_gen_0_model.v,
// not the generated AMD divider IP. All configuration uses the AXI-Lite bus;
// sensor samples use the real three-word AXI-Stream interface.
module tb_system;
    reg clk = 0;
    always #10 clk = ~clk; // Actual 50 MHz clock; PWM period is 1,000,000 ticks.
    reg rstn = 0;
    reg [11:0] awaddr = 0, araddr = 0;
    reg [31:0] wdata = 0;
    reg awvalid = 0, wvalid = 0, bready = 0;
    reg arvalid = 0, rready = 0;
    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;
    reg [31:0] tdata = 0;
    reg tlast = 0, tvalid = 0;
    wire tready;
    wire signed [31:0] angle, width;
    wire pwm_steer, pwm_width;

    my_fuzzy_ip_v1_0 dut (
        .o_crisp_angle(angle), .o_crisp_width(width),
        .o_pwm_steer(pwm_steer), .o_pwm_speed(pwm_width),
        .s00_axi_aclk(clk), .s00_axi_aresetn(rstn),
        .s00_axi_awaddr(awaddr), .s00_axi_awprot(3'b0),
        .s00_axi_awvalid(awvalid), .s00_axi_awready(awready),
        .s00_axi_wdata(wdata), .s00_axi_wstrb(4'hf),
        .s00_axi_wvalid(wvalid), .s00_axi_wready(wready),
        .s00_axi_bresp(bresp), .s00_axi_bvalid(bvalid), .s00_axi_bready(bready),
        .s00_axi_araddr(araddr), .s00_axi_arprot(3'b0),
        .s00_axi_arvalid(arvalid), .s00_axi_arready(arready),
        .s00_axi_rdata(rdata), .s00_axi_rresp(rresp),
        .s00_axi_rvalid(rvalid), .s00_axi_rready(rready),
        .s00_axis_aclk(clk), .s00_axis_aresetn(rstn),
        .s00_axis_tready(tready), .s00_axis_tdata(tdata),
        .s00_axis_tstrb(4'hf), .s00_axis_tlast(tlast), .s00_axis_tvalid(tvalid)
    );

    task check;
        input condition;
        input [1023:0] message;
        begin
            if (condition !== 1'b1) $fatal(1, "%0s", message);
        end
    endtask

    integer queued = 0, completed = 0;
    reg signed [31:0] expected_angle [0:31];
    reg signed [31:0] expected_width [0:31];
    always @(posedge clk) begin
        #1;
        if (rstn && dut.w_output_valid) begin
            check(completed < queued, "Unexpected/duplicate full-system result valid");
            if (angle !== expected_angle[completed] || width !== expected_width[completed])
                $fatal(1, "Sample %0d: got (%0d,%0d), expected (%0d,%0d)",
                       completed, angle, width,
                       expected_angle[completed], expected_width[completed]);
            completed = completed + 1;
        end
    end

    task expect_result;
        input signed [31:0] expected_a, expected_w;
        begin
            expected_angle[queued] = expected_a;
            expected_width[queued] = expected_w;
            queued = queued + 1;
        end
    endtask

    task wait_results;
        integer cycles;
        begin
            cycles = 0;
            while (completed != queued && cycles < 160) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            check(completed == queued, "Full-system result timeout");
            // AXI capture and held PWM commands sample valid at the next edge.
            repeat (3) @(negedge clk);
        end
    endtask

    task axi_write;
        input [11:0] address;
        input signed [31:0] value;
        begin
            @(negedge clk);
            awaddr = address; wdata = value;
            awvalid = 1; wvalid = 1; bready = 1;
            @(posedge clk);
            while (!(awready && wready)) @(posedge clk);
            @(negedge clk); awvalid = 0; wvalid = 0;
            while (!bvalid) @(negedge clk);
            check(bresp === 2'b00, "AXI-Lite write response error");
            @(negedge clk); bready = 0;
        end
    endtask

    task axi_read_check;
        input [11:0] address;
        input signed [31:0] expected;
        begin
            @(negedge clk); araddr = address; arvalid = 1;
            @(posedge clk);
            while (!arready) @(posedge clk);
            @(negedge clk); arvalid = 0;
            while (!rvalid) @(negedge clk);
            check(rresp === 2'b00 && rdata === expected, "AXI-Lite full-system readback mismatch");
            repeat (2) begin
                @(negedge clk);
                check(rvalid && rdata === expected, "AXI result changed while read was stalled");
            end
            rready = 1;
            @(negedge clk); rready = 0;
        end
    endtask

    task configure_mf;
        input integer index;
        input signed [31:0] a, b, c, d;
        integer base, rise, fall;
        begin
            base = index * 24;
            rise = 0; fall = 0;
            if (b > a) rise = (255 * 256) / (b - a);
            if (d > c) fall = (255 * 256) / (d - c);
            axi_write(base, a);      axi_write(base + 4, b);
            axi_write(base + 8, c);  axi_write(base + 12, d);
            axi_write(base + 16, rise); axi_write(base + 20, fall);
        end
    endtask

    task configure_firmware;
        integer i;
        begin
            // Same membership functions, rule map and singletons as dma firmware.
            configure_mf(0, -1000, -1000, -650, -300);
            configure_mf(1, -650, -300, -300, 0);
            configure_mf(2, -500, -200, 200, 500);
            configure_mf(3, 0, 300, 300, 650);
            configure_mf(4, 300, 650, 1000, 1000);
            configure_mf(5, -2000, -1000, 1000, 2000);
            configure_mf(6, 2000, 3000, 4000, 5000);
            configure_mf(7, 0, 0, 100, 500);
            configure_mf(8, 300, 400, 1000, 1000);
            for (i = 0; i < 5; i = i + 1) begin
                axi_write(12'h100 + i * 8, 4 - i);
                axi_write(12'h104 + i * 8, 2);
            end
            axi_write(12'h128, 0); axi_write(12'h12c, 1);
            axi_write(12'h200, -50); axi_write(12'h204, -25);
            axi_write(12'h208, 0); axi_write(12'h20c, 25);
            axi_write(12'h210, 50);
            axi_write(12'h214, 60); axi_write(12'h218, -70);
        end
    endtask

    task stream_frame;
        input signed [31:0] a, v, w;
        input integer gap_cycles;
        begin
            @(negedge clk); tdata = a; tvalid = 1; tlast = 0;
            @(posedge clk); check(tready, "Stream receiver not ready");
            #1; check(!dut.w_data_valid, "Frame completed before velocity/width words");
            @(negedge clk);
            if (gap_cycles > 0) begin
                tvalid = 0;
                repeat (gap_cycles) @(negedge clk);
            end
            tdata = v; tvalid = 1;
            @(posedge clk); check(tready, "Stream receiver not ready");
            #1; check(!dut.w_data_valid, "Frame completed before width word");
            @(negedge clk); tdata = w; tlast = 1;
            @(posedge clk); check(tready, "Stream receiver not ready");
            #1;
            check(dut.w_data_valid, "Third stream word did not complete frame");
            check(dut.w_sensor_angle === a && dut.w_sensor_velocity === v &&
                  dut.w_sensor_width === w, "Three stream words decoded incorrectly");
            @(negedge clk); tvalid = 0; tlast = 0;
        end
    endtask

    task sample;
        input signed [31:0] a, w, expected_a, expected_w;
        begin
            expect_result(expected_a, expected_w);
            stream_frame(a, 123, w, 0);
            wait_results;
            axi_read_check(12'h000, expected_a);
            axi_read_check(12'h004, expected_w);
            check(dut.held_pwm_angle === expected_a && dut.held_pwm_width === expected_w,
                  "Valid result was not captured as the PWM command");
        end
    endtask

    time last_steer_rise = 0, last_width_rise = 0;
    integer steer_periods = 0, width_periods = 0;
    always @(posedge pwm_steer or negedge rstn) begin
        if (!rstn) last_steer_rise = 0;
        else begin
            if (last_steer_rise != 0) begin
                check(($time - last_steer_rise) == 20000000,
                      "Steering PWM period changed or a mid-period glitch occurred");
                steer_periods = steer_periods + 1;
            end
            last_steer_rise = $time;
        end
    end
    always @(posedge pwm_width or negedge rstn) begin
        if (!rstn) last_width_rise = 0;
        else begin
            if (last_width_rise != 0) begin
                check(($time - last_width_rise) == 20000000,
                      "Width PWM period changed or a mid-period glitch occurred");
                width_periods = width_periods + 1;
            end
            last_width_rise = $time;
        end
    end

    task pwm_frame_check;
        input integer steer_ticks, width_ticks;
        time start_time;
        begin
            @(posedge pwm_steer);
            start_time = $time;
            #1; check(pwm_width === 1'b1, "PWM channels do not start together");
            fork
                begin
                    @(negedge pwm_steer);
                    if (($time - start_time) != steer_ticks * 20)
                        $fatal(1, "Steering pulse: got %0t ns, expected %0d ticks",
                               $time - start_time, steer_ticks);
                end
                begin
                    @(negedge pwm_width);
                    if (($time - start_time) != width_ticks * 20)
                        $fatal(1, "Width pulse: got %0t ns, expected %0d ticks",
                               $time - start_time, width_ticks);
                end
            join
            $display("PASS: full 50 MHz PWM frame, high ticks (%0d,%0d)", steer_ticks, width_ticks);
            $fflush();
        end
    endtask

    task pending_reset_check;
        input integer delay_cycles;
        input integer send_immediately;
        integer i;
        begin
            configure_firmware;
            sample(-1000, 0, 50, 60);
            // This nonzero result is deliberately cancelled rather than queued.
            stream_frame(1000, 0, 1000, 0);
            repeat (delay_cycles) @(negedge clk);
            rstn = 0;
            // Minimum one-clock reset, including one AXI/stream clock edge.
            @(negedge clk);
            check(dut.held_pwm_angle === 0 && dut.held_pwm_width === 0,
                  "In-flight reset did not clear PWM command");
            rstn = 1;
            if (send_immediately) begin
                // Reset cleared all configuration: singleton outputs are zero.
                // A fresh sample during the flush interval must not be lost.
                expect_result(0, 0);
                stream_frame(0, 0, 0, 0);
                wait_results;
            end
            for (i = 0; i < 48; i = i + 1) begin
                @(negedge clk);
                check(!dut.w_output_valid, "Cancelled divider result escaped after reset");
                check(dut.held_pwm_angle === 0 && dut.held_pwm_width === 0,
                      "Stale in-flight divider result changed reset PWM command");
            end
            axi_read_check(12'h000, 0); axi_read_check(12'h004, 0);
            if (!send_immediately) begin
                expect_result(0, 0);
                stream_frame(0, 0, 0, 0);
                wait_results;
                axi_read_check(12'h000, 0); axi_read_check(12'h004, 0);
            end
        end
    endtask

    initial begin
        repeat (5) @(negedge clk);
        rstn = 1;
        configure_firmware;
        sample(-1000, 0, 50, 60);
        sample(1000, 1000, -50, -70);
        sample(0, 0, 0, 60);
        // Q8 slopes: angle weights 255/127; width weights 95/127.
        // Signed integer weighted means are -3175/382=-8, -3190/222=-14.
        sample(150, 350, -8, -14);
        sample(2000, 1500, 0, 0); // Both sums have no active membership.

        expect_result(50, 60); stream_frame(-1000, 0, 0, 0);
        expect_result(-50, -70); stream_frame(1000, -999, 1000, 0);
        expect_result(0, 60); stream_frame(0, 999, 0, 3);
        wait_results;
        axi_read_check(12'h000, 0); axi_read_check(12'h004, 60);
        $display("PASS: AXI configuration, stream framing/gaps, fuzzy signed results and AXI readback");
        $fflush();

        // Sweep reset across pre-divider, input-adjacent and last in-flight
        // stages. Each reset is one clock, and the following 48 clocks include
        // the divider's entire 36-clock tail and mask-release boundary.
        pending_reset_check(0, 0);
        pending_reset_check(7, 0);
        pending_reset_check(8, 0);
        pending_reset_check(9, 0);
        pending_reset_check(40, 0);
        pending_reset_check(8, 1);
        configure_firmware;
        $display("PASS: in-flight reset/36-clock divider tail, zero readback and immediate new-frame recovery");
        $fflush();

        // Change output singletons through the real bus to exercise motor bounds.
        // Existing arithmetic uses floor(25000/90)=277 ticks/degree, so endpoints
        // are 50,070 and 99,930 ticks, rather than idealized 50,000/100,000.
        axi_write(12'h200, -90); axi_write(12'h210, 90);
        axi_write(12'h214, 0); axi_write(12'h218, 90);
        sample(0, 0, 0, 0);
        pwm_frame_check(75000, 75000);
        axi_write(12'h214, -90);
        sample(-1000, 0, 90, -90);
        pwm_frame_check(99930, 50070);
        sample(1000, 1000, -90, 90);
        pwm_frame_check(50070, 99930);

        axi_write(12'h200, -120); axi_write(12'h210, 120);
        axi_write(12'h214, -120); axi_write(12'h218, 120);
        sample(-1000, 0, 120, -120);
        pwm_frame_check(99930, 50070); // Beyond +/-90 must clamp.

        // An incomplete frame changes the continuously computed raw quotient in
        // the divider model. It must not change the accepted PWM command.
        @(negedge clk); tdata = 1000; tvalid = 1; tlast = 0;
        @(negedge clk); tvalid = 0;
        repeat (120) begin
            @(negedge clk);
            check(!dut.w_output_valid, "Incomplete frame produced a valid result");
            check(dut.held_pwm_angle === 32'sd120 && dut.held_pwm_width === -32'sd120,
                  "Invalid/incomplete sample changed PWM command");
        end
        check(angle === -32'sd120, "Incomplete-frame test did not perturb raw divider output");
        pwm_frame_check(99930, 50070); // Observe a real period with the old command.
        expect_result(-120, 120);
        @(negedge clk); tdata = 0; tvalid = 1;
        @(negedge clk); tdata = 1000; tlast = 1;
        @(negedge clk); tvalid = 0; tlast = 0;
        wait_results;
        axi_read_check(12'h000, -120); axi_read_check(12'h004, 120);
        pwm_frame_check(50070, 99930);
        $display("PASS: incomplete-frame/invalid-output hold and completed-frame PWM update");
        $fflush();

        @(negedge clk); rstn = 0;
        repeat (5) @(negedge clk);
        check(dut.held_pwm_angle === 0 && dut.held_pwm_width === 0,
              "Reset did not clear accepted PWM commands");
        check(pwm_steer === 0 && pwm_width === 0, "Reset did not clear PWM pins");
        rstn = 1;
        pwm_frame_check(75000, 75000);
        check(steer_periods >= 6 && width_periods >= 6, "Full PWM periods were not observed");
        check(completed == queued, "Not all queued samples completed");
        $display("PASS: full-system integration, %0d samples, +/-90 and clamp, reset; divider simulation model only", completed);
        $finish;
    end

    initial begin
        #200000000; // 200 ms of simulated time, not a shortened PWM frequency.
        $fatal(1, "System integration test timeout");
    end
endmodule
