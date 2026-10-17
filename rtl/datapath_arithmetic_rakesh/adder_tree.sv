module adder_tree #(
    parameter PROD_WIDTH  = 16,
    parameter DATA_WIDTH = 8,
    parameter NUM_TAPS = 9
)(
    input  logic                                   clk,
    input  logic                                   rst_n,
    input  logic                                   valid_in,
    input  logic signed [PROD_WIDTH-1:0]           bias,
    input  logic        [PROD_WIDTH*NUM_TAPS-1:0]  products,
    output logic                                   valid_out,
    output logic signed [PROD_WIDTH+3:0]           sum
);

//level 1 registers 17bits
logic signed [PROD_WIDTH:0] reg_11, reg_12,reg_13,reg_14;
//level 2 registers 18 bits
logic signed [PROD_WIDTH+1:0] reg_21,reg_22;
//register for bias 
logic signed [PROD_WIDTH-1:0] regbias_1, regbias_2, regM8_1,regM8_2;


//level 1 registers
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
            reg_11 <= '0;
            reg_12 <= '0;
            reg_13 <= '0;
            reg_14 <= '0;
            regM8_1 <= '0;
            regbias_1 <= '0;
end else begin 
    reg_11    <= $signed(products[1*PROD_WIDTH-1:0*PROD_WIDTH]) + $signed(products[2*PROD_WIDTH-1:PROD_WIDTH]);
    reg_12    <= $signed(products[3*PROD_WIDTH-1:2*PROD_WIDTH]) + $signed(products[4*PROD_WIDTH-1:3*PROD_WIDTH]);
    reg_13    <= $signed(products[5*PROD_WIDTH-1:4*PROD_WIDTH]) + $signed(products[6*PROD_WIDTH-1:5*PROD_WIDTH]);
    reg_14    <= $signed(products[7*PROD_WIDTH-1:6*PROD_WIDTH]) + $signed(products[8*PROD_WIDTH-1:7*PROD_WIDTH]);
    regM8_1   <= $signed(products[9*PROD_WIDTH-1:8*PROD_WIDTH]);
    regbias_1 <= bias;
end
end

//second level
always_ff @(posedge clk or negedge rst_n) begin 
    if(!rst_n)begin
        reg_21 <= '0;
        reg_22 <= '0;
        regM8_2 <= '0;
        regbias_2 <= '0;
     end else begin
        reg_21 <= reg_11 + reg_12;
        reg_22 <= reg_13 + reg_14;
        regM8_2 <= regM8_1;
        regbias_2 <= regbias_1;
end
end

//3rd level 
always_ff @(posedge clk or negedge rst_n)begin
    if(!rst_n) sum<=0 ;
    else sum <= reg_21 + reg_22 + regM8_2 + regbias_2;
 end

// 
  logic valid_stage_1;
  logic valid_stage_2;

    always_ff @(posedge clk or negedge rst_n) begin // stalling by 2 cycles
        if(!rst_n)begin
            valid_stage_1 <= '0;
            valid_stage_2 <= '0;
            valid_out <='0;
        end else begin 
            valid_stage_1 <= valid_in;
            valid_stage_2 <=  valid_stage_1;
            valid_out <= valid_stage_2;
            
            end
     end
endmodule