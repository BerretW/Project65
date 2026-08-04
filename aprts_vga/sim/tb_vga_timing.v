// =============================================================
// Unit testbench: vga_timing
// Quartus / ModelSim / iverilog
// =============================================================
`timescale 1ns / 1ps

module tb_vga_timing;

    reg clk = 1'b0;
    reg reset = 1'b1;
    wire [9:0] h_cnt;
    wire [9:0] v_cnt;
    wire hsync;
    wire vsync;
    wire video_on;

    // 25 MHz pixel clock
    always #20 clk = ~clk;

    vga_timing uut (
        .clk(clk),
        .reset(reset),
        .h_cnt(h_cnt),
        .v_cnt(v_cnt),
        .hsync(hsync),
        .vsync(vsync),
        .video_on(video_on)
    );

    integer errors;
    integer hsync_low_count;
    integer vsync_low_count;
    integer frames;
    reg hsync_prev;
    reg vsync_prev;
    integer i;

    task check;
        input cond;
        input [255:0] msg;
        begin
            if (!cond) begin
                $display("FAIL: %0s (t=%0t h=%0d v=%0d)", msg, $time, h_cnt, v_cnt);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        hsync_low_count = 0;
        vsync_low_count = 0;
        frames = 0;
        hsync_prev = 1'b1;
        vsync_prev = 1'b1;

        $display("=== tb_vga_timing start ===");

        // Reset
        repeat (5) @(posedge clk);
        reset = 1'b0;
        @(posedge clk);

        check(h_cnt == 0, "h_cnt reset to 0");
        check(v_cnt == 0, "v_cnt reset to 0");
        check(video_on == 1'b1, "video_on at (0,0)");

        // Walk one full line: 800 pixels (0..799)
        for (i = 0; i < 800; i = i + 1) begin
            @(posedge clk);
            #1;
            check(h_cnt == i, "h_cnt increments");
            if (i < 640)
                check(video_on == 1'b1, "video_on active area");
            else if (v_cnt == 0)
                check(video_on == 1'b0, "video_on blanking");

            // HSYNC active low for h in [656,752)
            if (i >= 656 && i < 752)
                check(hsync == 1'b0, "hsync low in pulse");
            else
                check(hsync == 1'b1, "hsync high outside pulse");
        end

        // After 800 clocks, h wraps and v increments
        @(posedge clk);
        #1;
        check(h_cnt == 0, "h_cnt wrap");
        check(v_cnt == 1, "v_cnt after one line");

        // Run one full frame: leave (0,0), then wait until wrap back
        while (!(h_cnt == 0 && v_cnt == 0)) @(posedge clk);
        @(posedge clk); // leave origin
        begin : wait_frame
            integer guard;
            guard = 0;
            while (!(h_cnt == 0 && v_cnt == 0) && guard < 800*525 + 100) begin
                @(posedge clk);
                #1;
                if (hsync_prev && !hsync)
                    hsync_low_count = hsync_low_count + 1;
                if (vsync_prev && !vsync)
                    vsync_low_count = vsync_low_count + 1;
                hsync_prev = hsync;
                vsync_prev = vsync;
                guard = guard + 1;
            end
            check(h_cnt == 0 && v_cnt == 0, "completed one full frame");
            check(guard >= 800*525 - 5, "frame length ~800*525 clocks");
        end

        check(hsync_low_count >= 520, "hsync pulses ~once per line");
        check(vsync_low_count == 1, "one vsync falling edge per frame");

        // Soft reset mid-frame
        reset = 1'b1;
        @(posedge clk);
        #1;
        check(h_cnt == 0 && v_cnt == 0, "reset clears counters");
        reset = 1'b0;

        if (errors == 0)
            $display("=== tb_vga_timing PASS ===");
        else
            $display("=== tb_vga_timing FAIL (%0d errors) ===", errors);

        $finish;
    end

endmodule
