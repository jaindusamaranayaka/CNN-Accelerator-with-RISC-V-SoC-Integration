module datapath_top #(
    parameter DATA_WIDTH = 8,
    parameter PROD_WIDTH = 16,
    parameter SHIFT_WIDTH = 5,
    parameter NUM_TAPS = 9
)(
    input  logic                            clk,
    input  logic                            rst_n,
    input  logic                            valid_in,
    input  logic [DATA_WIDTH*NUM_TAPS-1:0]  pixels,
    input  logic [DATA_WIDTH*NUM_TAPS-1:0]  weights,
    input  logic signed [PROD_WIDTH-1:0]    bias,
    input  logic        [SHIFT_WIDTH-1:0]   shift_s,
    output logic signed [DATA_WIDTH-1:0]    relu_out,
    output logic                            valid_out
);
// internal wires between stages
logic [PROD_WIDTH*NUM_TAPS-1:0]  products;
logic signed [PROD_WIDTH+3:0]           sum;
logic signed [DATA_WIDTH-1:0] s_scaled;
logic valid_out_1, valid_out_2, valid_out_3;

mac_array mac(
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_in),
    .pixels(pixels),
    .weights(weights),
    .products(products),
    .valid_out(valid_out_1)
);

adder_tree adder(
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_out_1),
    .bias(bias),
    .products(products),
    .valid_out(valid_out_2),
    .sum(sum)
);

quant_sat_unit sat(
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_out_2),
    .sum_in(sum),
    .shift_s(shift_s),
    .data_out(s_scaled),
    .valid_out(valid_out_3)
);

relu_activation relu(
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_out_3),
    .data_in(s_scaled),
    .data_out(relu_out),
    .valid_out(valid_out)
);
endmodule