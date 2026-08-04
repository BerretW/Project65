// =============================================================
// Integration testbench: aprts_bus + sram_model
// Covers CPU register map, auto-inc, font RAM, audio ports,
// mode/reset, status/ready, and basic SRAM R/W path.
//
// Compatible with:
//   - Intel Quartus Prime / Questa-Intel (ModelSim-Intel)
//   - Icarus Verilog (iverilog + vvp)
// =============================================================
`timescale 1ns / 1ps

module tb_aprts_bus;

    // ---------------------------------------------------------
    // Clock / bus
    // ---------------------------------------------------------
    reg        clk      = 1'b0;
    reg        n_reset  = 1'b0;
    reg        n_mem_w  = 1'b1;
    reg        n_mem_r  = 1'b1;
    reg        lv_cs    = 1'b1;
    reg  [3:0] lv_addr  = 4'h0;
    reg  [7:0] lv_data_drv = 8'h00;
    reg        lv_data_oe  = 1'b0;
    wire [7:0] lv_data;

    assign lv_data = lv_data_oe ? lv_data_drv : 8'hzz;

    // VGA
    wire [2:0] red, green, blue;
    wire       hsync, vsync;

    // SRAM pins
    wire [18:0] sram_addr;
    wire [7:0]  sram_data;
    wire        sram_ce_n, sram_oe_n, sram_we_n;

    // Audio
    wire pcm_bck, pcm_din, pcm_lrck, pcm_sck;

    // 25 MHz
    always #20 clk = ~clk;

    // ---------------------------------------------------------
    // DUT + SRAM
    // ---------------------------------------------------------
    aprts_bus uut (
        .n_reset(n_reset),
        .n_mem_w(n_mem_w),
        .n_mem_r(n_mem_r),
        .lv_cs(lv_cs),
        .clk(clk),
        .lv_addr(lv_addr),
        .lv_data(lv_data),
        .red(red),
        .green(green),
        .blue(blue),
        .hsync(hsync),
        .vsync(vsync),
        .sram_addr(sram_addr),
        .sram_data(sram_data),
        .sram_ce_n(sram_ce_n),
        .sram_oe_n(sram_oe_n),
        .sram_we_n(sram_we_n),
        .pcm_bck(pcm_bck),
        .pcm_din(pcm_din),
        .pcm_lrck(pcm_lrck),
        .pcm_sck(pcm_sck)
    );

    sram_model #(
        .ADDR_WIDTH(19),
        .DATA_WIDTH(8),
        .INIT_VALUE(8'h00)
    ) u_sram (
        .addr(sram_addr),
        .data(sram_data),
        .ce_n(sram_ce_n),
        .oe_n(sram_oe_n),
        .we_n(sram_we_n)
    );

    // ---------------------------------------------------------
    // Test helpers
    // ---------------------------------------------------------
    integer errors;
    integer checks;

    task check;
        input cond;
        input [255:0] msg;
        begin
            checks = checks + 1;
            if (!cond) begin
                $display("FAIL @%0t: %0s", $time, msg);
                errors = errors + 1;
            end
        end
    endtask

    // 6502-style write cycle: CS+!WE asserted for 2 clocks (edge detect)
    task cpu_write;
        input [3:0] a;
        input [7:0] d;
        begin
            @(negedge clk);
            lv_addr     = a;
            lv_data_drv = d;
            lv_data_oe  = 1'b1;
            n_mem_r     = 1'b1;
            n_mem_w     = 1'b0;
            lv_cs       = 1'b0;
            // hold active across at least one rising edge for write_en
            @(posedge clk);
            @(negedge clk);
            lv_cs       = 1'b1;
            n_mem_w     = 1'b1;
            lv_data_oe  = 1'b0;
            lv_data_drv = 8'h00;
            // allow write_req / auto-inc to settle
            @(posedge clk);
            @(posedge clk);
        end
    endtask

    task cpu_read;
        input  [3:0] a;
        output [7:0] d;
        begin
            @(negedge clk);
            lv_addr    = a;
            lv_data_oe = 1'b0;
            n_mem_w    = 1'b1;
            n_mem_r    = 1'b0;
            lv_cs      = 1'b0;
            @(posedge clk);
            #1;
            d = lv_data;
            @(negedge clk);
            lv_cs   = 1'b1;
            n_mem_r = 1'b1;
            @(posedge clk);
        end
    endtask

    task cpu_read_expect;
        input [3:0] a;
        input [7:0] exp;
        input [255:0] msg;
        reg [7:0] got;
        begin
            cpu_read(a, got);
            if (got !== exp) begin
                $display("FAIL @%0t: %0s (addr=%h exp=%02h got=%02h)",
                         $time, msg, a, exp, got);
                errors = errors + 1;
            end
            checks = checks + 1;
        end
    endtask

    task wait_ready;
        integer guard;
        reg [7:0] st;
        begin
            guard = 0;
            cpu_read(4'hF, st);
            while ((st[0] !== 1'b1) && (guard < 2000000)) begin
                cpu_read(4'hF, st);
                guard = guard + 1;
            end
            check(st[0] === 1'b1, "wait_ready timeout");
        end
    endtask

    task set_addr24;
        input [7:0] hi;
        input [7:0] mid;
        input [7:0] lo;
        begin
            cpu_write(4'h1, hi);
            cpu_write(4'h2, mid);
            cpu_write(4'h3, lo);
        end
    endtask

    // ---------------------------------------------------------
    // Tests
    // ---------------------------------------------------------
    reg [7:0] rdat;
    reg [7:0] r_hi, r_mid, r_lo;
    integer i;

    initial begin
        errors = 0;
        checks = 0;
        $display("========================================");
        $display(" tb_aprts_bus — APARTS_BUS RTL tests");
        $display("========================================");

        // Power-on
        n_reset = 1'b0;
        lv_cs   = 1'b1;
        n_mem_w = 1'b1;
        n_mem_r = 1'b1;
        repeat (10) @(posedge clk);
        n_reset = 1'b1;
        repeat (5) @(posedge clk);

        // -----------------------------------------------------
        // T1: default register values
        // -----------------------------------------------------
        $display("-- T1 defaults");
        cpu_read_expect(4'h0, 8'h00, "bg default 0");
        cpu_read_expect(4'h1, 8'h00, "addr_hi default 0");
        cpu_read_expect(4'h2, 8'h00, "addr_mid default 0");
        cpu_read_expect(4'h3, 8'h00, "addr_lo default 0");
        cpu_read_expect(4'hD, 8'h00, "mode default 0");
        cpu_read_expect(4'hF, 8'h01, "status ready");

        // -----------------------------------------------------
        // T2: bg / mode / address R/W
        // -----------------------------------------------------
        $display("-- T2 register R/W");
        cpu_write(4'h0, 8'hE4); // bright-ish RGB
        cpu_read_expect(4'h0, 8'hE4, "bg R/W");

        cpu_write(4'hD, 8'h01); // text mode
        cpu_read_expect(4'hD, 8'h01, "mode text 01");

        set_addr24(8'h05, 8'hAA, 8'h55);
        cpu_read_expect(4'h1, 8'h05, "addr_hi R/W");
        cpu_read_expect(4'h2, 8'hAA, "addr_mid R/W");
        cpu_read_expect(4'h3, 8'h55, "addr_lo R/W");

        // -----------------------------------------------------
        // T3: graphics SRAM write + auto-increment + readback
        // -----------------------------------------------------
        $display("-- T3 SRAM write / auto-inc / read");
        cpu_write(4'hD, 8'h00); // graphics
        set_addr24(8'h00, 8'h00, 8'h10);
        wait_ready;

        cpu_write(4'h4, 8'hA5);
        wait_ready;
        // address should have advanced to 0x11
        cpu_read(4'h1, r_hi);
        cpu_read(4'h2, r_mid);
        cpu_read(4'h3, r_lo);
        check({r_hi[2:0], r_mid, r_lo} == 19'h00011, "auto-inc after data write");

        // Peek model memory at written address
        check(u_sram.peek(19'h00010) === 8'hA5, "SRAM model got 0xA5 @0x10");

        // Sequential burst
        set_addr24(8'h00, 8'h01, 8'h00);
        for (i = 0; i < 8; i = i + 1) begin
            wait_ready;
            cpu_write(4'h4, i[7:0] + 8'h30);
        end
        wait_ready;
        for (i = 0; i < 8; i = i + 1) begin
            check(u_sram.peek(19'h00100 + i) === (i[7:0] + 8'h30),
                  "burst write pattern");
        end

        // CPU read-back via port 4 (set address, read)
        // Note: read does not auto-inc in RTL
        set_addr24(8'h00, 8'h00, 8'h10);
        // Ensure not in blanking conflict: force by writing during safe window
        // Multiple reads — accept value when OE path active
        begin : rdback
            integer tries;
            reg ok;
            ok = 0;
            for (tries = 0; tries < 64; tries = tries + 1) begin
                cpu_read(4'h4, rdat);
                if (rdat === 8'hA5)
                    ok = 1;
            end
            check(ok, "CPU readback port4 == 0xA5");
        end

        // -----------------------------------------------------
        // T4: font mode 0x0D write/read
        // -----------------------------------------------------
        $display("-- T4 font RAM");
        cpu_write(4'hD, 8'h0D);
        // font_addr = {addr_hi[6:0], addr_mid[2:0]}
        // choose char 1 row 0 => hi=1, mid=0
        set_addr24(8'h01, 8'h00, 8'h00);
        cpu_write(4'h4, 8'h3C); // does NOT set write_req / no SRAM
        // read needs 1-cycle registered font_read_data
        cpu_read(4'h4, rdat);
        cpu_read(4'h4, rdat);
        check(rdat === 8'h3C, "font RAM write/read 0x3C");

        // second glyph row
        set_addr24(8'h01, 8'h01, 8'h00);
        cpu_write(4'h4, 8'h5A);
        cpu_read(4'h4, rdat);
        cpu_read(4'h4, rdat);
        check(rdat === 8'h5A, "font RAM second row");

        // address must NOT auto-inc in font mode (write_req suppressed)
        cpu_read_expect(4'h1, 8'h01, "font mode no addr_hi change");
        cpu_read_expect(4'h2, 8'h01, "font mode no addr_mid change");

        // -----------------------------------------------------
        // T5: audio ports 5/6
        // -----------------------------------------------------
        $display("-- T5 audio");
        cpu_write(4'h5, 8'h00);
        cpu_write(4'h6, 8'h11); // freq_lo_0, auto-inc -> 1
        cpu_write(4'h6, 8'h22); // freq_hi_0
        cpu_write(4'h6, 8'h33); // vol_0
        cpu_read_expect(4'h5, 8'h03, "audio auto-inc after 3 writes");

        cpu_write(4'h5, 8'h00);
        cpu_read_expect(4'h6, 8'h11, "audio freq_lo_0");
        cpu_write(4'h5, 8'h01);
        cpu_read_expect(4'h6, 8'h22, "audio freq_hi_0");
        cpu_write(4'h5, 8'h02);
        cpu_read_expect(4'h6, 8'h33, "audio vol_0");

        // ctrl + gate
        cpu_write(4'h5, 8'h0C);
        cpu_write(4'h6, 8'h12); // wave=2 saw, ADSR off, gate on
        cpu_write(4'h5, 8'h0C);
        cpu_read_expect(4'h6, 8'h12, "audio ctrl0");

        // -----------------------------------------------------
        // T6: blank mode 0x0F forces black RGB during video
        // -----------------------------------------------------
        $display("-- T6 blank mode");
        cpu_write(4'hD, 8'h0F);
        // wait until counters in active area if possible
        begin : blank_chk
            integer t;
            reg saw_black;
            saw_black = 0;
            for (t = 0; t < 2000; t = t + 1) begin
                @(posedge clk);
                if (red === 3'b000 && green === 3'b000 && blue === 3'b000)
                    saw_black = 1;
            end
            check(saw_black, "mode 0x0F produces black");
        end

        // -----------------------------------------------------
        // T7: HW reset via mode 0x0E
        // -----------------------------------------------------
        $display("-- T7 HW reset 0x0E");
        cpu_write(4'h0, 8'hFF);
        set_addr24(8'h07, 8'h77, 8'h77);
        cpu_write(4'hD, 8'h0E);
        // one cycle pulse; then mode stays 0x0E as written
        @(posedge clk);
        @(posedge clk);
        cpu_read_expect(4'h0, 8'h00, "reset clears bg");
        cpu_read_expect(4'h1, 8'h00, "reset clears addr_hi");
        cpu_read_expect(4'h2, 8'h00, "reset clears addr_mid");
        cpu_read_expect(4'h3, 8'h00, "reset clears addr_lo");
        // mode register itself was written 0x0E
        cpu_read_expect(4'hD, 8'h0E, "mode holds 0x0E after reset cmd");

        // restore graphics
        cpu_write(4'hD, 8'h00);

        // -----------------------------------------------------
        // T8: clear engine start + busy/ready handshake
        // (full clear is huge — only check busy asserts then
        //  force-finish by hierarchical poke is not possible;
        //  instead verify busy goes 1 and ready 0, then stop early
        //  by issuing HW reset which clears clear_busy)
        // -----------------------------------------------------
        $display("-- T8 clear busy handshake");
        wait_ready;
        cpu_write(4'hF, 8'h01); // start clear
        // Immediately status should show not ready
        begin : clr_chk
            reg [7:0] st;
            integer t;
            reg saw_busy;
            saw_busy = 0;
            for (t = 0; t < 32; t = t + 1) begin
                cpu_read(4'hF, st);
                if (st[0] === 1'b0)
                    saw_busy = 1;
            end
            check(saw_busy, "clear sets addr_ready=0");
        end
        // Abort clear via HW reset so sim stays fast
        cpu_write(4'hD, 8'h0E);
        @(posedge clk);
        @(posedge clk);
        wait_ready;
        cpu_read_expect(4'hF, 8'h01, "ready after reset aborts clear");

        // short clear progress: ensure WE pulses while busy
        // (re-start and observe a few writes into model)
        cpu_write(4'hD, 8'h00);
        u_sram.poke(19'h00000, 8'hFF);
        u_sram.poke(19'h00001, 8'hFF);
        cpu_write(4'hF, 8'h01);
        // wait enough clocks for first few clear addresses
        repeat (50) @(posedge clk);
        check(u_sram.peek(19'h00000) === 8'h00, "clear wrote 0 @0");
        // abort again
        cpu_write(4'hD, 8'h0E);
        @(posedge clk);
        @(posedge clk);

        // -----------------------------------------------------
        // T9: VGA timing alive (hsync toggles)
        // -----------------------------------------------------
        $display("-- T9 VGA sync activity");
        begin : sync_chk
            integer t, h_edges;
            reg prev;
            h_edges = 0;
            prev = hsync;
            for (t = 0; t < 2000; t = t + 1) begin
                @(posedge clk);
                if (hsync !== prev)
                    h_edges = h_edges + 1;
                prev = hsync;
            end
            check(h_edges > 0, "hsync toggles");
        end

        // -----------------------------------------------------
        // T10: CS inactive — bus must not drive / no write
        // -----------------------------------------------------
        $display("-- T10 inactive CS");
        set_addr24(8'h00, 8'h02, 8'h00);
        u_sram.poke(19'h00200, 8'hBE);
        @(negedge clk);
        lv_addr     = 4'h4;
        lv_data_drv = 8'h11;
        lv_data_oe  = 1'b1;
        n_mem_w     = 1'b0;
        lv_cs       = 1'b1; // inactive
        @(posedge clk);
        @(negedge clk);
        n_mem_w     = 1'b1;
        lv_data_oe  = 1'b0;
        @(posedge clk);
        check(u_sram.peek(19'h00200) === 8'hBE, "no write when CS high");

        // -----------------------------------------------------
        // Done
        // -----------------------------------------------------
        $display("========================================");
        if (errors == 0)
            $display(" RESULT: PASS  (%0d checks)", checks);
        else
            $display(" RESULT: FAIL  (%0d errors / %0d checks)", errors, checks);
        $display("========================================");
        $finish;
    end

    // Safety timeout
    initial begin
        #50_000_000; // 50 ms sim time
        $display("TIMEOUT");
        errors = errors + 1;
        $finish;
    end

endmodule
