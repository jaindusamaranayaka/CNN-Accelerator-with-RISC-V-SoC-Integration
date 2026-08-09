`timescale 1ns / 1ps

module tb_slidingWindow;

    logic clk;
    logic rstn;
    logic wr_en;
    logic [7:0] data_in;
    logic [7:0] window_out [2:0][2:0];

    int i;

    slidingWindow dut (
        .clk       (clk),
        .rstn      (rstn),
        .wr_en     (wr_en),
        .data_in   (data_in),
        .window_out(window_out)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, dut);

        rstn    = 0;
        wr_en   = 0;
        data_in = '0;

        repeat (2) @(posedge clk);
        rstn = 1;
        @(posedge clk);
        wr_en = 1;

        for (i = 1; i <= 81; i++) begin
            data_in = i[7:0];
            @(posedge clk);
        end

        wr_en = 0;
        repeat (5) @(posedge clk);
        $finish();
    end

endmodule