// =============================================================
// Unit testbench: aprts_audio (register map + auto-inc + I2S clocks)
// =============================================================
`timescale 1ns / 1ps

module tb_aprts_audio;

    reg clk = 1'b0;
    reg reset = 1'b1;
    reg write_en = 1'b0;
    reg [3:0] lv_addr = 4'h0;
    reg [7:0] lv_data = 8'h00;
    wire [7:0] audio_read_val;
    wire pcm_bck, pcm_din, pcm_lrck, pcm_sck;

    always #20 clk = ~clk; // 25 MHz

    aprts_audio uut (
        .clk(clk),
        .reset(reset),
        .write_en(write_en),
        .lv_addr(lv_addr),
        .lv_data(lv_data),
        .audio_read_val(audio_read_val),
        .pcm_bck(pcm_bck),
        .pcm_din(pcm_din),
        .pcm_lrck(pcm_lrck),
        .pcm_sck(pcm_sck)
    );

    integer errors;

    task check;
        input cond;
        input [255:0] msg;
        begin
            if (!cond) begin
                $display("FAIL: %0s (t=%0t got=%02h)", msg, $time, audio_read_val);
                errors = errors + 1;
            end
        end
    endtask

    task bus_write;
        input [3:0] a;
        input [7:0] d;
        begin
            @(negedge clk);
            lv_addr  = a;
            lv_data  = d;
            write_en = 1'b1;
            @(negedge clk);
            write_en = 1'b0;
            lv_data  = 8'h00;
        end
    endtask

    task bus_read_expect;
        input [3:0] a;
        input [7:0] exp;
        input [255:0] msg;
        begin
            @(negedge clk);
            lv_addr = a;
            #1;
            check(audio_read_val === exp, msg);
        end
    endtask

    integer i;
    reg [7:0] exp_seq [0:5];

    initial begin
        errors = 0;
        $display("=== tb_aprts_audio start ===");

        repeat (4) @(posedge clk);
        reset = 1'b0;
        @(posedge clk);

        // Default aud_addr = 0
        bus_read_expect(4'h5, 8'h00, "aud_addr default 0");

        // Select index 0x0C (ctrl0) and write square+gate
        bus_write(4'h5, 8'h0C);
        bus_read_expect(4'h5, 8'h0C, "aud_addr set 0x0C");
        bus_write(4'h6, 8'h10); // gate only, no ADSR, wave=0
        // Auto-inc after write to 0x0D
        bus_read_expect(4'h5, 8'h0D, "aud_addr auto-inc to 0x0D");

        // Write sequential channel0 registers via auto-inc
        bus_write(4'h5, 8'h00);
        exp_seq[0] = 8'h34; // freq lo
        exp_seq[1] = 8'h12; // freq hi
        exp_seq[2] = 8'h7F; // vol
        exp_seq[3] = 8'hAA; // ch1 freq lo
        exp_seq[4] = 8'h55; // ch1 freq hi
        exp_seq[5] = 8'h10; // ch1 vol

        for (i = 0; i < 6; i = i + 1)
            bus_write(4'h6, exp_seq[i]);

        check(audio_read_val !== 8'hxx, "bus alive");

        // Verify by re-selecting each index
        for (i = 0; i < 6; i = i + 1) begin
            bus_write(4'h5, i[7:0]);
            bus_read_expect(4'h6, exp_seq[i], "audio reg R/W");
        end

        // Wrap: select 0x17, write, expect aud_addr -> 0
        bus_write(4'h5, 8'h17);
        bus_write(4'h6, 8'h99);
        bus_read_expect(4'h5, 8'h00, "aud_addr wrap 0x17->0");
        bus_write(4'h5, 8'h17);
        bus_read_expect(4'h6, 8'h99, "adsr_sr_3 stored");

        // Soft reset clears regs
        reset = 1'b1;
        @(posedge clk);
        @(posedge clk);
        reset = 1'b0;
        @(posedge clk);
        bus_write(4'h5, 8'h00);
        bus_read_expect(4'h6, 8'h00, "reset clears freq_lo_0");
        bus_read_expect(4'h5, 8'h00, "reset clears aud_addr");

        // I2S divider produces toggling clocks eventually
        begin : i2s_check
            integer toggles_bck;
            integer toggles_lrck;
            reg prev_bck;
            reg prev_lrck;
            toggles_bck = 0;
            toggles_lrck = 0;
            prev_bck = pcm_bck;
            prev_lrck = pcm_lrck;
            repeat (2048) begin
                @(posedge clk);
                if (pcm_bck !== prev_bck)
                    toggles_bck = toggles_bck + 1;
                if (pcm_lrck !== prev_lrck)
                    toggles_lrck = toggles_lrck + 1;
                prev_bck = pcm_bck;
                prev_lrck = pcm_lrck;
            end
            // pcm_sck is tied to 0 in RTL (MCLK unused / external)
            check(toggles_bck > 0, "pcm_bck toggles");
            check(toggles_lrck > 0, "pcm_lrck toggles");
        end

        if (errors == 0)
            $display("=== tb_aprts_audio PASS ===");
        else
            $display("=== tb_aprts_audio FAIL (%0d errors) ===", errors);

        $finish;
    end

endmodule
