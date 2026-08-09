`timescale 1ns / 1ps

module lineBuffer(
    input logic clk,
    input logic rstn,
    input logic wr_en,
    input logic [7:0] data_in,
    output logic [7:0] data_out
);

    logic [7:0] buffer [8:0];

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            buffer <= '{default : '0};
        end else if (wr_en) begin
            for (int i = 8; i > 0; i--) begin
                buffer[i] <= buffer[i-1];
            end
            buffer[0] <= data_in;
        end
    end

    assign data_out = buffer[8];
endmodule


