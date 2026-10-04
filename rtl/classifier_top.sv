`timescale 1 ns / 1 ps

module classifier_top (
    input  logic clk,
    input  logic rst_n,
    
    // CPU Interface for Dense Weights/Biases (mapped at 0x60000000)
    input  logic        weight_wr_en,
    input  logic [31:0] weight_addr,
    input  logic [31:0] weight_wdata,
    
    // Input from datapath
    input  logic        valid_in,
    input  logic [7:0]  data_in,
    
    // Output Classification
    output logic        valid_out,
    output logic [3:0]  class_id
);

    logic pool_valid;
    logic [7:0] pool_data;
    
    max_pool_2d #(
        .WIDTH(26),
        .DATA_WIDTH(8)
    ) pool (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .data_in(data_in),
        .valid_out(pool_valid),
        .data_out(pool_data)
    );
    
    logic dense_valid;
    logic signed [31:0] logits [0:9];
    
    dense_layer dense (
        .clk(clk),
        .rst_n(rst_n),
        .weight_wr_en(weight_wr_en),
        .weight_addr(weight_addr),
        .weight_wdata(weight_wdata),
        .valid_in(pool_valid),
        .data_in(pool_data),
        .valid_out(dense_valid),
        .logits(logits)
    );
    
    argmax am (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(dense_valid),
        .logits(logits),
        .valid_out(valid_out),
        .class_id(class_id)
    );

endmodule
