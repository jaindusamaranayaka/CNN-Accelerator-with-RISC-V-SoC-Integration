// maxpool.sv
module maxpool #(
    parameter int DATA_WIDTH  = 8,
    parameter int IMAGE_WIDTH = 26
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic [DATA_WIDTH-1:0] in_data,   
    input  logic                  in_valid,
    input  logic                  sof,        // start of frame
    output logic [DATA_WIDTH-1:0] out_data,
    output logic                  out_valid
);

    localparam int POOL_WIDTH = IMAGE_WIDTH / 2;    // 13
    localparam int CW         = $clog2(IMAGE_WIDTH); // 5 bits
    localparam int KW         = $clog2(POOL_WIDTH);  // 4 bits

    // state 
    logic [CW-1:0]         r, c;
    logic [DATA_WIDTH-1:0] h_reg;
    logic [DATA_WIDTH-1:0] line_buffer [0:POOL_WIDTH-1];

    // combinational
    logic [CW-1:0]         r_eff, c_eff;   // position of the beat being processed
    logic [KW-1:0]         k;              // line_buffer index
    logic [DATA_WIDTH-1:0] h_max;          // horizontal pair-max


    assign r_eff = sof ? '0 : r;
    assign c_eff = sof ? '0 : c;

    assign k     = c_eff[CW-1:1];
    assign h_max = (in_data > h_reg) ? in_data : h_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r         <= '0;
            c         <= '0;
            h_reg     <= '0;
            out_data  <= '0;
            out_valid <= 1'b0;
            for (int i = 0; i < POOL_WIDTH; i++) line_buffer[i] <= '0;
        end else begin
            out_valid <= 1'b0;  // default
            if (in_valid) begin
                if (c_eff[0] == 1'b0) begin
                    // even column
                    h_reg <= in_data;
                end else begin
                    // odd column
                    if (r_eff[0] == 1'b0) begin
                        // even row
                        line_buffer[k] <= h_max;
                    end else begin
                        // odd row:
                        out_data  <= (h_max > line_buffer[k]) ? h_max: line_buffer[k];
                        out_valid <= 1'b1;
                    end
                end

                // advance position (only on a valid beat, so stalls are safe)
                if (c_eff == CW'(IMAGE_WIDTH - 1)) begin
                    c <= '0;
                    r <= (r_eff == CW'(IMAGE_WIDTH - 1)) ? '0 : r_eff + 1'b1;
                end else begin
                    c <= c_eff + 1'b1;
                    r <= r_eff;
                end

            end
        end
    end

endmodule