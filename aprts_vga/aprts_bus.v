// =============================================================
// APARTS_BUS - VGA & SRAM CONTROLLER FOR 6502 BUS
// =============================================================

module aprts_bus (
    input n_reset,
    input n_mem_w,
    input n_mem_r,
    input lv_cs,
    input clk,
    input [3:0] lv_addr,
    inout [7:0] lv_data,

    output reg [2:0] red,
    output reg [2:0] green,
    output reg [2:0] blue,
    output reg hsync,
    output reg vsync,

    output [18:0] sram_addr,
    inout  [7:0]  sram_data,
    output        sram_ce_n,
    output        sram_oe_n,
    output        sram_we_n
);

    reg [7:0] reg_bg_color = 8'h00;
    reg [7:0] addr_hi      = 8'h00;
    reg [7:0] addr_mid     = 8'h00;
    reg [7:0] addr_lo      = 8'h00;
    reg [7:0] write_val    = 8'h00;

    reg clear_busy  = 1'b0;
    reg write_req   = 1'b0;
    reg clear_tick  = 1'b0;
    reg [18:0] clear_ptr = 19'h0;

    localparam CLEAR_LAST_ADDR = 19'h4AFFF;
    wire [18:0] cpu_addr_full = {addr_hi[2:0], addr_mid, addr_lo};

    reg [9:0] h_cnt = 0;
    reg [9:0] v_cnt = 0;
    wire video_on = (h_cnt < 640) && (v_cnt < 480);

    reg [18:0] vga_addr = 0;

    always @(posedge clk) begin
        if (h_cnt < 799) begin
            h_cnt <= h_cnt + 1;
        end else begin
            h_cnt <= 0;
            if (v_cnt < 524) begin
                v_cnt <= v_cnt + 1;
            end else begin
                v_cnt <= 0;
            end
        end

        hsync <= ~((h_cnt >= 656) && (h_cnt < 752));
        vsync <= ~((v_cnt >= 490) && (v_cnt < 492));
    end

    always @(posedge clk) begin
        if (h_cnt == 0 && v_cnt == 0) begin
            vga_addr <= 0;
        end else if (video_on) begin
            vga_addr <= vga_addr + 1;
        end
    end

    always @(posedge clk) begin
        if (!lv_cs && !n_mem_w) begin
            case (lv_addr)
                4'h0: reg_bg_color <= lv_data;
                4'h1: addr_hi      <= lv_data;
                4'h2: addr_mid     <= lv_data;
                4'h3: addr_lo      <= lv_data;
                4'h4: begin
                    write_req <= 1'b1;
                    write_val <= lv_data;
                end
                4'hF: begin
                    clear_busy <= 1'b1;
                    clear_ptr  <= 19'h0;
                    clear_tick <= 1'b0;
                end
            endcase
        end

        if (clear_busy) begin
            clear_tick <= ~clear_tick;
            if (clear_tick) begin
                if (clear_ptr == CLEAR_LAST_ADDR) begin
                    clear_busy <= 1'b0;
                end else begin
                    clear_ptr <= clear_ptr + 1'b1;
                end
            end
        end

        if (write_req && !video_on && !clear_busy) begin
            write_req <= 1'b0;
            {addr_hi[2:0], addr_mid, addr_lo} <= cpu_addr_full + 1'b1;
        end
    end

    assign sram_ce_n = 1'b0;
    assign sram_oe_n = !((video_on && !clear_busy) || (!lv_cs && !n_mem_r && lv_addr == 4'h4));
    assign sram_we_n = !((clear_busy && !clear_tick) || (write_req && !video_on && !clear_busy));

    assign sram_addr = clear_busy ? clear_ptr : (video_on ? vga_addr : cpu_addr_full);
    assign sram_data = (!sram_we_n) ? (clear_busy ? 8'h00 : write_val) : 8'bz;

    always @(posedge clk) begin
        if (video_on && !clear_busy) begin
            if (sram_data == 8'h00) begin
                red   <= reg_bg_color[7:5];
                green <= reg_bg_color[4:2];
                blue  <= {reg_bg_color[1:0], 1'b0};
            end else begin
                red   <= sram_data[7:5];
                green <= sram_data[4:2];
                blue  <= {sram_data[1:0], 1'b0};
            end
        end else begin
            red <= 3'b000;
            green <= 3'b000;
            blue <= 3'b000;
        end
    end

    wire addr_ready = !clear_busy && !write_req;
    reg [7:0] internal_read_val;

    always @(*) begin
        case (lv_addr)
            4'h0: internal_read_val = reg_bg_color;
            4'h1: internal_read_val = addr_hi;
            4'h2: internal_read_val = addr_mid;
            4'h3: internal_read_val = addr_lo;
            4'h4: internal_read_val = sram_data;
            4'hF: internal_read_val = {7'b0, addr_ready};
            default: internal_read_val = 8'h00;
        endcase
    end

    assign lv_data = (!lv_cs && !n_mem_r) ? internal_read_val : 8'bz;

endmodule