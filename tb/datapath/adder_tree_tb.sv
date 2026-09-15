`timescale 1ns/1ps

module adder_tree_tb;

    localparam PROD_WIDTH = 16;
    localparam DATA_WIDTH = 8;
    localparam NUM_TAPS   = 9;
    localparam CLK_PERIOD = 10;

    logic clk = 0;
    logic rst_n;
    logic valid_in;
    logic signed [PROD_WIDTH-1:0] bias;
    logic signed [PROD_WIDTH*NUM_TAPS-1:0] products;
    logic valid_out;
    logic signed [PROD_WIDTH+3:0] sum;

    int errors = 0;

    adder_tree #(
        .PROD_WIDTH (PROD_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .NUM_TAPS   (NUM_TAPS)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (valid_in),
        .bias      (bias),
        .products  (products),
        .valid_out (valid_out),
        .sum       (sum)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    task automatic run_case(
        input string                          name,
        input logic signed [PROD_WIDTH*NUM_TAPS-1:0] prod_in,
        input logic signed [15:0]             bias_in,
        input logic signed [PROD_WIDTH+3:0]   expected_sum
    );
        @(posedge clk);
        products = prod_in;
        bias     = bias_in;
        valid_in = 1;

        @(posedge clk);
        valid_in = 0;
        products = '0;
        bias     = '0;

        wait (valid_out === 1'b1);
        @(negedge clk);

        if (sum !== expected_sum) begin
            $error("[%s] MISMATCH: expected %0d, got %0d", name, expected_sum, sum);
            errors++;
        end else begin
            $display("[%s] OK: sum = %0d", name, sum);
        end

        wait (valid_out === 1'b0);
    endtask

    initial begin
        rst_n    = 0;
        valid_in = 0;
        products = '0;
        bias     = '0;
        #(CLK_PERIOD*2) rst_n = 1;

        run_case("case1_worked_example",
            {-16'sd40, 16'sd0, -16'sd10, 16'sd50, 16'sd0, 16'sd10, -16'sd30, 16'sd0, 16'sd10},
            16'sd5,
            -20'sd5
        );

        run_case("case2_negative_bias",
            {-16'sd40, 16'sd0, -16'sd10, 16'sd50, 16'sd0, 16'sd10, -16'sd30, 16'sd0, 16'sd10},
            -16'sd300,
            -20'sd310
        );

        if (errors == 0)
            $display(">>> adder_tree_tb PASSED");
        else
            $display(">>> adder_tree_tb FAILED with %0d error(s)", errors);

        $finish;
    end

endmodule
