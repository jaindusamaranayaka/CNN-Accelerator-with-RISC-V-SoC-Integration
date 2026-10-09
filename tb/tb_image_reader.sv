module tb_image_reader;

    localparam int DATA_WIDTH = 8;
    localparam int ADDR_W = 11;
    localparam int DRAIN = 2;
    localparam int MEM_BYTES = 2048;

    logic clk;
    logic rstn;
    logic start;
    logic [ADDR_W-1:0] img_base;
    logic [ADDR_W-1:0] img_len;
    logic busy;
    logic [ADDR_W-1:0] mem_raddr;
    logic [DATA_WIDTH-1:0] mem_rdata;
    logic [DATA_WIDTH-1:0] m_axis_tdata;
    logic m_axis_tvalid;
    logic m_axis_tuser;
    logic m_axis_tready;

    image_reader #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_W(ADDR_W),
        .DRAIN(DRAIN)
    ) dut (.*);

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    logic [DATA_WIDTH-1:0] mem_model [0:MEM_BYTES-1];

    initial begin
        for (int i = 0; i < MEM_BYTES; i++) begin
            mem_model[i] = $urandom();
        end
    end

    always @(posedge clk) begin
            mem_rdata <= mem_model[mem_raddr];
    end

    int exp_base, exp_len; // Base and Length of the run being checked
    int k; // Position of current pixel
    int out_count; // Number of pixels that came out 
    int errors = 0; // Total error

    initial begin
        rstn = 0;
        start = 0;
        img_base = 0;
        img_len = 0;
        m_axis_tready = 1;
        repeat (2) @(negedge clk);
        rstn = 1;
        run_image(0,5);
        run_image(1024,784);
        @(negedge clk);
        exp_base = 0;
        exp_len = 784;
        img_base = 0;
        img_len = 784;
        start = 1;
        @(negedge clk);
        start = 0;
        repeat(100) @(negedge clk);
        img_base = 1024;
        start = 1;
        @(negedge clk);
        start = 0;
        wait(busy == 0);
        if (out_count != 786) begin
            errors++;
            $display("Final test is wrong!, out count = %0d", out_count);
        end

        $display("Errors = %0d", errors);
        $finish();
    end
    always @(posedge clk) begin
            if (rstn && m_axis_tvalid) begin
                if (m_axis_tuser) begin
                    k = 0;
                    out_count = 0;
                end
                if ((k == 0) && (m_axis_tuser == 0)) begin
                    errors++;
                    $display("k = %0d, m_axis_tuser = %0h", k, m_axis_tuser);
                end
                if (k < exp_len) begin
                    if (m_axis_tdata != mem_model[exp_base + k]) begin
                        errors++;
                        $display("Memory model doesn't match the actual output, m_axis_tdata = %0h, mem_model = %0h", m_axis_tdata, mem_model[exp_base + k]);
                    end
                end else begin
                    if (m_axis_tdata != 0) begin
                        errors++;
                        $display("Drain pixel doesn't match with the model, k = %0d, m_axis_tdata = %0h", k, m_axis_tdata);
                    end
                end

                if (k > 0 && m_axis_tuser == 1) begin
                    errors++;
                    $display("K is greater than zero but tusre is 1, k = %0d, m_axis_tuser = %0d", k, m_axis_tuser);
                end
                k++;
                out_count++;
            end
    end

    task automatic run_image(input int base,input int len);
        exp_base = base;
        exp_len = len;
        @(negedge clk);
        img_base = base;
        img_len = len;
        start = 1;
        @(negedge clk);
        start = 0;
        wait (busy == 0);
        
        if (out_count != (len + DRAIN)) begin
            errors++;
            $display("Out count is wrong, out_count = %0d, len = %0d, DRAIN = 2",out_count, len);
        end

        repeat(3) @(posedge clk);

    endtask
endmodule