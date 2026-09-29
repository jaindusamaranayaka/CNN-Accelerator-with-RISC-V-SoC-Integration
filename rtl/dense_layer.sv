`timescale 1 ns / 1 ps

module dense_layer (
    input  logic clk,
    input  logic rst_n,
    
    // CPU Interface for Weights (mapped at 0x60000000)
    input  logic        weight_wr_en,
    input  logic [31:0] weight_addr, 
    input  logic [31:0] weight_wdata,
    
    // Pipeline Interface
    input  logic        valid_in,
    input  logic [7:0]  data_in, // from max pool
    
    // Output to Argmax
    output logic        valid_out,
    output logic signed [31:0] logits [0:9]
);
    // 10 memories, each 169 deep, 8-bit wide (signed)
    logic signed [7:0] w_mem [0:9][0:168];
    // 10 biases
    logic signed [15:0] biases [0:9];
    
    // Write logic
    // Neuron ID from address: bit 13:10. Pixel ID from address: bit 9:2.
    wire [3:0] nid = weight_addr[13:10];
    wire [7:0] pid = weight_addr[9:2]; // up to 168
    
    always_ff @(posedge clk) begin
        if (weight_wr_en) begin
            if (weight_addr[15:10] == 6'h0A && pid < 10) begin 
                // 0x2800 is 10_1000_0000_0000. Bits 15:10 = 001010 = 0x0A.
                biases[pid] <= weight_wdata[15:0];
            end else if (nid < 10 && pid < 169) begin
                w_mem[nid][pid] <= weight_wdata[7:0];
            end
        end
    end
    
    // Datapath logic
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
        end else begin
            valid_out <= 0;
            if (valid_in) begin
                for (int i=0; i<10; i++) begin
                    accum[i] <= accum[i] + $signed({1'b0, data_in}) * w_mem[i][pixel_count];
                end
                
                if (pixel_count == 168) begin
                    pixel_count <= 0;
                    valid_out <= 1;
                    for (int i=0; i<10; i++) begin
                        logits[i] <= accum[i] + $signed({1'b0, data_in}) * w_mem[i][pixel_count] + biases[i];
                        accum[i] <= 0; // Clear for next image
                    end
                end else begin
                    pixel_count <= pixel_count + 1;
                end
            end
        end
    end
endmodule
