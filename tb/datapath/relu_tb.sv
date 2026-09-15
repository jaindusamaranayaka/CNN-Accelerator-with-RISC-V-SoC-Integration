`timescale 1ns/1ps

module relu_tb;
    parameter DATA_WIDTH = 8;
    localparam CLK_PERIOD = 10;

    logic clk = 0;
    logic rst_n;
    logic valid_in;
    logic signed [DATA_WIDTH-1:0] data_in;
    logic signed [DATA_WIDTH-1:0] data_out;
    logic valid_out;

    int errors = 0;

    always #(CLK_PERIOD/2) clk = ~clk;

    relu_activation #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .data_in(data_in),
        .data_out(data_out),
        .valid_out(valid_out)
    );

    task automatic relu(
        input logic signed [DATA_WIDTH-1:0] din,
        input logic signed [DATA_WIDTH-1:0] exp
    );
    @(posedge clk);
    data_in  = din;
    valid_in = 1;

    @(posedge clk);
    data_in  = '0;
    valid_in = 0;

    wait (valid_out === 1'b1);

    @(negedge clk);
    if (data_out !== exp) begin
        $error("MISMATCH: din=%0d expected %0d, got %0d", din, exp, data_out);
        errors++;
    end else begin
        $display("Passed: din=%0d expected %0d, got %0d", din, exp, data_out);
    end

    wait (valid_out === 1'b0);
    endtask

    initial begin
        rst_n    = 0;
        valid_in = 0;
        data_in  = '0;
        #(CLK_PERIOD*2) rst_n = 1;

        relu(8'sd42, 8'sd42);
        relu(-8'sd15, 8'sd0);
        relu(8'sd0, 8'sd0);
        relu(-8'sd128, 8'sd0);
        relu(8'sd127, 8'sd127);

        if (errors == 0)
            $display(">>> relu_tb PASSED");
        else
            $display(">>> relu_tb FAILED with %0d error(s)", errors);

        $finish;
    end
endmodule
