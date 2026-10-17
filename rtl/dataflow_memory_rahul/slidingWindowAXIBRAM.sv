`timescale 1ns / 1ps

module slidingWindowAXIBRAM #(
    parameter int DATA_WIDTH = 8,
    parameter int ROW_LENGTH = 640,
    parameter bit PADDING = 0
) (
    input logic clk,
    input logic rstn,

    // Input Pixel Stream (Slave)
    input logic [DATA_WIDTH-1:0] s_axis_tdata,
    input logic s_axis_tvalid,
    input logic s_axis_tuser,
    output logic s_axis_tready,

    // 3x3 Matrix Output Stream (Master)
    output logic [DATA_WIDTH-1:0] m_axis_tdata [0:2] [0:2],
    output logic m_axis_tvalid,
    input logic m_axis_tready

);
    localparam int DRAIN = (PADDING) ? ROW_LENGTH + 3 : 2;
    localparam int PIXEL_WIDTH = $clog2(ROW_LENGTH*ROW_LENGTH + DRAIN + 1);
    logic [PIXEL_WIDTH-1:0] pixel_count;

    
    logic pending;
    logic en;   
    logic window_valid;
    logic interior;

    assign s_axis_tready = m_axis_tready;
    assign en = s_axis_tvalid && s_axis_tready;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            pending <= 1'b0;
        end else if (en) begin
            pending <= 1'b1;
        end else if (m_axis_tvalid && m_axis_tready) begin
            pending <= 1'b0;
        end
    end




    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            pixel_count <= '0;
        end else begin
            if (en && s_axis_tuser) begin
                pixel_count <= 1;
            end else if (en && ~s_axis_tuser) begin
                pixel_count <= pixel_count + 1'b1;
            end
        end
    end

    
    assign m_axis_tvalid = window_valid && pending && (PADDING || interior);

    assign window_valid = (pixel_count >= ROW_LENGTH + 4);


    logic [DATA_WIDTH-1:0] line_out_1;
    logic [DATA_WIDTH-1:0] line_out_2;

    lineBufferAXIBRAM #(
        .DATA_WIDTH(DATA_WIDTH),
        .ROW_LENGTH(ROW_LENGTH)
    ) buffer1 (
        .clk(clk),
        .rstn(rstn),
        .wr_en(en),
        .data_in(s_axis_tdata),
        .data_out(line_out_1)
    );

    lineBufferAXIBRAM #(
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
    
    logic [DATA_WIDTH-1:0] s_axis_tdata_delay;
    logic [DATA_WIDTH-1:0] s_axis_tdata_delay2;
    logic [DATA_WIDTH-1:0] line_out_1_delay;
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            s_axis_tdata_delay <= '0;
            s_axis_tdata_delay2 <= '0;
            line_out_1_delay <= '0;
        end else if (en) begin
            s_axis_tdata_delay <= s_axis_tdata;
            s_axis_tdata_delay2 <= s_axis_tdata_delay;
            line_out_1_delay <= line_out_1;
        end 
    end


    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            for (int i = 0; i < 3; i++) begin
                reg_row_1[i] <= '0;
                reg_row_2[i] <= '0;
                reg_row_3[i] <= '0;
            end
        end else if (en) begin
            reg_row_1[0] <= s_axis_tdata_delay2;
            reg_row_1[1] <= reg_row_1[0];
            reg_row_1[2] <= reg_row_1[1];

            reg_row_2[0] <= line_out_1_delay;
            reg_row_2[1] <= reg_row_2[0];
            reg_row_2[2] <= reg_row_2[1];

            reg_row_3[0] <= line_out_2;
            reg_row_3[1] <= reg_row_3[0];
            reg_row_3[2] <= reg_row_3[1];
        end
    end

    logic [$clog2(ROW_LENGTH)-1:0] center_row, center_col;
    logic right_ok, left_ok, top_ok, bottom_ok;
    

    
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            center_row <= '0;
            center_col <= '0;
        end else if (en) begin
            if (s_axis_tuser) begin
                center_row <= '0;
                center_col <= '0;
            end else if (pixel_count == (ROW_LENGTH + 3)) begin
                center_row <= '0;
                center_col <= '0;
            end else if (window_valid) begin
                if (center_col == ROW_LENGTH - 1) begin
                    center_col <= '0;
                    center_row <= center_row + 1'b1;
                end else begin
                    center_col <= center_col + 1'b1;
                end
            end
        end
    end

    assign right_ok = (center_col <= ROW_LENGTH - 2);  
    assign left_ok  = (center_col >= 1);            
    assign top_ok   = (center_row >= 1);     
    assign bottom_ok = (center_row <= ROW_LENGTH - 2);      
    assign interior = (top_ok && bottom_ok && left_ok && right_ok);  
    always_comb begin
        m_axis_tdata[0][0] = (top_ok && left_ok)  ? reg_row_3[2] : '0;
        m_axis_tdata[0][1] = (top_ok)             ? reg_row_3[1] : '0;
        m_axis_tdata[0][2] = (top_ok && right_ok) ? reg_row_3[0] : '0;

        m_axis_tdata[1][0] = (left_ok)  ? reg_row_2[2] : '0;
        m_axis_tdata[1][1] = reg_row_2[1];
        m_axis_tdata[1][2] = (right_ok) ? reg_row_2[0] : '0;

        m_axis_tdata[2][0] = (left_ok && bottom_ok)  ? reg_row_1[2] : '0;
        m_axis_tdata[2][1] = (bottom_ok)             ? reg_row_1[1] : '0;
        m_axis_tdata[2][2] = (right_ok && bottom_ok) ? reg_row_1[0] : '0;
    end
endmodule