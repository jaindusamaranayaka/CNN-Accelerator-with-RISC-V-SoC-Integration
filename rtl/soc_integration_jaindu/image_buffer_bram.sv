`timescale 1ns / 1ps

module image_buffer_bram #(
    parameter int DEPTH = 1024
)(
    input  logic clk,
    input  logic [31:0] a_addr,
    input  logic [31:0] a_wdata,
    input  logic [ 3:0] a_wstrb,
    input  logic        a_en,
    output logic [31:0] a_rdata,

    input  logic [13:0] b_addr,
    output logic [31:0] b_rdata
);
    logic [31:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (a_en) begin
            if (a_wstrb[0]) mem[a_addr[13:2]][ 7: 0] <= a_wdata[ 7: 0];
            if (a_wstrb[1]) mem[a_addr[13:2]][15: 8] <= a_wdata[15: 8];
            if (a_wstrb[2]) mem[a_addr[13:2]][23:16] <= a_wdata[23:16];
            if (a_wstrb[3]) mem[a_addr[13:2]][31:24] <= a_wdata[31:24];
            a_rdata <= mem[a_addr[13:2]];
        end
    end

    always_ff @(posedge clk) begin
        b_rdata <= mem[b_addr];
    end
endmodule
