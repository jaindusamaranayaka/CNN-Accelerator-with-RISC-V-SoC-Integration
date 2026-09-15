`timescale 1ns/1ps

module mac_tb;

    localparam DATA_WIDTH = 8;
    localparam PROD_WIDTH = 16;
    localparam NUM_TAPS   = 9;
    localparam CLK_PERIOD = 10;

    logic clk = 0;
    logic rst_n;
    logic valid_in;
    logic signed [DATA_WIDTH*NUM_TAPS-1:0] pixels;
    logic signed [DATA_WIDTH*NUM_TAPS-1:0] weights;
    logic signed [PROD_WIDTH*NUM_TAPS-1:0] products;
    logic valid_out;

    logic signed [PROD_WIDTH-1:0] expected [0:8];

    int errors = 0;

    mac_array #(
        .DATA_WIDTH (DATA_WIDTH),
        .PROD_WIDTH (PROD_WIDTH),
        .NUM_TAPS   (NUM_TAPS)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (valid_in),
        .pixels    (pixels),
        .weights   (weights),
        .products  (products),
        .valid_out (valid_out)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        rst_n    = 0;
        valid_in = 0;
        pixels   = '0;
        weights  = '0;

        expected[0] = 16'sd10;
        expected[1] = 16'sd0;
        expected[2] = -16'sd30;
        expected[3] = 16'sd10;
        expected[4] = 16'sd0;
        expected[5] = 16'sd50;
        expected[6] = -16'sd10;
        expected[7] = 16'sd0;
        expected[8] = -16'sd40;

        #(CLK_PERIOD*2) rst_n = 1;

        @(posedge clk);
        pixels   = {8'sd40, 8'sd0, -8'sd10, -8'sd25, 8'sd15, 8'sd5, 8'sd30, 8'sd20, 8'sd10};
        weights  = {-8'sd1, 8'sd0,  8'sd1,  -8'sd2,  8'sd0,  8'sd2, -8'sd1,  8'sd0,  8'sd1};
        valid_in = 1;

        @(posedge clk);
        @(posedge clk);
        valid_in = 0;
        pixels   = '0;
        weights  = '0;

        wait (valid_out === 1'b1);
        @(posedge clk);

        for (int i = 0; i < NUM_TAPS; i++) begin
            logic signed [PROD_WIDTH-1:0] got;
            got = products[PROD_WIDTH*(i+1)-1 -: PROD_WIDTH];
            if (got !== expected[i]) begin
                $error("tap%0d MISMATCH: expected %0d, got %0d", i, expected[i], got);
                errors++;
            end else begin
                $display("tap%0d OK: %0d", i, got);
            end
        end

        if (errors == 0)
            $display(">>> mac_array_3x3_tb PASSED");
        else
            $display(">>> mac_array_3x3_tb FAILED with %0d error(s)", errors);

        $finish;
    end

endmodule
