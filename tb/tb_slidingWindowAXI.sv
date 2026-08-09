`timescale 1ns / 1ps

module tb_slidingWindowAXI;

    parameter int DATA_WIDTH = 8;
    parameter int ROW_LENGTH = 8;
    parameter int CLK_PERIOD = 10;

    // DUT Signals
    logic                  clk;
    logic                  rstn;
    logic [DATA_WIDTH-1:0] s_axis_tdata;
    logic                  s_axis_tvalid;
    logic                  s_axis_tready;

    logic [DATA_WIDTH-1:0] m_axis_tdata [0:2][0:2];
    logic                  m_axis_tvalid;
    logic                  m_axis_tready;

    // Instantiate DUT
    slidingWindowAXI #(
        .DATA_WIDTH(DATA_WIDTH),
        .ROW_LENGTH(ROW_LENGTH)
    ) dut (
        .clk          (clk),
        .rstn         (rstn),
        .s_axis_tdata (s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .m_axis_tdata (m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready)
    );

    // Clock Generator
    always #(CLK_PERIOD / 2) clk = ~clk;

    // Direct assignment prevents 1-cycle non-blocking delay
    int pixel_counter;
    assign s_axis_tdata = pixel_counter[DATA_WIDTH-1:0];

    // Pixel Counter Increment on Valid Handshake
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            pixel_counter <= 1;
        end else if (s_axis_tvalid && s_axis_tready) begin
            pixel_counter <= pixel_counter + 1;
        end
    end

    // Test Control Sequence
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_slidingWindowAXI);

        clk           = 0;
        rstn          = 0;
        s_axis_tvalid = 0;
        m_axis_tready = 1;

        // Reset
        #(CLK_PERIOD * 2);
        rstn = 1;
        $display("--- Reset Released ---");

        // Start Streaming
        @(posedge clk);
        s_axis_tvalid = 1'b1;

        // Wait until pixel 24 is handshaked
        wait(pixel_counter == 25);

        // Apply Backpressure
        $display("--- Applying Downstream Backpressure ---");
        m_axis_tready = 1'b0;

        repeat (4) @(posedge clk);

        // Release Backpressure
        $display("--- Releasing Backpressure ---");
        m_axis_tready = 1'b1;

        // Run through remaining pixels
        wait(pixel_counter == 49);

        @(posedge clk);
        s_axis_tvalid = 1'b0;

        #(CLK_PERIOD * 10);
        $display("--- Simulation Completed ---");
        $finish;
    end

    // Console Logger
    always @(posedge clk) begin
        if (m_axis_tvalid && m_axis_tready) begin
            $display("Time %0t ps | Valid Matrix Output:", $time);
            $display("  [%3d %3d %3d]", m_axis_tdata[0][0], m_axis_tdata[0][1], m_axis_tdata[0][2]);
            $display("  [%3d %3d %3d]", m_axis_tdata[1][0], m_axis_tdata[1][1], m_axis_tdata[1][2]);
            $display("  [%3d %3d %3d]", m_axis_tdata[2][0], m_axis_tdata[2][1], m_axis_tdata[2][2]);
            $display("-----------------------------");
        end
    end

endmodule