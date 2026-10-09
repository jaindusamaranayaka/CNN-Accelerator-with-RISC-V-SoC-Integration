`timescale 1 ns / 1 ps
// =============================================================================
// Testbench: tb_soc_bus_interconnect
// DUT:       soc_bus_interconnect.sv
// Memory map being tested:
//   0x0xxx_xxxx -> RAM
//   0x1xxx_xxxx -> UART
//   0x2xxx_xxxx -> IMG_BRAM
//   0x3xxx_xxxx -> OUT_BRAM
//   0x4xxx_xxxx -> MAC_CTRL
//   0x5xxx_xxxx -> GPIO
//   0x6xxx_xxxx -> CLASS_WEIGHT (always ready)
// Tests:
//   [F] Functional   - each address range selects correct peripheral valid
//   [I] Interface    - mem_rdata mux, mem_ready mux
//   [T] Timing       - valid/ready propagated same cycle (combinatorial)
//   [P] Protocol     - only one peripheral valid at a time
//   [C] Corner-case  - unmapped address (top nibble = 7), simultaneous
// =============================================================================
module tb_soc_bus_interconnect;

    logic        clk    = 0;
    logic        resetn = 1;
    always #10 clk = ~clk;

    // CPU-side
    logic        mem_valid;
    logic        mem_instr;
    logic        mem_ready;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [ 3:0] mem_wstrb;
    logic [31:0] mem_rdata;

    // Peripheral-side (all mocked)
    logic        ram_valid,  ram_ready  = 0;  logic [31:0] ram_rdata  = 0;
    logic        uart_valid, uart_ready = 0;  logic [31:0] uart_rdata = 0;
    logic        img_bram_valid, img_bram_ready = 0; logic [31:0] img_bram_rdata = 0;
    logic        out_bram_valid, out_bram_ready = 0; logic [31:0] out_bram_rdata = 0;
    logic        mac_ctrl_valid, mac_ctrl_ready = 0; logic [31:0] mac_ctrl_rdata = 0;
    logic        gpio_valid, gpio_ready = 0;  logic [31:0] gpio_rdata = 0;
    logic        class_weight_valid;

    soc_bus_interconnect dut (
        .clk              (clk),
        .resetn           (resetn),
        .mem_valid        (mem_valid),
        .mem_instr        (mem_instr),
        .mem_ready        (mem_ready),
        .mem_addr         (mem_addr),
        .mem_wdata        (mem_wdata),
        .mem_wstrb        (mem_wstrb),
        .mem_rdata        (mem_rdata),
        .ram_valid        (ram_valid),
        .ram_ready        (ram_ready),
        .ram_rdata        (ram_rdata),
        .uart_valid       (uart_valid),
        .uart_ready       (uart_ready),
        .uart_rdata       (uart_rdata),
        .img_bram_valid   (img_bram_valid),
        .img_bram_ready   (img_bram_ready),
        .img_bram_rdata   (img_bram_rdata),
        .out_bram_valid   (out_bram_valid),
        .out_bram_ready   (out_bram_ready),
        .out_bram_rdata   (out_bram_rdata),
        .mac_ctrl_valid   (mac_ctrl_valid),
        .mac_ctrl_ready   (mac_ctrl_ready),
        .mac_ctrl_rdata   (mac_ctrl_rdata),
        .gpio_valid       (gpio_valid),
        .gpio_ready       (gpio_ready),
        .gpio_rdata       (gpio_rdata),
        .class_weight_valid(class_weight_valid)
    );

    int pass_count = 0;
    int fail_count = 0;

    task check(input string name, input logic got, input logic exp);
        if (got === exp) begin
            $display("  PASS  [%0s]  got=%0b  exp=%0b", name, got, exp);
            pass_count++;
        end else begin
            $display("  FAIL  [%0s]  got=%0b  exp=%0b  <---", name, got, exp);
            fail_count++;
        end
    endtask

    task check32(input string name, input logic [31:0] got, input logic [31:0] exp);
        if (got === exp) begin
            $display("  PASS  [%0s]  got=%0h  exp=%0h", name, got, exp);
            pass_count++;
        end else begin
            $display("  FAIL  [%0s]  got=%0h  exp=%0h  <---", name, got, exp);
            fail_count++;
        end
    endtask

    // Helper: drive a bus request and check which valid fired
    task drive_addr(input [31:0] a);
        mem_valid = 1; mem_addr = a; mem_wstrb = 4'b0; mem_wdata = 0; mem_instr = 0;
        #1; // let combinatorial settle
    endtask

    initial begin
        mem_valid = 0; mem_addr = 0; mem_wstrb = 0; mem_wdata = 0; mem_instr = 0;

        $display("\n==== [F] FUNCTIONAL - ADDRESS DECODE ====");

        // [F1] RAM  0x0000_0000
        drive_addr(32'h0000_0000);
        check("F1 ram_valid",          ram_valid,          1'b1);
        check("F1 uart_valid=0",       uart_valid,         1'b0);
        check("F1 gpio_valid=0",       gpio_valid,         1'b0);

        // [F2] UART 0x1000_0000
        drive_addr(32'h1000_0000);
        check("F2 uart_valid",         uart_valid,         1'b1);
        check("F2 ram_valid=0",        ram_valid,          1'b0);

        // [F3] IMG_BRAM 0x2000_0000
        drive_addr(32'h2000_0000);
        check("F3 img_bram_valid",     img_bram_valid,     1'b1);
        check("F3 others=0",           (ram_valid | uart_valid | gpio_valid), 1'b0);

        // [F4] OUT_BRAM 0x3000_0000
        drive_addr(32'h3000_0000);
        check("F4 out_bram_valid",     out_bram_valid,     1'b1);

        // [F5] MAC_CTRL 0x4000_0000
        drive_addr(32'h4000_0000);
        check("F5 mac_ctrl_valid",     mac_ctrl_valid,     1'b1);

        // [F6] GPIO 0x5000_0000
        drive_addr(32'h5000_0000);
        check("F6 gpio_valid",         gpio_valid,         1'b1);

        // [F7] CLASS_WEIGHT 0x6000_0000
        drive_addr(32'h6000_0000);
        check("F7 class_weight_valid", class_weight_valid, 1'b1);

        $display("\n==== [I] INTERFACE - MEM_RDATA MUX ====");

        // [I1] ram_rdata forwarded
        ram_rdata = 32'hAABBCCDD; drive_addr(32'h0000_0000); ram_ready = 1;
        #1; check32("I1 rdata from RAM", mem_rdata, 32'hAABBCCDD);
        ram_ready = 0;

        // [I2] gpio_rdata forwarded
        gpio_rdata = 32'h12345678; drive_addr(32'h5000_0000); gpio_ready = 1;
        #1; check32("I2 rdata from GPIO", mem_rdata, 32'h12345678);
        gpio_ready = 0;

        // [I3] class_weight always ready
        drive_addr(32'h6000_0000);
        check("I3 class_weight mem_ready", mem_ready, 1'b1);

        $display("\n==== [T] TIMING - COMBINATORIAL ====");

        // [T1] mem_ready propagates immediately from gpio_ready
        gpio_ready = 0; drive_addr(32'h5000_0000);
        check("T1a gpio_ready=0 -> mem_ready=0", mem_ready, 1'b0);
        gpio_ready = 1; #1;
        check("T1b gpio_ready=1 -> mem_ready=1", mem_ready, 1'b1);
        gpio_ready = 0;

        $display("\n==== [P] PROTOCOL - ONE VALID AT A TIME ====");

        // [P1] Only gpio_valid should be 1 for 0x5000_0000
        drive_addr(32'h5000_0000);
        check("P1 only gpio high", (ram_valid|uart_valid|img_bram_valid|
                                    out_bram_valid|mac_ctrl_valid), 1'b0);

        // [P2] No valid when mem_valid=0
        mem_valid = 0; #1;
        check("P2 all valid=0 when mem_valid=0",
              (ram_valid|uart_valid|img_bram_valid|out_bram_valid|
               mac_ctrl_valid|gpio_valid|class_weight_valid), 1'b0);

        $display("\n==== [C] CORNER-CASE ====");

        // [C1] Unmapped address (nibble=7) - no peripheral fires
        drive_addr(32'h7000_0000);
        check("C1 unmapped: ram_valid=0",          ram_valid,          1'b0);
        check("C1 unmapped: uart_valid=0",         uart_valid,         1'b0);
        check("C1 unmapped: gpio_valid=0",         gpio_valid,         1'b0);
        check("C1 unmapped: class_weight_valid=0", class_weight_valid, 1'b0);
        // mem_ready should be 0 (no peripheral responds)
        check("C1 unmapped: mem_ready=0",          mem_ready,          1'b0);

        // [C2] High bits of address don't affect low-bit decode
        drive_addr(32'h50FF_FFFC); // still GPIO range
        check("C2 gpio selects despite low bits", gpio_valid, 1'b1);

        mem_valid = 0;

        $display("\n========================================");
        $display("  TOTAL PASS: %0d  |  TOTAL FAIL: %0d", pass_count, fail_count);
        $display("========================================\n");
        $finish;
    end

    initial begin
        #100000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
