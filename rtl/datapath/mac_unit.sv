module mac_unit#(
    parameter DATA_WIDTH = 8,
    parameter PROD_WIDTH = 16
)(
    input logic clk,
    input logic rst_n,
    input logic signed [DATA_WIDTH-1:0] pixel_i,
    input logic signed [DATA_WIDTH-1:0] weight_i,
    output logic signed [PROD_WIDTH-1:0] product_o

);
    // stage 1 a register interface between the input and the multiplier to innitiate DSP blocks.
    logic signed [DATA_WIDTH-1:0] pixel_r, weight_r;


    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            pixel_r <= '0;
            weight_r <= '0;
        end else begin
            pixel_r <= pixel_i;
            weight_r <= weight_i;
         end
    end

    // stage 2 multiply and output register

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            product_o <= '0;
        else
            product_o <= pixel_r * weight_r;
    end



endmodule