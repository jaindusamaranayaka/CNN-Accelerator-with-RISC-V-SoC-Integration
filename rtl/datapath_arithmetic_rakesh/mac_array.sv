
module mac_array #(
    parameter DATA_WIDTH = 8,
    parameter PROD_WIDTH = 16,
    parameter NUM_TAPS = 9
)(
    input  logic                            clk,
    input  logic                            rst_n,
    input  logic                            valid_in,
    input  logic [DATA_WIDTH*NUM_TAPS-1:0]  pixels,
    input  logic [DATA_WIDTH*NUM_TAPS-1:0]  weights,
    output logic [PROD_WIDTH*NUM_TAPS-1:0]  products,
    output logic                            valid_out
);
    genvar i;
    generate 
        for (i = 0; i<NUM_TAPS; i++) begin : gen_mac_lane
         mac_unit#(
            .DATA_WIDTH(DATA_WIDTH),
            .PROD_WIDTH(PROD_WIDTH)
         )u_mac (
            .clk(clk),
            .rst_n(rst_n),
            .pixel_i(pixels [DATA_WIDTH*(i+1)-1 -: DATA_WIDTH]),
            .weight_i(weights[DATA_WIDTH*(i+1)-1 -: DATA_WIDTH]),
            .product_o(products[PROD_WIDTH*(i+1)-1 -: PROD_WIDTH])
         );
        end
    endgenerate

    // staling the valid stage to match the datapath 
    // Mac unit depth is 2 if it changes-- change the stalling code below also by the same value
    logic valid_stage_1;

    always_ff @(posedge clk or negedge rst_n) begin // stalling by 2 cycles
        if(!rst_n)begin
            valid_stage_1 <= '0;
            valid_out <='0;
        end else begin 
            valid_stage_1 <= valid_in;
            valid_out <= valid_stage_1;
            end
     end
endmodule