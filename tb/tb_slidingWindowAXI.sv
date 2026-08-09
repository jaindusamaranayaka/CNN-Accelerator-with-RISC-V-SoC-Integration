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

    // Instantiate Device Under Test (DUT)
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

    initial begin
        $dumpfile("dump.vcd");$dumpvars(0,dut);
    end

    // Clock Generator
    always #(CLK_PERIOD / 2) clk = ~clk;

    // Test stimulus
    initial begin
        // Initialize signals
        clk           = 0;
        rstn          = 0;
        s_axis_tdata  = 0;
        s_axis_tvalid = 0;
        m_axis_tready = 1; // Downstream ready by default

        // Apply Reset
        #(CLK_PERIOD * 2);
        rstn = 1;
        $display("--- Reset Released ---");

        // Step 1: Stream sequential pixels into the module
        for (int pixel = 1; pixel <= 40; pixel++) begin
            @(posedge clk);
            s_axis_tvalid <= 1'b1;
            s_axis_tdata  <= pixel;

            // Wait if upstream handshaking is stalled
            while (!s_axis_tready) @(posedge clk);
        end

        // Step 2: Inject backpressure (downstream not ready) mid-stream
        $display("--- Applying Downstream Backpressure ---");
        m_axis_tready <= 1'b0;
        
        for (int pixel = 41; pixel <= 45; pixel++) begin
            @(posedge clk);
            s_axis_tvalid <= 1'b1;
            s_axis_tdata  <= pixel;
        end

        // Step 3: Release backpressure
        @(posedge clk);
        $display("--- Releasing Backpressure ---");
        m_axis_tready <= 1'b1;

        // Stream remaining pixels
        for (int pixel = 46; pixel <= 64; pixel++) begin
            @(posedge clk);
            s_axis_tvalid <= 1'b1;
            s_axis_tdata  <= pixel;
        end

        // End Stream
        @(posedge clk);
        s_axis_tvalid <= 1'b0;

        #(CLK_PERIOD * 10);
        $display("--- Simulation Completed ---");
        $finish;
    end

    // Monitor output window once primed
    always @(posedge clk) begin
        if (m_axis_tvalid && m_axis_tready) begin
            $display("Time %0t ps | Valid Matrix:", $time);
            $display("  [%3d %3d %3d]", m_axis_tdata[0][0], m_axis_tdata[0][1], m_axis_tdata[0][2]);
            $display("  [%3d %3d %3d]", m_axis_tdata[1][0], m_axis_tdata[1][1], m_axis_tdata[1][2]);
            $display("  [%3d %3d %3d]", m_axis_tdata[2][0], m_axis_tdata[2][1], m_axis_tdata[2][2]);
            $display("-----------------------------");
        end
    end

endmodule