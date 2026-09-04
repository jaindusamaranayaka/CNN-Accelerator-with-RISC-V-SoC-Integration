`include "lineBufferAXI.sv"
`timescale 1ns / 1ps

module slidingWindowAXI #(
    parameter int DATA_WIDTH = 8,
    parameter int ROW_LENGTH = 8
) (
    input logic clk,
    input logic rstn,

    // Input Pixel Stream (Slave)
    input logic [DATA_WIDTH-1:0] s_axis_tdata,
    input logic s_axis_tvalid,
    output logic s_axis_tready,

    // 3x3 Matrix Output Stream (Master)
    output logic [DATA_WIDTH-1:0] m_axis_tdata [0:2] [0:2],
    output logic m_axis_tvalid,
    input logic m_axis_tready
);

    logic [31:0] pixel_count;  // free-running, non-saturating count of completed
                               // transfers — unlike the old valid_counter, this
                               // must NOT freeze, since center_index below needs
                               // it to keep advancing for the whole image, not
                               // just up to a one-time startup threshold.
    logic en;
    logic [$clog2(ROW_LENGTH)-1 : 0] live_col;
    logic [$clog2(ROW_LENGTH)-1 : 0] live_row;
    logic window_valid;

    assign s_axis_tready = m_axis_tready;
    assign en = s_axis_tvalid && s_axis_tready;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            pixel_count <= '0;
            m_axis_tvalid <= 1'b0;
        end else begin
            if (en) begin
                pixel_count <= pixel_count + 1'b1;
                
            end
        end
    end
    assign m_axis_tvalid = window_valid;
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            live_row <= '0;
        end else begin
            if (en) begin
                if (live_col == ROW_LENGTH-1) begin
                    live_row <= live_row + 1;
                end
            end
        end
    end

    // window_valid: true once the CENTER slot (reg_row_2[1]) holds a real pixel.
    // Center's true index = live_index - (ROW_LENGTH+1) = (pixel_count-1) - (ROW_LENGTH+1)
    //                      = pixel_count - (ROW_LENGTH+2)
    assign window_valid = (pixel_count >= ROW_LENGTH + 2);

    always_ff @(posedge clk or negedge rstn) begin // Horizontal
        if (!rstn) begin
            live_col <= '0;
        end else begin
            if (en) begin
                if (live_col == ROW_LENGTH - 1) begin
                    live_col <= '0;
                end else begin
                    live_col <= live_col + 1;
                end
            end
        end
    end

    logic [DATA_WIDTH-1:0] line_out_1;
    logic [DATA_WIDTH-1:0] line_out_2;

    lineBufferAXI #(
        .DATA_WIDTH(DATA_WIDTH),
        .ROW_LENGTH(ROW_LENGTH)
    ) buffer1 (
        .clk(clk),
        .rstn(rstn),
        .wr_en(en),
        .data_in(s_axis_tdata),
        .data_out(line_out_1)
    );

    lineBufferAXI #(
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

    // ---- Padding mask, derived from the CENTER's true (row,col), not from
    // ---- live_row/live_col subtracted independently (that was the bug:
    // ---- it doesn't account for borrowing across a row boundary).
    int center_index;
    logic [$clog2(ROW_LENGTH)-1:0] center_row, center_col;
    logic right_ok, left_ok, top_ok;

    always_comb begin
        center_index = pixel_count - (ROW_LENGTH + 2);
        if (center_index >= 0) begin
            center_row = center_index / ROW_LENGTH;
            center_col = center_index % ROW_LENGTH;
        end else begin
            center_row = '0;
            center_col = '0;
        end
    end

    // NOTE: bottom edge / right-past-last-row is NOT handled here — that
    // needs image height H, which this module doesn't receive yet. Only
    // left and top edges are handled (documented open item).
    assign right_ok = (center_col <= ROW_LENGTH-2);  // slot [0] of each reg_row (one col right of center)
    assign left_ok  = (center_col >= 1);             // slot [2] of each reg_row (one col left of center)
    assign top_ok   = (center_row >= 1);              // reg_row_3 (one row above center)

    always_comb begin
        m_axis_tdata[0][0] = (top_ok && right_ok) ? reg_row_3[0] : '0;
        m_axis_tdata[0][1] = (top_ok)             ? reg_row_3[1] : '0;
        m_axis_tdata[0][2] = (top_ok && left_ok)  ? reg_row_3[2] : '0;

        m_axis_tdata[1][0] = (right_ok) ? reg_row_2[0] : '0;
        m_axis_tdata[1][1] = reg_row_2[1];
        m_axis_tdata[1][2] = (left_ok)  ? reg_row_2[2] : '0;

        m_axis_tdata[2][0] = (right_ok) ? reg_row_1[0] : '0;
        m_axis_tdata[2][1] = reg_row_1[1];
        m_axis_tdata[2][2] = (left_ok)  ? reg_row_1[2] : '0;
    end

endmodule