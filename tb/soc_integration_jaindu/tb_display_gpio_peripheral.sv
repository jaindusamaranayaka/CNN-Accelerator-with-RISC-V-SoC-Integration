`timescale 1 ns / 1 ps
// =============================================================================
// Testbench: tb_display_gpio_peripheral
// DUT:       display_gpio_peripheral.sv
// Tests:
//   [F]  Functional  - write/read of all four byte lanes
//   [I]  Interface   - valid/ready handshake
//   [T]  Timing      - ready deasserts after 1 cycle, 2-cycle back-to-back
//   [P]  Protocol    - write-only (no read-back), read-only (no write)
//   [C]  Corner-case - reset mid-transaction, invalid address read, partial strobe
// =============================================================================
module tb_display_gpio_peripheral;

    // -------------------------------------------------------------------------
    // Clock / reset
    // -------------------------------------------------------------------------
    logic        clk    = 0;
    logic        resetn = 0;
    always #10 clk = ~clk;          // 50 MHz

    // -------------------------------------------------------------------------
    // DUT ports
    // -------------------------------------------------------------------------
    logic        valid;
    logic [31:0] addr;
    logic [31:0] wdata;
    logic [ 3:0] wstrb;
    logic [31:0] rdata;
    logic        ready;
    logic [31:0] gpio_out;

    display_gpio_peripheral dut (
        .clk     (clk),
        .resetn  (resetn),
        .valid   (valid),
        .addr    (addr),
        .wdata   (wdata),
        .wstrb   (wstrb),
        .rdata   (rdata),
        .ready   (ready),
        .gpio_out(gpio_out)
    );

    // -------------------------------------------------------------------------
    // Helper tasks
    // -------------------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    task do_write(input [31:0] a, input [31:0] d, input [3:0] s);
        @(negedge clk);
        valid = 1; addr = a; wdata = d; wstrb = s;
        @(posedge clk);
        wait (ready == 1);
        @(negedge clk);
        valid = 0; wstrb = 4'b0;
        @(posedge clk);
    endtask

    task do_read(input [31:0] a, output [31:0] rd);
        @(negedge clk);
        valid = 1; addr = a; wstrb = 4'b0000;
        @(posedge clk);
        wait (ready == 1);
        @(negedge clk);
        rd = rdata;
        valid = 0;
        @(posedge clk);
    endtask

    task check(input string name, input logic [31:0] got, input logic [31:0] exp);
        if (got === exp) begin
            $display("  PASS  [%0s]  got=%0h  exp=%0h", name, got, exp);
            pass_count++;
        end else begin
            $display("  FAIL  [%0s]  got=%0h  exp=%0h  <---", name, got, exp);
            fail_count++;
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    logic [31:0] rd;

    initial begin
        valid = 0; addr = 0; wdata = 0; wstrb = 0;

        // ---- Reset ----
        resetn = 0;
        repeat(4) @(posedge clk);
        resetn = 1;
        @(posedge clk);

        $display("\n==== [F] FUNCTIONAL TESTS ====");

        // [F1] Full 32-bit write then read-back
        do_write(32'h5000_0000, 32'hDEAD_BEEF, 4'b1111);
        do_read (32'h5000_0000, rd);
        check("F1 full write/read", rd, 32'hDEAD_BEEF);

        // [F2] Only write byte 0 (strobe = 0001)
        do_write(32'h5000_0000, 32'h0, 4'b1111);       // clear first
        do_write(32'h5000_0000, 32'hABCD_EF12, 4'b0001);
        do_read (32'h5000_0000, rd);
        check("F2 byte0 only", {24'b0, rd[7:0]}, {24'b0, 8'h12});
        check("F2 upper bytes unchanged", rd[31:8], 24'h0);

        // [F3] Write upper byte only (strobe = 1000)
        do_write(32'h5000_0000, 32'h0, 4'b1111);
        do_write(32'h5000_0000, 32'hAA00_0000, 4'b1000);
        do_read (32'h5000_0000, rd);
        check("F3 byte3 only", {24'b0, rd[31:24]}, {24'b0, 8'hAA});
        check("F3 lower bytes unchanged", {8'b0, rd[23:0]}, 32'h0);

        $display("\n==== [I] INTERFACE TESTS ====");

        // [I1] ready must be 0 when valid is deasserted
        @(negedge clk); valid = 0;
        @(posedge clk);
        check("I1 ready low when idle", {31'b0,ready}, 32'h0);

        // [I2] ready goes high exactly 1 cycle after valid assertion
        @(negedge clk); valid = 1; addr = 32'h5000_0000; wstrb = 4'b0;
        @(posedge clk);
        check("I2a ready not yet", {31'b0,ready}, 32'h0);
        @(posedge clk);
        check("I2b ready asserted", {31'b0,ready}, 32'h1);
        @(negedge clk); valid = 0;
        @(posedge clk);

        $display("\n==== [T] TIMING TESTS ====");

        // [T1] ready deasserts 1 cycle after being high
        @(negedge clk); valid = 1; addr = 32'h5000_0000; wstrb = 4'b1111; wdata = 32'h1234;
        wait (ready == 1);
        @(posedge clk); // one cycle with ready high
        @(negedge clk); valid = 0;
        @(posedge clk);
        check("T1 ready deasserts", {31'b0,ready}, 32'h0);

        // [T2] Two consecutive writes with 1-cycle bus turnaround
        do_write(32'h5000_0000, 32'hAAAA_AAAA, 4'b1111);
        do_write(32'h5000_0000, 32'hBBBB_BBBB, 4'b1111);
        do_read(32'h5000_0000, rd);
        check("T2 consecutive writes last wins", rd, 32'hBBBB_BBBB);

        $display("\n==== [P] PROTOCOL TESTS ====");

        // [P1] Read from offset 0 returns gpio_out
        do_write(32'h5000_0000, 32'hCAFE_BABE, 4'b1111);
        do_read (32'h5000_0000, rd);
        check("P1 read returns gpio_out", rd, 32'hCAFE_BABE);

        // [P2] Read from non-zero offset returns 0
        do_read(32'h5000_0004, rd);
        check("P2 invalid-offset read=0", rd, 32'h0);

        $display("\n==== [C] CORNER-CASE TESTS ====");

        // [C1] Reset clears gpio_out
        do_write(32'h5000_0000, 32'hFFFF_FFFF, 4'b1111);
        resetn = 0;
        repeat(2) @(posedge clk);
        resetn = 1;
        @(posedge clk);
        check("C1 reset clears gpio_out", gpio_out, 32'h0);

        // [C2] Reset during active transaction - no lock-up
        @(negedge clk); valid = 1; addr = 32'h5000_0000; wdata = 32'hDEAD; wstrb = 4'b1111;
        @(posedge clk);
        resetn = 0;
        @(posedge clk);
        resetn = 1;
        @(negedge clk); valid = 0;
        @(posedge clk);
        check("C2 reset mid-txn gpio_out=0", gpio_out, 32'h0);
        check("C2 reset mid-txn ready=0",   {31'b0,ready}, 32'h0);

        // [C3] Zero strobe write treated as read - must not change gpio_out
        do_write(32'h5000_0000, 32'h1234_5678, 4'b1111);
        do_write(32'h5000_0000, 32'hDEAD_DEAD, 4'b0000);
        do_read (32'h5000_0000, rd);
        check("C3 zero-strobe no write", rd, 32'h1234_5678);

        // ---- Summary ----
        $display("\n========================================");
        $display("  TOTAL PASS: %0d  |  TOTAL FAIL: %0d", pass_count, fail_count);
        $display("========================================\n");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #500000;
        $display("TIMEOUT - simulation hung");
        $finish;
    end

endmodule
