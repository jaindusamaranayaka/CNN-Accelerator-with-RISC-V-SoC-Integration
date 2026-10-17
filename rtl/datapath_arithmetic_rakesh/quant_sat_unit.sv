module quant_sat_unit #(
    parameter OUT_WIDTH = 8,
    parameter SUM_WIDTH = 20,
    parameter SHIFT_WIDTH = 5
)(
    input  logic clk,
    input  logic rst_n,
    input  logic valid_in,
    input  logic signed [SUM_WIDTH-1:0] sum_in,
    input  logic        [SHIFT_WIDTH-1:0] shift_s,
    output logic signed [OUT_WIDTH-1:0] data_out,
    output logic valid_out
);
logic signed [SUM_WIDTH-1:0] s_scaled_comb;
assign s_scaled_comb = sum_in >>> shift_s;  


always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin 
        valid_out <= '0;
    end else begin 
        if (s_scaled_comb>20'sd127) 
            data_out <= 8'sd127;
        else if (s_scaled_comb<-20'sd128) 
            data_out <= -8'sd128;
        else 
            data_out <= s_scaled_comb[OUT_WIDTH-1:0];
        valid_out <= valid_in;
    end  
 end

endmodule