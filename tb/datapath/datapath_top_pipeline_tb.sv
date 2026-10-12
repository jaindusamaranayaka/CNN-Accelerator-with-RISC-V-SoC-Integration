`timescale 1ns/1ps

module datapath_top_pipeline_tb;
    parameter  DATA_WIDTH  =  8;
    parameter  PROD_WIDTH  = 16;
    parameter  SHIFT_WIDTH =  5;
    parameter  NUM_TAPS    =  9;
    localparam CLK_PERIOD  = 10;


 // readable test bench side arrays
 logic signed [DATA_WIDTH-1:0] pixel_arr [0:NUM_TAPS-1];
 logic signed [DATA_WIDTH-1:0] weight_arr [0:NUM_TAPS-1];

 //
    logic                            clk=0;
    logic                            rst_n;

//flattened signals driving the DUT
    logic                            valid_in;
    logic [DATA_WIDTH*NUM_TAPS-1:0]  pixels;
    logic [DATA_WIDTH*NUM_TAPS-1:0]  weights;
    logic signed [PROD_WIDTH-1:0]    bias;
    logic        [SHIFT_WIDTH-1:0]   shift_s;


    logic signed [DATA_WIDTH-1:0]    relu_out;
    logic                            valid_out;

    always #(CLK_PERIOD/2) clk = ~clk;

    //flattening the arrays 
    always_comb begin
        for(int i=0; i< NUM_TAPS; i++) begin
            automatic int start_idx = DATA_WIDTH*i; 
            pixels[start_idx +:DATA_WIDTH] = pixel_arr[i];
            weights[start_idx +:DATA_WIDTH] = weight_arr[i];
        end
     end

    //instantiating a DUT
    datapath_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .PROD_WIDTH(PROD_WIDTH),
        .SHIFT_WIDTH(SHIFT_WIDTH),
        .NUM_TAPS(NUM_TAPS)
    ) dut(
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

    //golden function
    function automatic logic signed [DATA_WIDTH-1:0] check(
        input logic signed [DATA_WIDTH-1:0] pixel_arr_check  [0:NUM_TAPS-1],
        input logic signed [DATA_WIDTH-1:0] weight_arr_check [0:NUM_TAPS-1],
        input logic signed [PROD_WIDTH-1:0] bias,
        input logic [SHIFT_WIDTH-1:0] shift_s
    );

    logic signed [PROD_WIDTH+3:0] sum_1 = '0;
    logic signed [PROD_WIDTH+3:0] sum_shifted = 0;
    logic signed [DATA_WIDTH-1:0] sat_result;

     for(int i=0; i<NUM_TAPS; i++)begin 
        sum_1 += pixel_arr_check[i]*weight_arr_check[i];
     end

    sum_shifted = (sum_1 + bias) >>> shift_s;
        if (sum_shifted>20'sd127) 
            sat_result = 8'sd127;
        else if (sum_shifted<-20'sd128) 
            sat_result = -8'sd128;
        else 
            sat_result = sum_shifted[DATA_WIDTH-1:0];
    return sat_result[DATA_WIDTH-1] ? '0 : sat_result;

    endfunction

    //scoreboard Qeue declaration
    logic signed [DATA_WIDTH-1:0] expected_relu_q[$];

    // Driver processs
    always @(posedge clk) begin 
        //temperory
        if(!rst_n) begin 
            valid_in <= '0;
        end else begin
            automatic logic is_valid = ($urandom_range(0, 99) < 80);

            valid_in <= is_valid;
            if(is_valid) begin
                automatic logic signed [DATA_WIDTH-1:0] pixel_arr_temp [0:NUM_TAPS-1];
                automatic logic signed [DATA_WIDTH-1:0] weight_arr_temp [0:NUM_TAPS-1];
                automatic logic signed [PROD_WIDTH-1:0] bias_temp;
                automatic logic        [SHIFT_WIDTH-1:0] shift_s_temp;

                //generating temperory values
                // blocking assignment is used to create values because it is used in the same clock cycle to drive the DUT
                for(int i = 0; i<NUM_TAPS; i++) begin 
                        pixel_arr_temp[i] = $urandom_range(0,255);
                        weight_arr_temp[i] = $urandom_range(0,255);
                    end
                shift_s_temp = $urandom_range(4,12);
                bias_temp =  $urandom_range(0,128);
                
                
                for(int i = 0; i<NUM_TAPS; i++) begin 
                    pixel_arr[i] <= pixel_arr_temp[i];
                    weight_arr[i] <= weight_arr_temp[i];
                end
                shift_s <= shift_s_temp;
                bias <=  bias_temp;
                expected_relu_q.push_back(check(pixel_arr_temp,weight_arr_temp,bias_temp,shift_s_temp));
            end
        end
    end
    // Checker processs
    int errors =0;
    always @(posedge clk) begin
        if(valid_out) begin 
            automatic logic signed [DATA_WIDTH-1:0] exp_relu = expected_relu_q.pop_front();
            if(relu_out == exp_relu) begin
                $display("No error, expected %d, and got %d", exp_relu, relu_out);
            end else begin 
                errors++;
                $display("Error, expected %d, and got %d", exp_relu, relu_out);
            end
        end 

     end
    
    // Run control
initial begin
    rst_n = 0;
    repeat (3) @(posedge clk);
    rst_n = 1;

    repeat (500) @(posedge clk);

    if (errors == 0)
        $display(">>> datapath_top_pipeline_tb PASSED");
    else
        $display(">>> datapath_top_pipeline_tb FAILED with %0d error(s)", errors);

    $finish;
end
endmodule