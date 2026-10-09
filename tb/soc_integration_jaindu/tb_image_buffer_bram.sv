`timescale 1 ns / 1 ps
// =============================================================================
// Testbench: tb_image_buffer_bram
// DUT:       image_buffer_bram.sv
// Tests:
//   [F] Functional  - write via port A, read via both ports
//   [I] Interface   - a_en gating, byte-write strobes
//   [T] Timing      - 1-cycle read latency on both ports
//   [P] Protocol    - port B always reads (no write enable)
//   [C] Corner-case - write with a_en=0 does not change memory
// =============================================================================
module tb_image_buffer_bram;

    logic        clk = 0;
    always #10 clk = ~clk;

    logic [31:0] a_addr;
    logic [31:0] a_wdata;
    logic [ 3:0] a_wstrb;
    logic        a_en;
    logic [31:0] a_rdata;
    logic [13:0] b_addr;
    logic [31:0] b_rdata;

    image_buffer_bram #(.DEPTH(64)) dut (
        .clk     (clk),
        .a_addr  (a_addr),
        .a_wdata (a_wdata),
        .a_wstrb (a_wstrb),
        .a_en    (a_en),
        .a_rdata (a_rdata),
        .b_addr  (b_addr),
        .b_rdata (b_rdata)
    );

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

    // Write a full word via port A
    task bram_write(input [31:0] a, input [31:0] d, input [3:0] s);
        @(negedge clk);
        a_addr = a; a_wdata = d; a_wstrb = s; a_en = 1;
        @(posedge clk);
        @(negedge clk);
        a_en = 0;
    endtask

    // Read via port B (1 cycle latency)
    task bram_read_b(input [13:0] a, output [31:0] rd);
        @(negedge clk);
        b_addr = a;
        @(posedge clk);
        @(posedge clk);  // 1-cycle latency
        rd = b_rdata;
    endtask

    logic [31:0] rd;

    initial begin
        a_addr = 0; a_wdata = 0; a_wstrb = 0; a_en = 0; b_addr = 0;
        repeat(2) @(posedge clk);

        $display("\n==== [F] FUNCTIONAL ====");

        // [F1] Write full word, read back via port B
        bram_write(32'h0, 32'hDEAD_BEEF, 4'b1111);
        bram_read_b(14'h0, rd);
        check("F1 write/read port B", rd, 32'hDEAD_BEEF);

        // [F2] Write to different address
        bram_write(32'h8, 32'h1234_5678, 4'b1111);   // addr[13:2] = 2
        bram_read_b(14'h2, rd);
        check("F2 second address", rd, 32'h1234_5678);
        // Previous address must still hold its value
        bram_read_b(14'h0, rd);
        check("F2 addr0 unchanged", rd, 32'hDEAD_BEEF);

        $display("\n==== [I] INTERFACE - BYTE STROBES ====");

        // [I1] Write only byte 0
        bram_write(32'h0, 32'h0, 4'b1111);             // clear
        bram_write(32'h0, 32'hABCD_EF12, 4'b0001);
        bram_read_b(14'h0, rd);
        check("I1 byte0 written", {24'b0, rd[7:0]}, {24'b0, 8'h12});
        check("I1 bytes1-3 = 0",  rd[31:8], 24'h0);

        // [I2] Write only byte 3
        bram_write(32'h0, 32'h0, 4'b1111);
        bram_write(32'h0, 32'hBB00_0000, 4'b1000);
        bram_read_b(14'h0, rd);
        check("I2 byte3 written", {24'b0, rd[31:24]}, {24'b0, 8'hBB});
        check("I2 bytes0-2 = 0",  {8'b0, rd[23:0]}, 32'h0);

        $display("\n==== [T] TIMING - 1-CYCLE READ LATENCY ====");

        bram_write(32'h4, 32'hCAFE_BABE, 4'b1111);  // word addr 1

        // Port B: present address, check NEXT posedge
        @(negedge clk); b_addr = 14'h1;
        @(posedge clk);
        // rdata not yet valid this cycle
        @(posedge clk);
        rd = b_rdata;
        check("T1 port B 1-cycle latency", rd, 32'hCAFE_BABE);

        $display("\n==== [P] PROTOCOL - a_en GATING ====");

        // Port A write does NOT happen when a_en = 0
        bram_write(32'h0, 32'hFFFF_FFFF, 4'b1111);   // set known value
        // attempt write with a_en=0
        @(negedge clk);
        a_addr = 32'h0; a_wdata = 32'h0; a_wstrb = 4'b1111; a_en = 0;
        @(posedge clk); @(negedge clk); a_en = 0;
        bram_read_b(14'h0, rd);
        check("P1 a_en=0 no write", rd, 32'hFFFF_FFFF);

        $display("\n==== [C] CORNER-CASE ====");

        // [C1] Write to address 0 and address max (63)
        bram_write(32'hFC, 32'hA5A5_A5A5, 4'b1111);  // word addr 63
        bram_read_b(14'd63, rd);
        check("C1 max address write/read", rd, 32'hA5A5_A5A5);

        // [C2] Write zeros over existing data
        bram_write(32'h0, 32'hFFFF_FFFF, 4'b1111);
        bram_write(32'h0, 32'h0000_0000, 4'b1111);
        bram_read_b(14'h0, rd);
        check("C2 write zeros", rd, 32'h0000_0000);

        $display("\n========================================");
        $display("  TOTAL PASS: %0d  |  TOTAL FAIL: %0d", pass_count, fail_count);
        $display("========================================\n");
        $finish;
    end

    initial begin #200000; $display("TIMEOUT"); $finish; end

endmodule
