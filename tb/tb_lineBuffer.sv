`timescale 1ns / 1ps

module tb_lineBuffer;

    logic clk;
    logic rstn;
    logic wr_en;
    logic [7:0] data_in;
    logic [7:0] data_out;

    lineBuffer dut (.clk(clk),
                    .rstn(rstn),
                    .wr_en(wr_en),
                    .data_in(data_in),
                    .data_out(data_out));
    initial begin
        $dumpfile("dump.vcd");$dumpvars(0,dut);
    end

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin

        #5;
        rstn = 0;
        wr_en = 0;
        data_in = 8'd0;

        #10;
        rstn = 1;

        @(posedge clk);
        wr_en = 1;
        data_in = 8'd10;

        @(posedge clk);
        data_in = 8'd20;
        
        @(posedge clk);
        data_in = 8'd30;
        
        @(posedge clk);
        data_in = 8'd40;

        @(posedge clk);
        wr_en = 0;

        #50;
        $finish;
    end

endmodule
