module window_wrapper #(
    parameter int ROW_LENGTH = 28,
    parameter bit PADDING = 0,
    parameter int DATA_WIDTH = 8
) (
    input logic clk,
    input logic rstn,
    input logic [DATA_WIDTH-1:0] pixels,
    input logic s_axis_tvalid,
    input logic s_axis_tuser,
    input logic m_axis_tready,
    output logic [9 * DATA_WIDTH - 1:0] window,
    output logic m_axis_tvalid,
    output logic s_axis_tready
);
    logic s_tvalid;
    logic s_tuser;
    logic m_tready;
    logic [DATA_WIDTH-1:0] input_pixels;

    logic [DATA_WIDTH-1:0] dut_window [0:2] [0:2]; 
    logic s_tready;
    logic m_tvalid;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            s_tvalid <= 0;
            s_tuser <= 0;
            m_tready <= 0;
            input_pixels <= '0;
        end else begin
            s_tvalid <= s_axis_tvalid;
            s_tuser <= s_axis_tuser;
            m_tready <= m_axis_tready;
            input_pixels <= pixels;
        end
    end

    slidingWindowAXIBRAM #(
        .DATA_WIDTH(DATA_WIDTH),
        .ROW_LENGTH(ROW_LENGTH),
        .PADDING(PADDING)
    ) dut (
        .clk(clk),
        .rstn(rstn),
        .s_axis_tdata(input_pixels),
        .s_axis_tvalid(s_tvalid),
        .s_axis_tuser(s_tuser),
        .m_axis_tready(m_tready),
        .s_axis_tready(s_tready),
        .m_axis_tvalid(m_tvalid),
        .m_axis_tdata(dut_window)
    );

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            window <= '0;
            s_axis_tready <= 0;
            m_axis_tvalid <= 0;
        end else begin
            s_axis_tready <= s_tready;
            m_axis_tvalid <= m_tvalid;

            window[7:0] <= dut_window[0][0];
            window[15:8] <= dut_window[0][1];
            window[23:16] <= dut_window[0][2];
            window[31:24] <= dut_window[1][0];
            window[39:32] <= dut_window[1][1];
            window[47:40] <= dut_window[1][2];
            window[55:48] <= dut_window[2][0];
            window[63:56] <= dut_window[2][1];
            window[71:64] <= dut_window[2][2];
        
        end

    end



endmodule