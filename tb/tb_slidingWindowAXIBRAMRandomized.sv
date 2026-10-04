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

    localparam int DATA_WIDTH       = 8;
    localparam int ROW_LENGTH       = 5;
    localparam bit PADDING          = 0;
    localparam int FRAMES           = 2;
    localparam int DRAIN            = PADDING ? (ROW_LENGTH + 3) : 2;
    localparam int EXPECTED_WINDOWS = FRAMES * (PADDING ? (ROW_LENGTH * ROW_LENGTH)
                                                        : ((ROW_LENGTH - 2) * (ROW_LENGTH - 2)));

    logic                  clk;
    logic                  rstn;

    logic [DATA_WIDTH-1:0] s_axis_tdata;
    logic                  s_axis_tvalid;
    logic                  s_axis_tready;
    logic                  s_axis_tuser;

    logic [DATA_WIDTH-1:0] m_axis_tdata [0:2] [0:2];
    logic                  m_axis_tvalid;
    logic                  m_axis_tready;

    logic [DATA_WIDTH-1:0] sent_pixels [0:63];
    int                    n;
    logic                  tb_pending;
    logic                  expected_valid;
    int                    transfers = 0;

    StallGen sg = new();

    slidingWindowAXIBRAM #(
        .DATA_WIDTH(DATA_WIDTH),
        .ROW_LENGTH(ROW_LENGTH),
        .PADDING(PADDING)
    ) dut (.*);

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, dut);

        rstn          = 0;
        #10;
        rstn          = 1;
        m_axis_tready = 1;
        s_axis_tvalid = 1;
        s_axis_tuser  = 0;

        for (int f = 0; f < FRAMES; f++) begin
            for (int i = 0; i < ROW_LENGTH * ROW_LENGTH; i++) begin
                @(negedge clk);
                s_axis_tdata = 100 * f + i + 1;
                s_axis_tuser = (i == 0);

                void'(sg.randomize());
                sg.display();

                case (sg.stall_type)
                    0: begin
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

            repeat (DRAIN) begin
                @(negedge clk);
                s_axis_tdata = '0;
                s_axis_tuser = 0;
            end
        end

        @(negedge clk);
        s_axis_tvalid = 0;
        repeat (2) @(negedge clk);

        if (transfers != EXPECTED_WINDOWS)
            $display("COUNT MISMATCH: expected %0d windows, got %0d", EXPECTED_WINDOWS, transfers);
        else
            $display("COUNT OK: %0d windows", transfers);

        $finish();
    end

    always @(posedge clk) begin
        if (!rstn) begin
            n          = 0;
            tb_pending = 0;
        end else begin
            if (s_axis_tvalid && s_axis_tready)
                tb_pending = 1'b1;
            else if (expected_valid && m_axis_tready)
                tb_pending = 1'b0;

            if (s_axis_tvalid && s_axis_tready) begin
                if (s_axis_tuser) n = 0;
                sent_pixels[n] = s_axis_tdata;
                n              = n + 1;
            end
        end
    end

    always @(posedge clk) begin
        if (rstn && m_axis_tvalid && m_axis_tready)
            transfers++;
    end

    function automatic logic [DATA_WIDTH-1:0] predict(int n, int offset);
        int idx;
        idx = n - offset;
        if (idx < 0)
            return '0;
        else
            return sent_pixels[idx];
    endfunction

    function automatic void get_masks(
        input  int   n,
        output logic right_ok,
        output logic left_ok,
        output logic top_ok,
        output logic bottom_ok
    );
        int center_index;
        int center_row;
        int center_col;

        center_index = n - (ROW_LENGTH + 4);

        if (center_index >= 0) begin
            center_row = center_index / ROW_LENGTH;
            center_col = center_index % ROW_LENGTH;
        end else begin
            center_row = 0;
            center_col = 0;
        end

        right_ok  = (center_col <= ROW_LENGTH - 2);
        left_ok   = (center_col >= 1);
        top_ok    = (center_row >= 1);
        bottom_ok = (center_row <= ROW_LENGTH - 2);
    endfunction

    always_comb begin
        logic r_ok, l_ok, t_ok, b_ok;
        get_masks(n, r_ok, l_ok, t_ok, b_ok);
        expected_valid = (n >= ROW_LENGTH + 4) && tb_pending
                         && (PADDING || (r_ok && l_ok && t_ok && b_ok));
    end

    always @(negedge clk) begin
        if (expected_valid != m_axis_tvalid)
            $display("expected_valid = %0d not matching m_axis_tvalid = %0d, n = %0d, time = %0d",
                     expected_valid, m_axis_tvalid, n, $time);
    end

    always @(negedge clk) begin
        if (m_axis_tvalid) begin
            logic                  right_ok, left_ok, top_ok, bottom_ok;
            logic [DATA_WIDTH-1:0] expected_masked;

            get_masks(n, right_ok, left_ok, top_ok, bottom_ok);

            expected_masked = (top_ok && left_ok) ? predict(n-1, 2*ROW_LENGTH + 4) : '0;
            if (m_axis_tdata[0][0] !== expected_masked)
                $display("MISMATCH [0][0] at time %0t: expected %0d, got %0d", $time, expected_masked, m_axis_tdata[0][0]);

            expected_masked = (top_ok) ? predict(n-1, 2*ROW_LENGTH + 3) : '0;
            if (m_axis_tdata[0][1] !== expected_masked)
                $display("MISMATCH [0][1] at time %0t: expected %0d, got %0d", $time, expected_masked, m_axis_tdata[0][1]);

            expected_masked = (top_ok && right_ok) ? predict(n-1, 2*ROW_LENGTH + 2) : '0;
            if (m_axis_tdata[0][2] !== expected_masked)
                $display("MISMATCH [0][2] at time %0t: expected %0d, got %0d", $time, expected_masked, m_axis_tdata[0][2]);

            expected_masked = (left_ok) ? predict(n-1, ROW_LENGTH + 4) : '0;
            if (m_axis_tdata[1][0] !== expected_masked)
                $display("MISMATCH [1][0] at time %0t: expected %0d, got %0d", $time, expected_masked, m_axis_tdata[1][0]);

            expected_masked = predict(n-1, ROW_LENGTH + 3);
            if (m_axis_tdata[1][1] !== expected_masked)
                $display("MISMATCH [1][1] at time %0t: expected %0d, got %0d", $time, expected_masked, m_axis_tdata[1][1]);

            expected_masked = (right_ok) ? predict(n-1, ROW_LENGTH + 2) : '0;
            if (m_axis_tdata[1][2] !== expected_masked)
                $display("MISMATCH [1][2] at time %0t: expected %0d, got %0d", $time, expected_masked, m_axis_tdata[1][2]);

            expected_masked = (left_ok && bottom_ok) ? predict(n-1, 4) : '0;
            if (m_axis_tdata[2][0] !== expected_masked)
                $display("MISMATCH [2][0] at time %0t: expected %0d, got %0d", $time, expected_masked, m_axis_tdata[2][0]);

            expected_masked = (bottom_ok) ? predict(n-1, 3) : '0;
            if (m_axis_tdata[2][1] !== expected_masked)
                $display("MISMATCH [2][1] at time %0t: expected %0d, got %0d", $time, expected_masked, m_axis_tdata[2][1]);

            expected_masked = (right_ok && bottom_ok) ? predict(n-1, 2) : '0;
            if (m_axis_tdata[2][2] !== expected_masked)
                $display("MISMATCH [2][2] at time %0t: expected %0d, got %0d", $time, expected_masked, m_axis_tdata[2][2]);
        end
    end

endmodule