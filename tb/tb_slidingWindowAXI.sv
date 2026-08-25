`timescale 1ns / 1ps
module tb_slidingWindowAXI;
    localparam int DATA_WIDTH = 8;
    localparam int ROW_LENGTH = 8;
    logic clk;
    logic rstn;
    logic [DATA_WIDTH-1:0] s_axis_tdata;
    logic s_axis_tvalid;
    logic s_axis_tready;
    logic [DATA_WIDTH-1:0] m_axis_tdata [0:2] [0:2];
    logic m_axis_tvalid;
    logic m_axis_tready;

    slidingWindowAXI #(.DATA_WIDTH(DATA_WIDTH),
                           .ROW_LENGTH(ROW_LENGTH)) dut (.*);
    
    initial begin // Clock Driver
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("dump.vcd");$dumpvars(0,dut);
        rstn = 0;
        #10;
        rstn = 1;
        m_axis_tready = 1;
        s_axis_tvalid = 1;
        for (int i = 1; i < 30; i++) begin
          	@(negedge clk);
            s_axis_tdata = i;
            
        end
        @(negedge clk);
        $finish();
    end

    logic [DATA_WIDTH-1:0] sent_pixels [0:30];
    int n;

    function automatic logic [DATA_WIDTH-1:0] predict (int n, int offset);
        int idx;
        idx = n - offset;
        if (idx < 0)
            return '0;
        else 
            return sent_pixels[idx];
    endfunction

    always @(posedge clk) begin
        if (!rstn) begin
            n = 0;
        end else if (s_axis_tvalid && s_axis_tready) begin
            sent_pixels[n] = s_axis_tdata;
            n = n + 1;
        end
    end

    always @(negedge clk) begin // Checker
        if (m_axis_tvalid) begin
            if (m_axis_tdata[0][0] !== predict(n-1, 2*ROW_LENGTH))
                $display("MISMATCH [0][0] at time %0t: expected %0d, got %0d",$time, predict(n-1, 2*ROW_LENGTH), m_axis_tdata[0][0]);
            if (m_axis_tdata[0][1] !== predict(n-1, 2*ROW_LENGTH+1))
                $display("MISMATCH [0][1] at time %0t: expected %0d, got %0d",$time, predict(n-1, 2*ROW_LENGTH+1), m_axis_tdata[0][1]);
            if (m_axis_tdata[0][2] !== predict(n-1, 2*ROW_LENGTH+2))
                $display("MISMATCH [0][2] at time %0t: expected %0d, got %0d",$time, predict(n-1, 2*ROW_LENGTH+2), m_axis_tdata[0][2]);
            if (m_axis_tdata[1][0] !== predict(n-1, ROW_LENGTH))
                $display("MISMATCH [1][0] at time %0t: expected %0d, got %0d",$time, predict(n-1, ROW_LENGTH), m_axis_tdata[1][0]);
            if (m_axis_tdata[1][1] !== predict(n-1, ROW_LENGTH+1))
                $display("MISMATCH [1][1] at time %0t: expected %0d, got %0d",$time, predict(n-1, ROW_LENGTH+1), m_axis_tdata[1][1]);
            if (m_axis_tdata[1][2] !== predict(n-1, ROW_LENGTH+2))
                $display("MISMATCH [1][2] at time %0t: expected %0d, got %0d",$time, predict(n-1, ROW_LENGTH+2), m_axis_tdata[1][2]);
            if (m_axis_tdata[2][0] !== predict(n-1, 0))
                $display("MISMATCH [2][0] at time %0t: expected %0d, got %0d",$time, predict(n-1, 0), m_axis_tdata[2][0]);
            if (m_axis_tdata[2][1] !== predict(n-1, 1))
                $display("MISMATCH [2][1] at time %0t: expected %0d, got %0d",$time, predict(n-1, 1), m_axis_tdata[2][1]);
            if (m_axis_tdata[2][2] !== predict(n-1, 2))
                $display("MISMATCH [2][2] at time %0t: expected %0d, got %0d",$time, predict(n-1, 2), m_axis_tdata[2][2]);
            

        end

    end
endmodule