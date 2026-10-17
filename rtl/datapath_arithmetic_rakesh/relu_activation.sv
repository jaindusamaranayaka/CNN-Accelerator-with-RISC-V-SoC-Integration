module relu_activation #(
    parameter DATA_WIDTH = 8
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          valid_in,
    input  logic signed [DATA_WIDTH-1:0]  data_in,     // from quant_saturate_unit
    output logic signed [DATA_WIDTH-1:0]  data_out,
    output logic                          valid_out
);

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        data_out  <= '0;
        valid_out <= '0;
    end else begin
        data_out  <= data_in[DATA_WIDTH-1] ? '0 : data_in;
        valid_out <= valid_in;
    end
end

endmodule