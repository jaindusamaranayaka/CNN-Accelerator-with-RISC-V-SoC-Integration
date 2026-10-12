`timescale 1ns / 1ps

// dense_layer.sv  
module dense_layer #(
    parameter int N_IN       = 169,
    parameter int N_OUT      = 10,
    parameter int DATA_WIDTH = 8,   // pooled value, unsigned 0..127
    parameter int W_WIDTH    = 8,   // weight, signed int8
    parameter int BIAS_WIDTH = 16,  // bias, signed int16
    parameter int PROD_WIDTH = 17,  // 9-bit signed * 8-bit signed
    parameter int ACC_WIDTH  = 24   // 169 products + bias, derived bound
)(
    input  logic clk,
    input  logic rst_n,

    // ---- CPU weight / bias write port -------------------------------
    input  logic        weight_wr_en,
    input  logic [31:0] weight_addr,
    input  logic [31:0] weight_wdata,

    // ---- pooled value stream ----------------------------------------
    input  logic                  sof,        // frame start, same pulse MaxPool gets
    input  logic                  valid_in,
    input  logic [DATA_WIDTH-1:0] data_in,

    // ---- result to argmax -------------------------------------------
    output logic                          valid_out,  // 1-cycle pulse
    output logic [N_OUT*ACC_WIDTH-1:0]    logits_o    // lane j = [24j+23 : 24j]
);

    localparam int IDX_WIDTH = $clog2(N_IN);   // 8 bits, counts 0..168

    // =================================================================
    // Address decode  (GIVEN -- settled, do not change without telling
    // the team; the 1024/4 spacing exists to make this pure bit slicing)
    // =================================================================
    logic [3:0] nid; // lane(digit) id
    logic [7:0] pid; // 169 pixel id (index i)
    logic       is_bias;
    logic       is_weight;
    logic [5:0] blk;
    
    assign blk       = weight_addr[15:10];
    assign nid       = weight_addr[13:10];
    assign pid       = weight_addr[9:2];
    assign is_bias   = (blk == 6'd10); // first 10 positions is for the address
    assign is_weight = (blk <  6'd10);


    // =================================================================
    // State
    logic [IDX_WIDTH-1:0]       i;              // pooled value index, 0..168
    logic signed [DATA_WIDTH:0] p_reg;          // zero-extended pooled value
    logic signed [PROD_WIDTH-1:0] prod [0:N_OUT-1];
    logic signed [ACC_WIDTH-1:0]  acc  [0:N_OUT-1];
    logic signed [BIAS_WIDTH-1:0] bias_reg [0:N_OUT-1];

    logic v1, v2;       // valid delayed to stage 1 and stage 2
    logic l1, l2;       // "this was the 169th beat" delayed likewise

    // =================================================================
    // Per-lane weight memory  (GIVEN -- this exact shape is what makes
    // per lane memory to interface the per lane memory weight to infer M9K

    logic signed [W_WIDTH-1:0] w_rdata [0:N_OUT-1];

    genvar g;
    generate
        for (g = 0; g < N_OUT; g++) begin : gen_lane_mem
            logic signed [W_WIDTH-1:0] w_mem [0:N_IN-1];

            always_ff @(posedge clk) begin
                if (weight_wr_en && is_weight && (nid == g) && (pid < N_IN))
                    w_mem[pid] <= weight_wdata[W_WIDTH-1:0]; // write data 

                w_rdata[g] <= w_mem[i];     // synchronous read, 1-cycle latency
            end
        end
    endgenerate



    // =================================================================
    //bias write port
    always_ff @(posedge clk) begin
        if(weight_wr_en && is_bias && (pid < N_OUT)) begin 
            bias_reg[pid]<= weight_wdata[BIAS_WIDTH-1:0];
        end
    end

    // =================================================================
    // index counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i <= '0;
        end else begin
           if(sof) begin
                i <= '0;
           end else if (valid_in) begin 
                if (i == IDX_WIDTH'(N_IN-1))
                    i <= '0;
                else
                    i <= i + 1'b1;
           end
        end
    end

    // =================================================================
    //stage 0: register the pooled value, start the delay chains
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p_reg <= '0;
            v1    <= 1'b0;
            v2    <= 1'b0;
            l1    <= 1'b0;
            l2    <= 1'b0;
        end else begin
            if(sof) begin 
                v1 <= '0;
                l1 <= '0;
                v2 <= '0;
                l2 <= '0;
            end else begin
                v1 <= valid_in;
                v2 <= v1;
                l1 <= valid_in && (i == IDX_WIDTH'(N_IN-1));
                l2 <= l1;
                if(valid_in)begin
                    p_reg <= {1'b0, data_in}; end
            end
        end
    end

    // =================================================================
    //stage 1: multiply
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int j = 0; j < N_OUT; j++)
                prod[j] <= '0;
        end else begin
            for (int j = 0; j < N_OUT; j++)
                prod[j] <= p_reg * w_rdata[j];
        end
    end

    // =================================================================
    //stage 2: accumulate, and emit
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            for (int j = 0; j < N_OUT; j++)
                acc[j] <= '0;
        end else begin
            valid_out <= 1'b0;                  // default, overridden below

            if (sof) begin
                for (int j = 0; j < N_OUT; j++)
                    acc[j] <= ACC_WIDTH'(bias_reg[j]);
            end else if (v2) begin
                for (int j = 0; j < N_OUT; j++)
                    acc[j] <= acc[j] + ACC_WIDTH'(prod[j]);
                valid_out <= l2;
            end
        end
    end
    // =================================================================
    //pack acc[] into the flat logits_o bus

    genvar p;
    generate
        for (p = 0; p < N_OUT; p++) begin : gen_pack
            assign logits_o[ACC_WIDTH*p +: ACC_WIDTH] = acc[p];
        end
    endgenerate
endmodule