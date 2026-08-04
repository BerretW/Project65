// =============================================================
// Asynchronous SRAM behavioural model (512 KB, 8-bit)
// Suitable for functional RTL simulation (ModelSim / iverilog)
// =============================================================
`timescale 1ns / 1ps

module sram_model #(
    parameter ADDR_WIDTH = 19,
    parameter DATA_WIDTH = 8
) (
    input  [ADDR_WIDTH-1:0] addr,
    inout  [DATA_WIDTH-1:0] data,
    input                   ce_n,
    input                   oe_n,
    input                   we_n
);

    localparam DEPTH = (1 << ADDR_WIDTH);

    // Uninitialized X by default — faster elaborace než smyčka 512 KB
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [DATA_WIDTH-1:0] dout;
    reg we_n_d;

    initial begin
        dout   = {DATA_WIDTH{1'bz}};
        we_n_d = 1'b1;
    end

    // Capture write on rising edge of we_n (end of write pulse)
    always @(*) begin
        // level-sensitive write while WE low (matches async SRAM + simple RTL)
        if (!ce_n && !we_n)
            mem[addr] = data;
    end

    always @(*) begin
        if (!ce_n && !oe_n && we_n)
            dout = mem[addr];
        else
            dout = {DATA_WIDTH{1'bz}};
    end

    assign data = dout;

    function [DATA_WIDTH-1:0] peek;
        input [ADDR_WIDTH-1:0] a;
        begin
            peek = mem[a];
        end
    endfunction

    task poke;
        input [ADDR_WIDTH-1:0] a;
        input [DATA_WIDTH-1:0] d;
        begin
            mem[a] = d;
        end
    endtask

endmodule
