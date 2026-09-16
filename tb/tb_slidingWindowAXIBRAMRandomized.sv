`timescale 1ns / 1ps
class StallGen;
    rand int stall_type;
    rand int stall_duration;

    constraint c_type {
        stall_type inside {[0:3]};
    }
    constraint c_duration {
        (stall_type != 0) -> stall_duration inside {[1:5]};
    }

    function void display();
        $display("Stall Type = %0d, Stall Duration = %0d", stall_type, stall_duration);
    endfunction
endclass

module tb_slidingWindowAXIBRAMRandomized;
    localparam int DATA_WIDTH = 8;
    localparam int ROW_LENGTH = 3;
    logic clk;
    logic rstn;
    logic [DATA_WIDTH-1:0] s_axis_tdata;
    logic s_axis_tvalid;
    logic s_axis_tready;
    logic [DATA_WIDTH-1:0] m_axis_tdata [0:2] [0:2];
    logic m_axis_tvalid;
    logic m_axis_tready;
    StallGen sg = new();

    slidingWindowAXIBRAM #(.DATA_WIDTH(DATA_WIDTH),
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
        for (int i = 1; i < (ROW_LENGTH*ROW_LENGTH)+1;i++) begin
            @(negedge clk);
            s_axis_tdata = i;
            void'(sg.randomize());
            sg.display();
            case (sg.stall_type)
                0: begin
                    // No stall
                end
                1: begin
                    s_axis_tvalid = 0;
                    repeat (sg.stall_duration) @(negedge clk);
                    s_axis_tvalid = 1;
                end
                2: begin
                    m_axis_tready = 0;
                    repeat (sg.stall_duration) @(negedge clk);
                    m_axis_tready = 1;
                end
                3: begin
                    m_axis_tready = 0;
                    s_axis_tvalid = 0;
                    repeat (sg.stall_duration) @(negedge clk);
                    m_axis_tready = 1;
                    s_axis_tvalid = 1;
                end
            endcase
        end
        repeat (6) begin
            @(negedge clk);
            s_axis_tdata = '0;
        end
        @(negedge clk);
        $finish();
    end
    
  logic [DATA_WIDTH-1:0] sent_pixels [0:63];
    int n;
    logic expected_valid;
    assign expected_valid = (n >= ROW_LENGTH + 4);

    always @(negedge clk) begin
        if (expected_valid == m_axis_tvalid) begin
        end else begin
            $display("expected_valid = %0d not matching m_axis_tvalid = %0d, n = %0d, time = %0d", expected_valid, m_axis_tvalid, n, $time);
        
        end
    end


    function automatic logic [DATA_WIDTH-1:0] predict (int n, int offset);
        int idx;
        idx = n - offset;
        if (idx < 0)
            return '0;
        else 
            return sent_pixels[idx];
    endfunction

    function automatic void get_masks (int n, output logic right_ok, output logic left_ok, output logic top_ok, output logic bottom_ok);
        int center_index;
        int center_row, center_col;

        center_index = n - (ROW_LENGTH + 4);

        if (center_index >= 0) begin
            center_row = center_index / ROW_LENGTH;
            center_col = center_index % ROW_LENGTH;
        end else begin
            center_row = '0;
            center_col = '0;
        end

        right_ok = (center_col <= ROW_LENGTH - 2);
        left_ok = (center_col >= 1);
        top_ok = (center_row >= 1);
        bottom_ok = (center_row <= ROW_LENGTH - 2);

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
            logic right_ok, left_ok, top_ok, bottom_ok;
            logic [DATA_WIDTH-1:0] expected_masked;
            get_masks(n, right_ok, left_ok, top_ok, bottom_ok);

            expected_masked = (top_ok && right_ok) ? predict(n-1, 2*ROW_LENGTH+2) : '0;
            if (m_axis_tdata[0][0] !== expected_masked)
                $display("MISMATCH [0][0] at time %0t: expected %0d, got %0d",$time, expected_masked, m_axis_tdata[0][0]);

            expected_masked = (top_ok) ? predict(n-1, 2*ROW_LENGTH + 3) : '0;
            if (m_axis_tdata[0][1] !== expected_masked)
                $display("MISMATCH [0][1] at time %0t: expected %0d, got %0d",$time, expected_masked, m_axis_tdata[0][1]);

            expected_masked = (top_ok && left_ok) ? predict(n-1, 2*ROW_LENGTH + 4) : '0;
            if (m_axis_tdata[0][2] !== expected_masked)
                $display("MISMATCH [0][2] at time %0t: expected %0d, got %0d",$time, expected_masked, m_axis_tdata[0][2]);

            expected_masked = (right_ok) ? predict(n-1, ROW_LENGTH+2) : '0;
            if (m_axis_tdata[1][0] !== expected_masked)
                $display("MISMATCH [1][0] at time %0t: expected %0d, got %0d",$time, expected_masked, m_axis_tdata[1][0]);

            expected_masked = predict(n-1, ROW_LENGTH + 3);
            if (m_axis_tdata[1][1] !== expected_masked)
                $display("MISMATCH [1][1] at time %0t: expected %0d, got %0d",$time, expected_masked, m_axis_tdata[1][1]);

            expected_masked = (left_ok) ? predict(n-1, ROW_LENGTH + 4) : '0;
            if (m_axis_tdata[1][2] !== expected_masked)
                $display("MISMATCH [1][2] at time %0t: expected %0d, got %0d",$time, expected_masked, m_axis_tdata[1][2]);

            expected_masked = (right_ok && bottom_ok) ? predict(n-1, 2) : '0;
            if (m_axis_tdata[2][0] !== expected_masked)
                $display("MISMATCH [2][0] at time %0t: expected %0d, got %0d",$time, expected_masked, m_axis_tdata[2][0]);

            expected_masked = (bottom_ok) ? predict(n-1, 3) : '0;
            if (m_axis_tdata[2][1] !== expected_masked)
                $display("MISMATCH [2][1] at time %0t: expected %0d, got %0d",$time, expected_masked, m_axis_tdata[2][1]);

            expected_masked = (left_ok && bottom_ok) ? predict(n-1, 4) : '0;
            if (m_axis_tdata[2][2] !== expected_masked)
                $display("MISMATCH [2][2] at time %0t: expected %0d, got %0d",$time, expected_masked, m_axis_tdata[2][2]);
            

        end
        

    end
endmodule