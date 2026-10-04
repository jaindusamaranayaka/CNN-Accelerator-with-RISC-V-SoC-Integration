`timescale 1 ns / 1 ps

module argmax (
    input  logic clk,
    input  logic rst_n,
    input  logic valid_in,
    input  logic signed [31:0] logits [0:9],
    output logic valid_out,
    output logic [3:0] class_id
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 0;
            class_id <= 0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                logic [3:0] best_id;
                logic signed [31:0] best_val;
                best_id = 0;
                best_val = logits[0];
                for (int i=1; i<10; i++) begin
                    if (logits[i] > best_val) begin
                        best_val = logits[i];
                        best_id = i[3:0];
                    end
                end
                class_id <= best_id;
            end
        end
    end
endmodule
