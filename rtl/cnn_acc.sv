module cnn_acc #(
    parameter int N_CLASSES = 10,
    parameter int DATA_WIDTH = 8
)(
    input  logic clk,
    input  logic rst,
    input  logic start,

    // Streaming 3x3 Window Input
    input logic [DATA_WIDTH-1:0] window_data [0:2][0:2],
    input logic                  window_valid,

    // Kernel (weights)
    input logic [2:0] kernel [0:2],

    // Classification result
    output logic [31:0] class_result,
    output logic done
);

    // ============================================================
    // Stage 1: Feature extraction
    // ============================================================

    logic feature_valid;
    logic feature_valid_r;

    logic [FEATURE_WIDTH-1:0] feature_data;


    // ============================================================
    // Stage 2: ReLU
    // ============================================================

    logic relu_valid;
    logic relu_valid_r;

    logic [FEATURE_WIDTH-1:0] relu_data;


    // ============================================================
    // Stage 3: Pooling
    // ============================================================

    logic pool_valid;
    logic pool_valid_r;

    logic [POOL_WIDTH-1:0] pool_data;


    // ============================================================
    // Stage 4: Flatten
    // ============================================================

    logic flatten_valid;
    logic flatten_valid_r;

    logic [FLAT_WIDTH-1:0] flatten_data;


    // ============================================================
    // Stage 5: Normalize
    // ============================================================

    logic normalize_valid;
    logic normalize_valid_r;

    logic [NORM_WIDTH-1:0] normalize_data;


    // ============================================================
    // Stage 6: Classification
    // ============================================================

    logic classify_valid;

    // ============================================================
    // Module instantiations
    // ============================================================

    feature1 f1 (
        .clk          (clk),
        .rst          (rst),
        .start        (start),
        
        .window_data  (window_data),
        .window_valid (window_valid),
        .kernel       (kernel),

        .data_out     (feature_data),
        .valid_out    (feature_valid)
    );


    Relu relu (
        .clk       (clk),
        .rst       (rst),

        .data_in   (feature_data),
        .valid_in  (feature_valid_r),

        .data_out  (relu_data),
        .valid_out (relu_valid)
    );


    Pooling pooling (
        .clk       (clk),
        .rst       (rst),

        .data_in   (relu_data),
        .valid_in  (relu_valid_r),

        .data_out  (pool_data),
        .valid_out (pool_valid)
    );


    flatten #(
        .INPUT_WIDTH(POOL_WIDTH)
    ) flat (
        .clk       (clk),
        .rst       (rst),

        .data_in   (pool_data),
        .valid_in  (pool_valid_r),

        .data_out  (flatten_data),
        .valid_out (flatten_valid)
    );


    Normalize normalize (
        .clk       (clk),
        .rst       (rst),

        .data_in   (flatten_data),
        .valid_in  (flatten_valid_r),

        .data_out  (normalize_data),
        .valid_out (normalize_valid)
    );


    Classification classification (
        .clk       (clk),
        .rst       (rst),

        .data_in   (normalize_data),
        .valid_in  (normalize_valid_r),

        .class_out (class_result),
        .valid_out (classify_valid)
    );


    // ============================================================
    // Pipeline registers
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            feature_valid_r  <= 1'b0;
            relu_valid_r     <= 1'b0;
            pool_valid_r     <= 1'b0;
            flatten_valid_r  <= 1'b0;
            normalize_valid_r <= 1'b0;

        end
        else begin

            // Stage 1 → Stage 2
            feature_valid_r <= feature_valid;

            // Stage 2 → Stage 3
            relu_valid_r <= relu_valid;

            // Stage 3 → Stage 4
            pool_valid_r <= pool_valid;

            // Stage 4 → Stage 5
            flatten_valid_r <= flatten_valid;

            // Stage 5 → Stage 6
            normalize_valid_r <= normalize_valid;

        end

    end


    // Classification is finished when its output is valid
    assign done = classify_valid;

endmodule