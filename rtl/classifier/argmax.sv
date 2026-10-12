`timescale 1ns / 1ps

// argmax.sv


module argmax #(
    parameter int N_OUT     = 10,
    parameter int ACC_WIDTH = 24
)(
    input  logic                           clk,
    input  logic                           rst_n,
    input  logic                           valid_in,    
    input  logic [N_OUT*ACC_WIDTH-1:0]     logits_i,    // lane j = [24j+23 : 24j]
    output logic                           valid_out,   
    output logic [$clog2(N_OUT)-1:0]       class_id
);

    localparam int IDX_WIDTH = $clog2(N_OUT);   // 4 bits for 10 classes

    logic signed [ACC_WIDTH-1:0] lg [0:N_OUT-1];

    genvar u;
    generate
        for (u = 0; u < N_OUT; u++) begin : gen_unpack
            assign lg[u] = logits_i[ACC_WIDTH*u +: ACC_WIDTH];
        end
    endgenerate

    logic                        busy;
    logic [IDX_WIDTH-1:0]        cnt;   
    logic [IDX_WIDTH-1:0]        best_id;
    logic signed [ACC_WIDTH-1:0] best_val;

    logic beats_best;
    assign beats_best = (lg[cnt] > best_val);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy      <= 1'b0;
            cnt       <= '0;
            best_id   <= '0;
            best_val  <= '0;
            class_id  <= '0;
            valid_out <= 1'b0;
        end else begin
            valid_out <= 1'b0;       

            if (!busy) begin
                if (valid_in) begin
                    best_val <= lg[0];
                    best_id  <= '0;
                    cnt      <= IDX_WIDTH'(1);
                    busy     <= 1'b1;
                end
            end else begin
                if (beats_best) begin
                    best_val <= lg[cnt];
                    best_id  <= cnt;       
                end

                if (cnt == IDX_WIDTH'(N_OUT - 1)) begin
                    class_id  <= beats_best ? cnt : best_id;
                    valid_out <= 1'b1;
                    busy      <= 1'b0;
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end
        end
    end

endmodule