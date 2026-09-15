`timescale 1ns/1ps

module quant_sat_tb;
    parameter OUT_WIDTH = 8;
    parameter SUM_WIDTH = 20;
    parameter SHIFT_WIDTH = 5;
    localparam CLK_PERIOD = 10;

    logic clk =0;
    logic rst_n;
    logic valid_in;
    logic signed [SUM_WIDTH-1:0] sum_in;
    logic        [SHIFT_WIDTH-1:0] shift_s;
    logic signed [OUT_WIDTH-1:0] data_out;
    logic valid_out;

    int errors =0;

    always #(CLK_PERIOD/2) clk = ~clk;

    quant_sat_unit #(
        .OUT_WIDTH(OUT_WIDTH),
        .SUM_WIDTH(SUM_WIDTH),
        .SHIFT_WIDTH(SHIFT_WIDTH)
    ) dut (
       .clk(clk),
       .rst_n(rst_n),
       .valid_in(valid_in),
       .sum_in(sum_in),
       .shift_s(shift_s),
       .data_out(data_out),
       .valid_out(valid_out)
    );

    task automatic quant(
        input logic signed [SUM_WIDTH-1:0] sum,
        input logic        [SHIFT_WIDTH-1:0] shift,
        input logic signed [OUT_WIDTH-1:0] exp
    );
    @(posedge clk);
    sum_in = sum;
    shift_s = shift;
    valid_in = 1;

    @(posedge clk);
    sum_in = '0;
    shift_s = '0;
    valid_in = 0;

    wait (valid_out === 1'b1);

    @(negedge clk);
    if(data_out !== exp) begin
        $error("MISMATCH: expected %0d, got %0d", exp, data_out);
        errors ++;
    end else begin
        $display("Passed: expected %0d, got %0d", exp, data_out);
     end

    wait (valid_out === 1'b0);
    endtask

    initial begin
        rst_n    = 0;
        valid_in = 0;
        sum_in = '0;
        shift_s = '0;
        #(CLK_PERIOD*2) rst_n = 1;

        quant(-20'sd5,5'sd2,-8'sd2);
        quant(20'sd177928,5'sd2,8'sd127);
        quant(-20'sd1600,5'sd2,-8'sd128);
        quant(20'sd127,5'sd0,8'sd127);
        quant(-20'sd7,5'sd1,-8'sd4);
        
        if (errors == 0)
            $display(">>> quant_sat_tb PASSED");
        else
            $display(">>> quant_sat_tb FAILED with %0d error(s)", errors);

        $finish;
     end
endmodule
