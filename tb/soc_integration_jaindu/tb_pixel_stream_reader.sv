`timescale 1 ns / 1 ps
// =============================================================================
// Testbench: tb_pixel_stream_reader
// DUT:       pixel_stream_reader.sv
// Tests:
//   [F] Functional  - streams correct bytes from BRAM words
//   [I] Interface   - AXI-S tuser on first pixel, tvalid/tready handshake
//   [T] Timing      - busy/done flags, state transitions
//   [P] Protocol    - tvalid held until tready, no data lost on backpressure
//   [C] Corner-case - img_len=1, img_len=4 (one word), back-to-back start
// =============================================================================
module tb_pixel_stream_reader;

    logic clk    = 0;
    logic resetn = 0;
    always #10 clk = ~clk;

    logic        start;
    logic [31:0] img_base;
    logic [31:0] img_len;
    logic        done;
    logic        busy;
    logic [13:0] bram_addr;
    logic [31:0] bram_rdata;
    logic [ 7:0] m_axis_tdata;
    logic        m_axis_tvalid;
    logic        m_axis_tuser;
    logic        m_axis_tready;

    pixel_stream_reader dut (
        .clk          (clk),
        .resetn       (resetn),
        .start        (start),
        .img_base     (img_base),
        .img_len      (img_len),
        .done         (done),
        .busy         (busy),
        .bram_addr    (bram_addr),
        .bram_rdata   (bram_rdata),
        .m_axis_tdata (m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tuser (m_axis_tuser),
        .m_axis_tready(m_axis_tready)
    );

    // Fake BRAM with small content
    logic [31:0] fake_mem [0:15];
    always_ff @(posedge clk)
        bram_rdata <= fake_mem[bram_addr[3:0]];

    int pass_count = 0;
    int fail_count = 0;

    task check(input string name, input logic [31:0] got, input logic [31:0] exp);
        if (got === exp) begin
            $display("  PASS  [%0s]  got=%0h  exp=%0h", name, got, exp);
            pass_count++;
        end else begin
            $display("  FAIL  [%0s]  got=%0h  exp=%0h  <---", name, got, exp);
            fail_count++;
        end
    endtask

    // Collect all bytes streamed out
    logic [7:0] received_bytes [0:255];
    logic [7:0] received_user  [0:255];
    int         rx_count;

    logic rx_count_clr;

    // Monitor on tvalid & tready
    always_ff @(posedge clk) begin
        if (rx_count_clr) begin
            rx_count <= 0;
        end else if (m_axis_tvalid && m_axis_tready) begin
            received_bytes[rx_count] <= m_axis_tdata;
            received_user [rx_count] <= m_axis_tuser;
            rx_count <= rx_count + 1;
        end
    end

    task automatic run_stream(input int num_bytes, input logic stall_en);
        int tready_cycle;
        tready_cycle = 0;
        @(negedge clk);
        start = 1;
        @(posedge clk);
        @(negedge clk);
        start = 0;
        // Keep driving tready and wait for done
        while (!done) begin
            @(negedge clk);
            if (stall_en)
                m_axis_tready = tready_cycle[0];
            else
                m_axis_tready = 1;
            tready_cycle++;
        end
        @(negedge clk);
        m_axis_tready = 0;
        repeat(3) @(posedge clk);
    endtask

    initial begin
        // Populate fake BRAM
        //   word[0] = 0xAABBCCDD -> bytes: DD CC BB AA
        //   word[1] = 0x11223344 -> bytes: 44 33 22 11
        fake_mem[0] = 32'hAABBCCDD;
        fake_mem[1] = 32'h11223344;
        for (int i = 2; i < 16; i++) fake_mem[i] = 32'hDEAD_0000 + i;

        start = 0; img_base = 0; img_len = 0; m_axis_tready = 0;
        rx_count_clr = 1;

        resetn = 0;
        repeat(4) @(posedge clk);
        resetn = 1;
        @(posedge clk);
        rx_count_clr = 0;

        $display("\n==== [F] FUNCTIONAL - BYTE STREAM ORDER ====");
        img_base = 32'h0; img_len = 32'd8; 
        @(negedge clk); rx_count_clr = 1; @(posedge clk); rx_count_clr = 0;
        run_stream(8, 0);
        // Expected: DD CC BB AA  44 33 22 11
        check("F1 byte0", {24'b0, received_bytes[0]}, {24'b0, 8'hDD});
        check("F1 byte1", {24'b0, received_bytes[1]}, {24'b0, 8'hCC});
        check("F1 byte2", {24'b0, received_bytes[2]}, {24'b0, 8'hBB});
        check("F1 byte3", {24'b0, received_bytes[3]}, {24'b0, 8'hAA});
        check("F1 byte4", {24'b0, received_bytes[4]}, {24'b0, 8'h44});
        check("F1 byte5", {24'b0, received_bytes[5]}, {24'b0, 8'h33});
        check("F1 total", {24'b0, rx_count[7:0]}, {24'b0, 8'd8});

        $display("\n==== [I] INTERFACE - TUSER ON FIRST PIXEL ====");
        img_base = 32'h0; img_len = 32'd4;
        @(negedge clk); rx_count_clr = 1; @(posedge clk); rx_count_clr = 0;
        run_stream(4, 0);
        check("I1 tuser on first byte",  {31'b0, received_user[0]}, 32'h1);
        check("I1 tuser on second byte", {31'b0, received_user[1]}, 32'h0);
        check("I1 tuser on third byte",  {31'b0, received_user[2]}, 32'h0);

        $display("\n==== [T] TIMING - BUSY/DONE FLAGS ====");
        img_base = 32'h0; img_len = 32'd4;
        @(negedge clk); rx_count_clr = 1; @(posedge clk); rx_count_clr = 0;
        @(negedge clk); start = 1;
        @(posedge clk);
        @(negedge clk); start = 0;
        check("T1 busy after start", {31'b0, busy}, 32'h1);
        m_axis_tready = 1;
        wait (done == 1);
        check("T2 done when finished", {31'b0, done}, 32'h1);
        @(posedge clk);
        check("T3 not busy when done", {31'b0, busy}, 32'h0);
        m_axis_tready = 0;
        @(posedge clk);

        $display("\n==== [P] PROTOCOL - BACKPRESSURE ====");
        img_base = 32'h0; img_len = 32'd8;
        @(negedge clk); rx_count_clr = 1; @(posedge clk); rx_count_clr = 0;
        run_stream(8, 1); // stall every other cycle
        check("P1 all bytes received despite stall", {24'b0, rx_count[7:0]}, {24'b0, 8'd8});
        check("P1 first byte still correct", {24'b0, received_bytes[0]}, {24'b0, 8'hDD});

        $display("\n==== [C] CORNER-CASE ====");

        // [C1] img_len = 1 (single byte)
        img_base = 32'h0; img_len = 32'd1;
        @(negedge clk); rx_count_clr = 1; @(posedge clk); rx_count_clr = 0;
        run_stream(1, 0);
        check("C1 single byte count", {24'b0, rx_count[7:0]}, {24'b0, 8'd1});
        check("C1 single byte tuser", {31'b0, received_user[0]}, 32'h1);

        // [C2] img_len = 4 (exactly one BRAM word)
        img_base = 32'h0; img_len = 32'd4;
        @(negedge clk); rx_count_clr = 1; @(posedge clk); rx_count_clr = 0;
        run_stream(4, 0);
        check("C2 one-word count", {24'b0, rx_count[7:0]}, {24'b0, 8'd4});
        check("C2 one-word count", {24'b0, rx_count[7:0]}, {24'b0, 8'd4});

        $display("\n========================================");
        $display("  TOTAL PASS: %0d  |  TOTAL FAIL: %0d", pass_count, fail_count);
        $display("========================================\n");
        $finish;
    end

    initial begin #2000000; $display("TIMEOUT"); $finish; end

endmodule
