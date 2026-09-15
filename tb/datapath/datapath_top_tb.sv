`timescale 1ns/1ps

module datapath_top_tb;

    parameter DATA_WIDTH  = 8;
    parameter PROD_WIDTH  = 16;
    parameter SHIFT_WIDTH = 5;
    parameter NUM_TAPS    = 9;
    localparam CLK_PERIOD = 10;

    logic clk = 0;
    logic rst_n;
    logic valid_in;
    logic [DATA_WIDTH*NUM_TAPS-1:0] pixels;
    logic [DATA_WIDTH*NUM_TAPS-1:0] weights;
    logic signed [PROD_WIDTH-1:0]   bias;
    logic [SHIFT_WIDTH-1:0]         shift_s;
    logic signed [DATA_WIDTH-1:0]   relu_out;
    logic                           valid_out;

    int errors = 0;

    always #(CLK_PERIOD/2) clk = ~clk;

    datapath_top #(
        .DATA_WIDTH  (DATA_WIDTH),
        .PROD_WIDTH  (PROD_WIDTH),
        .SHIFT_WIDTH (SHIFT_WIDTH),
        .NUM_TAPS    (NUM_TAPS)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (valid_in),
        .pixels    (pixels),
        .weights   (weights),
        .bias      (bias),
        .shift_s   (shift_s),
        .relu_out  (relu_out),
        .valid_out (valid_out)
    );

    task automatic run_case(
        input string name,
        input logic [DATA_WIDTH*NUM_TAPS-1:0] px,
        input logic [DATA_WIDTH*NUM_TAPS-1:0] wt,
        input logic signed [PROD_WIDTH-1:0]   b,
        input logic [SHIFT_WIDTH-1:0]         s,
        input logic signed [DATA_WIDTH-1:0]   exp
    );
        @(posedge clk);
        pixels   = px;
        weights  = wt;
        bias     = b;
        shift_s  = s;
        valid_in = 1;

        @(posedge clk);
        valid_in = 0;
        pixels   = '0;
        weights  = '0;

        wait (valid_out === 1'b1);
        @(negedge clk);

        if (relu_out !== exp) begin
            $error("[%s] MISMATCH: expected %0d, got %0d", name, exp, relu_out);
            errors++;
        end else begin
            $display("[%s] OK: relu_out = %0d", name, relu_out);
        end

        wait (valid_out === 1'b0);
    endtask

    initial begin
        rst_n    = 0;
        valid_in = 0;
        pixels   = '0;
        weights  = '0;
        bias     = '0;
        shift_s  = '0;
        #(CLK_PERIOD*2) rst_n = 1;

        run_case("case1_worked_example",
            {8'sd40, 8'sd0, -8'sd10, -8'sd25, 8'sd15, 8'sd5, 8'sd30, 8'sd20, 8'sd10},
            {-8'sd1, 8'sd0,  8'sd1,  -8'sd2,  8'sd0,  8'sd2, -8'sd1,  8'sd0,  8'sd1},
            16'sd5,
            5'd2,
            8'sd0
        );

        run_case("case2_all_ones",
            {9{8'sd1}},
            {9{8'sd1}},
            16'sd0,
            5'd0,
            8'sd9
        );

        run_case("case3_saturation",
            {9{8'sd127}},
            {9{8'sd127}},
            16'sd0,
            5'd0,
            8'sd127
        );

        if (errors == 0)
            $display(">>> datapath_top_tb PASSED");
        else
            $display(">>> datapath_top_tb FAILED with %0d error(s)", errors);

        $finish;
    end

endmodule
