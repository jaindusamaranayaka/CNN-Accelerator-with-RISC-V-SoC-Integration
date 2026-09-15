`timescale 1ns/1ps
module mac_unit_tb;
  localparam DATA_WIDTH = 8;
  localparam PROD_WIDTH = 16;
  localparam CLK_PERIOD = 10;
  
  logic clk = 0;
  logic rst_n;
  logic signed [DATA_WIDTH-1:0] pixel_i;
  logic signed [DATA_WIDTH-1:0] weight_i;
  logic signed [PROD_WIDTH-1:0] product_o;
  
  int errors = 0;
  //Initializing the design under test
  mac_unit #(
    .DATA_WIDTH(DATA_WIDTH),
    .PROD_WIDTH(PROD_WIDTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .pixel_i(pixel_i),
    .weight_i(weight_i),
    .product_o(product_o)
  );
   // clock cycle
  always #(CLK_PERIOD/2) clk = ~clk;

  task automatic check(input logic signed [DATA_WIDTH-1:0] px, wt, input logic signed [PROD_WIDTH-1:0] exp);
    pixel_i = px;
    weight_i = wt;
    @(posedge clk); // for register write
    @(posedge clk); // for product capture
    #1;
    if (product_o !== exp) begin
         $error("FAIL px=%0d wt=%0d expected=%0d got=%0d", px, wt, exp, product_o);
         errors++;
    end else
        $display("PASS px=%0d wt=%0d product=%0d", px, wt, product_o);
  endtask
  
  initial begin
    $dumpfile("dump.vcd"); $dumpvars(0,mac_unit_tb);
    rst_n = 0; pixel_i  = 0; weight_i = 0;
    #(2*CLK_PERIOD);

    rst_n = 1;

    //test cases
    check(12, 5, 60);
    check(-8, 3, -24);
    check(-10, -6, 60);
    check(0, 47, 0);
    
    if (errors == 0) $display(">>> All Tests Passed");
    else $display(">>> %0d TEST(S) FAILED", errors);
    $finish;
  end
endmodule
