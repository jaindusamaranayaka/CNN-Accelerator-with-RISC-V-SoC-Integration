// End to end test of the whole dataflow path

// Testbench (CPU) -> port A -> shared BRAM -> port B -> image reader -> pixel stream -> sliding window -> 3x3 windows


// 2 randomized images are created (img0 & img1)
// Write them into the shared memory like a CPU would : 4 pixels at a time (32 bits at a time)
// img0 -> slot 0 (byte 0), img1 -> slot 1 (byte 1024)
// Starts reader on slot 0 until its done then onto slot 1


// Stream check: every pixel entering the window == original image pixel
// Valid check: window's tvalid is high exactly as it is required
// Data check: all 9 bytes of every window is correct
// Count check: 2 images x 26 x 26 = 1352 windows (PADDING = 0)

module tb_image_path;
    localparam int DATA_WIDTH = 8; // Each pixel is 8 bits
    localparam int ROW_LENGTH = 28; // image size: 28 x 28
    localparam bit PADDING = 0; 
    localparam int DEPTH_WORDS = 512; // memory : 512 words = 2 KB
    localparam int WADDR_W = 9; // word address width (port A)
    localparam int ADDR_W = 11; // byte address width (port B)
    localparam int DRAIN = 2; // flush pixels after each image to make window valid
    localparam int IMG_PIXELS = ROW_LENGTH * ROW_LENGTH; // 784

    logic clk;
    logic rstn;

    // CPU to Memory
    logic a_we;
    logic [WADDR_W-1:0] a_waddr;
    logic [31:0] a_wdata;
    logic [3:0] a_wstrb;

    // CPU to Reader Control
    logic start;
    logic [ADDR_W-1:0] img_base;
    logic [ADDR_W-1:0] img_len;
    logic busy;

    // Memory and Reader
    logic [ADDR_W-1:0] mem_raddr;
    logic [DATA_WIDTH-1:0] mem_rdata;

    // Reader to sliding window
    logic [DATA_WIDTH-1:0] px_tdata;
    logic px_tvalid;
    logic px_tuser;
    logic px_tready;

    // Window Output
    logic [DATA_WIDTH-1:0] win_tdata [0:2] [0:2];
    logic win_tvalid;
    logic win_tready;

    // Image References
    logic [DATA_WIDTH-1:0] img0 [0:IMG_PIXELS-1];
    logic [DATA_WIDTH-1:0] img1 [0:IMG_PIXELS-1];


    // Sliding Window
    logic [DATA_WIDTH-1:0] sent_pixels [0:IMG_PIXELS+DRAIN-1]; // pixels that entered the window
    int                    n; // number of pixels in the image
    logic                  tb_pending; // a window is due
    logic                  expected_valid; // predictor for window's actual tvalid
    int                    transfers = 0; // number of windows that came out

    int errors = 0;

    int cur_slot; // current image slot

    image_bram_dp #(
        .DEPTH_WORDS(DEPTH_WORDS)
    ) u_mem (
        .clk(clk),
        .a_we(a_we),
        .a_waddr(a_waddr),
        .a_wdata(a_wdata),
        .a_wstrb(a_wstrb),
        .b_raddr(mem_raddr),
        .b_rdata(mem_rdata)
    );

    image_reader #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_W(ADDR_W),
        .DRAIN(DRAIN)
    ) u_reader (
        .clk(clk),
        .rstn(rstn),
        .start(start),
        .img_base(img_base),
        .img_len(img_len),
        .busy(busy),
        .mem_raddr(mem_raddr),
        .mem_rdata(mem_rdata),
        .m_axis_tdata(px_tdata),
        .m_axis_tvalid(px_tvalid),
        .m_axis_tuser(px_tuser),
        .m_axis_tready(px_tready)
    );

    slidingWindowAXIBRAM #(
        .DATA_WIDTH(DATA_WIDTH),
        .ROW_LENGTH(ROW_LENGTH),
        .PADDING(PADDING)
    ) u_window (
        .clk(clk),
        .rstn(rstn),
        .s_axis_tdata(px_tdata),
        .s_axis_tvalid(px_tvalid),
        .s_axis_tuser(px_tuser),
        .s_axis_tready(px_tready),
        .m_axis_tdata(win_tdata),
        .m_axis_tvalid(win_tvalid),
        .m_axis_tready(win_tready)
    );
    
    // 10 ns Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end 

    initial begin
        rstn = 0;
        a_we = 0;
        start = 0;
        win_tready = 1;
        repeat (2) @(negedge clk);
        rstn = 1;

        // Creating 2 random images
        for (int k = 0; k < IMG_PIXELS; k++) begin
            img0[k] = $urandom();
            img1[k] = $urandom();
        end

        // Writing into shared memory as a CPU would
        load_image(0,0); // img0 -> word 0 (byte address 0)
        load_image(256,1); // img1 -> word 256 (byte address 1024)

        // Image 1 (slot 0)
        cur_slot = 0;
        img_base = 0;
        img_len = 784;
        start = 1; // Initial one cycle start pulse
        @(negedge clk);
        start = 0;
        @(negedge clk);
        wait (busy == 0); // reader finished (all pixels with drain sent)
        repeat (5) @(negedge clk);

        // Image 2 (slot 1)
        cur_slot = 1;
        img_base = 1024;
        img_len = 784;
        start = 1;
        @(negedge clk);
        start = 0;
        @(negedge clk);
        wait (busy == 0);
        repeat (5) @(negedge clk);

        // Count check : 2 images x 26 x 26 windows
        if (transfers != 1352) begin
            errors++;
        end

        $display("Transfers = %0d, Errors = %0d", transfers, errors);
        $finish();

    end



    // Records every pixel that enters the window and checks against original image
    always @(posedge clk) begin
        if (!rstn) begin
            n          = 0;
            tb_pending = 0;
        end else begin
            // pending flag set to 1 when a pixel enters
            // cleared when the window is taken
            if (px_tvalid && px_tready)
                tb_pending = 1'b1;
            else if (expected_valid && win_tready)
                tb_pending = 1'b0;

            if (px_tvalid && px_tready) begin
                if (px_tuser) n = 0; // new image begins, reset count  
                sent_pixels[n] = px_tdata; // record pixel
                if (n < IMG_PIXELS) begin
                    if (cur_slot) begin
                        if(px_tdata != img1[n]) begin
                            errors++;
                            $display("Mismatch, px_tdata = %0d, img1[n] = %0d", px_tdata, img1[n]);
                        end
                    end else begin
                        if(px_tdata != img0[n]) begin
                            errors++;
                            $display("Mismatch, px_tdata = %0d, img0[n] = %0d", px_tdata, img0[n]);
                        end
                    end
                end
                n = n + 1;
            end
        end
    end

    // Window counter : counts every window handed downstream
    always @(posedge clk) begin
        if (rstn && win_tvalid && win_tready)
            transfers++;
    end

    // Valid check: window tvalid must match model's tvalid (checked at negedge after everything settles)
    always @(negedge clk) begin
        if (expected_valid != win_tvalid) begin
            errors++;
            $display("expected_valid = %0d not matching m_axis_tvalid = %0d, n = %0d, time = %0d",
                     expected_valid, win_tvalid, n, $time);
        end
    end

    // Data check: all 9 bytes of the window against the model
    always @(negedge clk) begin
        if (win_tvalid) begin
            logic                  right_ok, left_ok, top_ok, bottom_ok;
            logic [DATA_WIDTH-1:0] expected_masked;

            get_masks(n, right_ok, left_ok, top_ok, bottom_ok);

            expected_masked = (top_ok && left_ok) ? predict(n-1, 2*ROW_LENGTH + 4) : '0;
            if (win_tdata[0][0] !== expected_masked) begin
                errors++;
                $display("MISMATCH [0][0] at time %0t: expected %0d, got %0d", $time, expected_masked, win_tdata[0][0]);
            end
            expected_masked = (top_ok) ? predict(n-1, 2*ROW_LENGTH + 3) : '0;
            if (win_tdata[0][1] !== expected_masked) begin
                errors++;
                $display("MISMATCH [0][1] at time %0t: expected %0d, got %0d", $time, expected_masked, win_tdata[0][1]);
            end
            expected_masked = (top_ok && right_ok) ? predict(n-1, 2*ROW_LENGTH + 2) : '0;
            if (win_tdata[0][2] !== expected_masked) begin
                errors++;
                $display("MISMATCH [0][2] at time %0t: expected %0d, got %0d", $time, expected_masked, win_tdata[0][2]);
            end
            expected_masked = (left_ok) ? predict(n-1, ROW_LENGTH + 4) : '0;
            if (win_tdata[1][0] !== expected_masked) begin
                errors++;
                $display("MISMATCH [1][0] at time %0t: expected %0d, got %0d", $time, expected_masked, win_tdata[1][0]);
            end
            expected_masked = predict(n-1, ROW_LENGTH + 3);
            if (win_tdata[1][1] !== expected_masked) begin
                errors++;
                $display("MISMATCH [1][1] at time %0t: expected %0d, got %0d", $time, expected_masked, win_tdata[1][1]);
            end
            expected_masked = (right_ok) ? predict(n-1, ROW_LENGTH + 2) : '0;
            if (win_tdata[1][2] !== expected_masked) begin
                errors++;
                $display("MISMATCH [1][2] at time %0t: expected %0d, got %0d", $time, expected_masked, win_tdata[1][2]);
            end
            expected_masked = (left_ok && bottom_ok) ? predict(n-1, 4) : '0;
            if (win_tdata[2][0] !== expected_masked) begin
                errors++;
                $display("MISMATCH [2][0] at time %0t: expected %0d, got %0d", $time, expected_masked, win_tdata[2][0]);
            end
            expected_masked = (bottom_ok) ? predict(n-1, 3) : '0;
            if (win_tdata[2][1] !== expected_masked) begin
                errors++;
                $display("MISMATCH [2][1] at time %0t: expected %0d, got %0d", $time, expected_masked, win_tdata[2][1]);
            end
            expected_masked = (right_ok && bottom_ok) ? predict(n-1, 2) : '0;
            if (win_tdata[2][2] !== expected_masked) begin
                errors++;
                $display("MISMATCH [2][2] at time %0t: expected %0d, got %0d", $time, expected_masked, win_tdata[2][2]);
            end
        end
        end

    // Expected window valid: A window is due once enough pixels have arrived or
    // a new pixel is pending
    // for valid convolution (PADDING = 0) window center must be not on the image border
    always_comb begin
        logic right, left, top, bottom;
        get_masks(n, right, left, top, bottom);
        expected_valid = (n >= ROW_LENGTH + 4) && tb_pending && (PADDING || (right && left && top && bottom));
    end

    // one CPU store to the memory (port A)
    task automatic write_word (
        input logic [WADDR_W-1:0] addr,
        input logic [31:0] data,
        input logic [3:0] strobe
    );
        @(negedge clk);
        a_we = 1;
        a_waddr = addr;
        a_wdata = data;
        a_wstrb = strobe;
        @(negedge clk);
        a_we = 0;
    endtask

    // Writing a whole image into memory (little endian)
    task automatic load_image (
        input logic [ADDR_W-1:0] word_base,
        input bit slot
    );
        logic [31:0] word;
        for (int w = 0; w < 196; w++) begin
            if (slot) begin
                word = {img1[4*w+3],img1[4*w+2],img1[4*w+1],img1[4*w]};
            end else begin
                word = {img0[4*w+3],img0[4*w+2],img0[4*w+1],img0[4*w]};
            end
            write_word(word_base + w, word, 4'b1111);
        end
    endtask

    // Helper function: pixel that entered 'offset' positions before pixel n
    function automatic logic [DATA_WIDTH-1:0] predict(int n, int offset);
        int idx;
        idx = n - offset;
        if (idx < 0)
            return '0;
        else
            return sent_pixels[idx];
    endfunction
    // Helper function: from pixel count, calculate window center's row / column
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


endmodule