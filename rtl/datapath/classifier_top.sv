`timescale 1ns / 1ps

// classifier_top.sv

module classifier_top #(
    parameter int N_IN       = 169,
    parameter int N_OUT      = 10,
    parameter int DATA_WIDTH = 8,
    parameter int ACC_WIDTH  = 24
)(
    input  logic clk,
    input  logic rst_n,

    // ---- CPU bus (uart_peripheral shape) ----------------------------
    input  logic        bus_valid,
    input  logic [31:0] bus_addr,
    input  logic [31:0] bus_wdata,
    input  logic [ 3:0] bus_wstrb,
    output logic [31:0] bus_rdata,
    output logic        bus_ready,

    // ---- pooled value stream from the feature extraction block ------
    input  logic                  sof,
    input  logic                  valid_in,
    input  logic [DATA_WIDTH-1:0] data_in,

    // ---- result, also exposed to the SoC (7-seg, etc.) --------------
    output logic                           result_valid,
    output logic [$clog2(N_OUT)-1:0]       class_id_o
);

    localparam int IDX_WIDTH   = $clog2(N_OUT);
    localparam int RESULT_BLK  = 11;

    logic                       weight_wr_en;
    logic                       dense_valid;
    logic [N_OUT*ACC_WIDTH-1:0] dense_logits;
    logic                       argmax_valid;
    logic [IDX_WIDTH-1:0]       argmax_class;


    logic                 result_done;
    logic [IDX_WIDTH-1:0] result_class;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bus_ready <= 1'b0;
        end else begin
            bus_ready <= 1'b0;
            if (bus_valid && !bus_ready)
                bus_ready <= 1'b1;
        end
    end

    assign weight_wr_en = bus_valid && !bus_ready && (bus_wstrb != 4'b0000);


    always_comb begin
        bus_rdata = 32'h0;
        if (bus_addr[15:10] == RESULT_BLK[5:0])
            bus_rdata = {27'h0, result_done, result_class};
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_done  <= 1'b0;
            result_class <= '0;
        end else begin
            if (sof) begin
                result_done <= 1'b0;
            end else if (argmax_valid) begin
                result_done  <= 1'b1;
                result_class <= argmax_class;
            end
        end
    end

    assign result_valid = result_done;
    assign class_id_o   = result_class;

    dense_layer #(
        .N_IN       (N_IN),
        .N_OUT      (N_OUT),
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH)
    ) u_dense (
        .clk          (clk),
        .rst_n        (rst_n),
        .weight_wr_en (weight_wr_en),
        .weight_addr  (bus_addr),
        .weight_wdata (bus_wdata),
        .sof          (sof),
        .valid_in     (valid_in),
        .data_in      (data_in),
        .valid_out    (dense_valid),
        .logits_o     (dense_logits)
    );

    argmax #(
        .N_OUT     (N_OUT),
        .ACC_WIDTH (ACC_WIDTH)
    ) u_argmax (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (dense_valid),
        .logits_i  (dense_logits),
        .valid_out (argmax_valid),
        .class_id  (argmax_class)
    );

endmodule