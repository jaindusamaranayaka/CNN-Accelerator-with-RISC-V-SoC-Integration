module slidingWindowAXI #(
    parameter int DATA_WIDTH = 8,
    parameter int ROW_LENGTH = 8
) (
    input logic clk,
    input logic rstn,

    // Input Pixel Stream
    input logic [DATA_WIDTH-1:0] s_axis_tdata,
    input logic s_axis_tvalid,
    output logic s_axis_tready,

    // 3x3 Matrix Output Stream
    output logic [DATA_WIDTH-1:0] m_axis_tdata [0:2] [0:2],
    output logic m_axis_tvalid,
    input logic m_axis_tready
);

    // AXI STREAM BLOCK
    
    localparam int LATENCY = (2 * ROW_LENGTH) + 2; 
    logic [$clog2(LATENCY) : 0] valid_counter;
    logic en; // Clock Enable

    assign s_axis_tready = m_axis_tready || !m_axis_tvalid;
    assign en = s_axis_tvalid && s_axis_tready;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            valid_counter <= '0;
            m_axis_tvalid <= 1'b0;
        end else if (en) begin
            if (valid_counter < LATENCY) begin
                valid_counter <= valid_counter + 1'b1;
                m_axis_tvalid <= 1'b0;
            end else begin 
                m_axis_tvalid <= 1'b1;
            end
        end
    end

    // SLIDING WINDOW BLOCK

    logic [DATA_WIDTH-1:0] line_out_1;
    logic [DATA_WIDTH-1:0] line_out_2;

    lineBuffer  #(
        .DATA_WIDTH(DATA_WIDTH),
        .ROW_LENGTH(ROW_LENGTH)
    ) buffer1 (
        .clk(clk),
        .rstn(rstn),
        .wr_en(en),
        .data_in(s_axis_tdata),
        .data_out(line_out_1)
    );

    lineBuffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .ROW_LENGTH(ROW_LENGTH)
    ) buffer2 (
        .clk(clk),
        .rstn(rstn),
        .wr_en(en),
        .data_in(line_out_1),
        .data_out(line_out_2)
    );

    logic [DATA_WIDTH-1:0] reg_row_1 [0:2];
    logic [DATA_WIDTH-1:0] reg_row_2 [0:2];
    logic [DATA_WIDTH-1:0] reg_row_3 [0:2];

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            for (int i = 0; i < 3; i++) begin
                reg_row_1[i] <= '0;
                reg_row_2[i] <= '0;
                reg_row_3[i] <= '0;
            end
        end else if (en) begin

            reg_row_1[0] <= s_axis_tdata;
            reg_row_1[1] <= reg_row_1[0];
            reg_row_1[2] <= reg_row_1[1];

            reg_row_2[0] <= line_out_1;
            reg_row_2[1] <= reg_row_2[0];
            reg_row_2[2] <= reg_row_2[1];

            reg_row_3[0] <= line_out_2;
            reg_row_3[1] <= reg_row_3[0];
            reg_row_3[2] <= reg_row_3[1];
        end
    end

    always_comb begin
        for (int c = 0; c < 3; c++) begin
            m_axis_tdata[0][c] = reg_row_3[c];
            m_axis_tdata[1][c] = reg_row_2[c];
            m_axis_tdata[2][c] = reg_row_1[c];
        end
    end

endmodule
