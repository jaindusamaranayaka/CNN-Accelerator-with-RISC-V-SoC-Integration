`timescale 1 ns / 1 ps

module cnn_core (
    input  logic        clk,
    input  logic        rst_n,
    
    // Config/Control signals
    input  logic        accel_start,
    input  logic [71:0] weights,
    input  logic [15:0] bias,
    input  logic [ 4:0] shift_s,
    
    // Inputs from Window Generator
    input  logic        valid_in,
    input  logic [71:0] pixels,
    
    // Classifier memory interface (for writing classifier weights)
    input  logic        weight_wr_en,
    input  logic [31:0] weight_addr,
    input  logic [31:0] weight_wdata,
    
    // Final Output
    output logic        class_valid,
    output logic [ 3:0] class_id
);

    // Internal pipeline signals
    logic signed [7:0] dp_relu_out;
    logic              dp_valid_out;

    // 1. Convolution / MAC Datapath
    datapath_top #(
        .DATA_WIDTH(8), 
        .PROD_WIDTH(16), 
        .SHIFT_WIDTH(5), 
        .NUM_TAPS(9)
    ) dp (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (valid_in),
        .pixels    (pixels),
        .weights   (weights),
        .bias      ($signed(bias)),
        .shift_s   (shift_s),
        .relu_out  (dp_relu_out),
        .valid_out (dp_valid_out)
    );

    // 2. Dense Layer / Classifier
    classifier_top clf (
        .clk          (clk),
        .rst_n        (rst_n),
        .weight_wr_en (weight_wr_en),
        .weight_addr  (weight_addr),
        .weight_wdata (weight_wdata),
        .accel_start  (accel_start),
        .valid_in     (dp_valid_out),
        .data_in      (dp_relu_out),
        .valid_out    (class_valid),
        .class_id     (class_id)
    );

endmodule
