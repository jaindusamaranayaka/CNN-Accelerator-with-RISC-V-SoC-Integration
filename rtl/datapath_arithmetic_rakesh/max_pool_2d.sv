`timescale 1 ns / 1 ps

module max_pool_2d
    parameter WIDTH = 26,
    parameter DATA_WIDTH = 8
)(
    input  logic clk,
    input  logic rst_n,
    input  logic accel_start,
    input  logic valid_in,
    input  logic [DATA_WIDTH-1:0] data_in,
    output logic valid_out,
    output logic [DATA_WIDTH-1:0] data_out
);
    logic [4:0] r, c;
    logic [DATA_WIDTH-1:0] line_buf [0:(WIDTH/2)-1];
    logic [DATA_WIDTH-1:0] temp_max;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r <= 0;
            c <= 0;
            valid_out <= 0;
            data_out <= 0;
            temp_max <= 0;
            for (int i=0; i<(WIDTH/2); i++) line_buf[i] <= 0;
        end else if (accel_start) begin
            r <= 0;
            c <= 0;
            valid_out <= 0;
            temp_max <= 0;
        end else begin
            valid_out <= 1'b0;
            if (valid_in) begin
                if (c[0] == 1'b0) begin
                    temp_max <= data_in;
                end else begin
                    automatic logic [DATA_WIDTH-1:0] current_max = (data_in > temp_max) ? data_in : temp_max;
                    if (r[0] == 1'b0) begin
                        line_buf[c[4:1]] <= current_max;
                    end else begin
                        data_out <= (current_max > line_buf[c[4:1]]) ? current_max : line_buf[c[4:1]];
                        valid_out <= 1'b1;
                    end
                end

                if (c == WIDTH - 1) begin
                    c <= 0;
                    if (r == WIDTH - 1) r <= 0;
                    else r <= r + 1;
                end else begin
                    c <= c + 1;
                end
            end
        end
    end
endmodule
