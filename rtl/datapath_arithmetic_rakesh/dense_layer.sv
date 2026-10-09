`timescale 1 ns / 1 ps

module dense_layer (
    input  logic clk,
    input  logic rst_n,

    input  logic        weight_wr_en,
    input  logic [31:0] weight_addr,
    input  logic [31:0] weight_wdata,

    input  logic        accel_start,
    input  logic        valid_in,
    input  logic [7:0]  data_in,

    output logic        valid_out,
    output logic signed [31:0] logits [0:9]
);
    logic signed [7:0] w_mem [0:9][0:195];
    logic signed [15:0] biases [0:9];

    wire [3:0] nid = weight_addr[13:10];
    wire [7:0] pid = weight_addr[9:2];

    always_ff @(posedge clk) begin
        if (weight_wr_en) begin
            if (weight_addr[15:10] == 6'h0A && pid < 10) begin
                biases[pid] <= weight_wdata[15:0];
            end else if (nid < 10 && pid < 196) begin
                w_mem[nid][pid] <= weight_wdata[7:0];
            end
        end
    end

    logic [7:0] pixel_count;
    logic signed [31:0] accum [0:9];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_count <= 0;
            valid_out <= 0;
            for (int i=0; i<10; i++) begin
                accum[i] <= 0;
                logits[i] <= 0;
            end
        end else if (accel_start) begin
            pixel_count <= 0;
            valid_out <= 0;
            for (int i=0; i<10; i++) begin
                accum[i] <= 0;
            end
        end else begin
            valid_out <= 0;
            if (valid_in) begin
                for (int i=0; i<10; i++) begin
                    accum[i] <= accum[i] + $signed({1'b0, data_in}) * w_mem[i][pixel_count];
                end

                if (pixel_count == 195) begin
                    pixel_count <= 0;
                    valid_out <= 1;
                    for (int i=0; i<10; i++) begin
                        logits[i] <= accum[i] + $signed({1'b0, data_in}) * w_mem[i][pixel_count] + biases[i];
                        accum[i] <= 0;
                    end
                end else begin
                    pixel_count <= pixel_count + 1;
                end
            end
        end
    end
endmodule
