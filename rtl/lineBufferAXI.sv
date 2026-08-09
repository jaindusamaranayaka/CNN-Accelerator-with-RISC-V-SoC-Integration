`timescale 1ns / 1ps

module lineBuffer #(
    parameter int DATA_WIDTH = 8,
    parameter int ROW_LENGTH = 8
)(
    input logic clk,
    input logic rstn,
    input logic wr_en,
    input logic [DATA_WIDTH-1:0] data_in,
    output logic [DATA_WIDTH-1:0] data_out
);

    logic [DATA_WIDTH-1:0] buffer [0:ROW_LENGTH-1];

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            buffer <= '{default : '0};
        end else if (wr_en) begin
            for (int i = ROW_LENGTH-1; i > 0; i--) begin
                buffer[i] <= buffer[i-1];
            end
            buffer[0] <= data_in;
        end
    end

    assign data_out = buffer[ROW_LENGTH-1];
endmodule


