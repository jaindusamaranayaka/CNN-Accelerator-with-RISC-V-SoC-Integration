`timescale 1ns / 1ps

module slidingWindow (
    input  logic       clk,
    input  logic       rstn,
    input  logic       wr_en,
    input  logic [7:0] data_in,
    output logic [7:0] window_out [2:0][2:0]
);

    logic [7:0] lineOut1;
    logic [7:0] lineOut2;

    logic [7:0] regRow1 [2:0];
    logic [7:0] regRow2 [2:0];
    logic [7:0] regRow3 [2:0];

    lineBuffer buffer1 (
        .clk     (clk),
        .rstn    (rstn),
        .wr_en   (wr_en),
        .data_in (data_in),
        .data_out(lineOut1)
    );

    lineBuffer buffer2 (
        .clk     (clk),
        .rstn    (rstn),
        .wr_en   (wr_en),
        .data_in (lineOut1),
        .data_out(lineOut2)
    ); 

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            regRow1[0] <= '0;
            regRow1[1] <= '0;
            regRow1[2] <= '0;

            regRow2[0] <= '0;
            regRow2[1] <= '0;
            regRow2[2] <= '0;

            regRow3[0] <= '0;
            regRow3[1] <= '0;
            regRow3[2] <= '0;
        end else if (wr_en) begin
            regRow1[2] <= data_in;
            regRow1[1] <= regRow1[2];
            regRow1[0] <= regRow1[1];

            regRow2[2] <= lineOut1;
            regRow2[1] <= regRow2[2];
            regRow2[0] <= regRow2[1];

            regRow3[2] <= lineOut2;
            regRow3[1] <= regRow3[2];
            regRow3[0] <= regRow3[1];
        end
    end

    always_comb begin
        window_out[0][0] = regRow1[2];
        window_out[0][1] = regRow1[1];
        window_out[0][2] = regRow1[0];

        window_out[1][0] = regRow2[2];
        window_out[1][1] = regRow2[1];
        window_out[1][2] = regRow2[0];

        window_out[2][0] = regRow3[2];
        window_out[2][1] = regRow3[1];
        window_out[2][2] = regRow3[0];
    end

endmodule   