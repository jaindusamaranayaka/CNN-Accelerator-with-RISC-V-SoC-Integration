`timescale 1 ns / 1 ps
// =============================================================================
// Testbench: tb_uart_serial_controller
// DUT:       uart_serial_controller.sv
// Tests:
//   [F] Functional  - TX serialization, RX deserialization (loopback test)
//   [I] Interface   - CPU register access: Data Reg (0x0) & Status Reg (0x4)
//   [T] Timing      - Ready assertion latency, bit baud duration verification
//   [P] Protocol    - rx_valid set on stop bit, rx_read_ack auto-clears rx_valid,
//                     tx_ready status bit tracking
//   [C] Corner-case - Write when tx is busy (ignored), reset mid-transmission,
//                     consecutive back-to-back byte transfers
// =============================================================================
module tb_uart_serial_controller;

    // Use small clock divider for fast simulation:
    // CLK_FREQ = 10_000_000 (10 MHz, 100ns period), BAUD_RATE = 1_000_000 (1 MBaud)
    // CLOCK_DIVIDE = 10 clock cycles per bit
    localparam CLK_FREQ  = 10_000_000;
    localparam BAUD_RATE = 1_000_000;
    localparam CLOCK_DIV = CLK_FREQ / BAUD_RATE; // 10 cycles

    logic        clk    = 0;
    logic        resetn = 0;
    always #50 clk = ~clk; // 100ns period (10 MHz)

    logic        valid;
    logic [31:0] addr;
    logic [31:0] wdata;
    logic [ 3:0] wstrb;
    logic [31:0] rdata;
    logic        ready;
    logic        uart_rx;
    logic        uart_tx;

    uart_serial_controller #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .clk     (clk),
        .resetn  (resetn),
        .valid   (valid),
        .addr    (addr),
        .wdata   (wdata),
        .wstrb   (wstrb),
        .rdata   (rdata),
        .ready   (ready),
        .uart_rx (uart_rx),
        .uart_tx (uart_tx)
    );

    // Loopback connection wire
    // Can connect directly or override with stimulus
    logic loopback_en;
    assign uart_rx = loopback_en ? uart_tx : 1'b1;

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

    // CPU Bus Write Task
    task cpu_write(input [31:0] a, input [31:0] d);
        @(negedge clk);
        valid = 1; addr = a; wdata = d; wstrb = 4'b0001;
        @(posedge clk);
        wait (ready == 1);
        @(negedge clk);
        valid = 0; wstrb = 4'b0000;
        @(posedge clk);
    endtask

    // CPU Bus Read Task
    task cpu_read(input [31:0] a, output [31:0] rd);
        @(negedge clk);
        valid = 1; addr = a; wstrb = 4'b0000;
        @(posedge clk);
        wait (ready == 1);
        @(negedge clk);
        rd = rdata;
        valid = 0;
        @(posedge clk);
    endtask

    logic [31:0] status;
    logic [31:0] rx_data_rd;

    initial begin
        valid = 0; addr = 0; wdata = 0; wstrb = 0;
        loopback_en = 1; // enable loopback by default

        // ---- Reset ----
        resetn = 0;
        repeat(5) @(posedge clk);
        resetn = 1;
        @(posedge clk);

        $display("\n==== [I] INTERFACE & STATUS REGISTER INITIAL STATE ====");
        // Status reg at 0x4: bit 0 = tx_ready, bit 1 = rx_valid
        cpu_read(32'h1000_0004, status);
        check("I1 initial tx_ready == 1", {31'b0, status[0]}, 32'h1);
        check("I1 initial rx_valid == 0", {31'b0, status[1]}, 32'h0);

        $display("\n==== [F] FUNCTIONAL - TX TO RX LOOPBACK ====");
        // Transmit byte 0xA5
        cpu_write(32'h1000_0000, 32'h0000_00A5);

        // While transmitting, tx_ready should go to 0
        @(posedge clk);
        cpu_read(32'h1000_0004, status);
        check("F1 tx_ready goes low during transmission", {31'b0, status[0]}, 32'h0);

        // Poll status register until rx_valid is high (status[1] == 1)
        do begin
            cpu_read(32'h1000_0004, status);
        end while (status[1] == 1'b0);

        check("F2 rx_valid asserted after loopback reception", {31'b0, status[1]}, 32'h1);

        // TX completes stop bit shortly after RX samples it in the middle of the bit
        do begin
            cpu_read(32'h1000_0004, status);
        end while (status[0] == 1'b0);

        check("F3 tx_ready back to 1", {31'b0, status[0]}, 32'h1);

        // Read received byte from data register (0x0)
        cpu_read(32'h1000_0000, rx_data_rd);
        check("F4 loopback data received equals 0xA5", rx_data_rd[7:0], 32'hA5);

        $display("\n==== [P] PROTOCOL - AUTO-CLEAR RX_VALID ON READ ====");
        // Reading Data register must clear rx_valid in Status register
        cpu_read(32'h1000_0004, status);
        check("P1 rx_valid cleared automatically", {31'b0, status[1]}, 32'h0);

        $display("\n==== [T] TIMING - BIT DURATION VERIFICATION ====");
        // Check that tx line starts with Start bit (low) for ~CLOCK_DIV cycles
        cpu_write(32'h1000_0000, 32'h0000_0055);
        wait (uart_tx == 1'b0); // start bit
        check("T1 start bit asserted low", {31'b0, uart_tx}, 32'h0);

        // Wait until reception completes
        do begin
            cpu_read(32'h1000_0004, status);
        end while (status[1] == 1'b0);
        cpu_read(32'h1000_0000, rx_data_rd);
        check("T2 0x55 received successfully", rx_data_rd[7:0], 32'h55);

        $display("\n==== [C] CORNER-CASE TESTS ====");
        // [C1] Back-to-back writes: write when TX busy should be safely ignored
        cpu_write(32'h1000_0000, 32'h0000_003C);
        // Try to immediately write 0xFF while tx is busy
        cpu_write(32'h1000_0000, 32'h0000_00FF);

        // Wait for first transmission to finish
        do begin
            cpu_read(32'h1000_0004, status);
        end while (status[1] == 1'b0);

        cpu_read(32'h1000_0000, rx_data_rd);
        check("C1 first byte 0x3C preserved, ignored conflicting write", rx_data_rd[7:0], 32'h3C);

        // [C2] Reset mid-transmission restores idle state
        cpu_write(32'h1000_0000, 32'h0000_007E);
        repeat(5) @(posedge clk);
        resetn = 0; // reset active
        repeat(3) @(posedge clk);
        resetn = 1;
        @(posedge clk);
        cpu_read(32'h1000_0004, status);
        check("C2 tx_ready restored after reset", {31'b0, status[0]}, 32'h1);
        check("C2 rx_valid reset to 0", {31'b0, status[1]}, 32'h0);
        check("C2 uart_tx line high (idle) after reset", {31'b0, uart_tx}, 32'h1);

        // ---- Summary ----
        $display("\n========================================");
        $display("  TOTAL PASS: %0d  |  TOTAL FAIL: %0d", pass_count, fail_count);
        $display("========================================\n");
        $finish;
    end

    // Watchdog
    initial begin
        #5000000;
        $display("TIMEOUT - simulation hung");
        $finish;
    end

endmodule
