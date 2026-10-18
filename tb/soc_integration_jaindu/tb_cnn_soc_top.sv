`timescale 1 ns / 1 ps

module tb_cnn_soc_top;
    localparam CLK_PERIOD = 20; // 50 MHz clock (20 ns period)
    localparam BAUD_RATE  = 2500000; // 2.5 MBaud for fast, accurate simulation
    localparam BIT_PERIOD = 400; // 400 ns per bit (20 clock cycles @ 50 MHz)

    logic        clk;
    logic [3:0]  key;
    logic        uart_rxd;
    logic        uart_txd;
    logic [6:0]  hex0, hex1, hex2, hex3, hex4, hex5, hex6, hex7;

    // Clock generator
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // Instantiate Top-Level SoC
    cnn_soc_top #(
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .CLOCK_50 (clk),
        .KEY      (key),
        .UART_RXD (uart_rxd),
        .UART_TXD (uart_txd),
        .HEX0     (hex0),
        .HEX1     (hex1),
        .HEX2     (hex2),
        .HEX3     (hex3),
        .HEX4     (hex4),
        .HEX5     (hex5),
        .HEX6     (hex6),
        .HEX7     (hex7)
    );

    // Task to send a byte via UART RX
    task automatic send_uart_byte(input [7:0] data, input int post_delay_clocks);
        integer b;
        begin
            // Start bit (0)
            uart_rxd = 1'b0;
            #(BIT_PERIOD);
            // 8 data bits (LSB first)
            for (b = 0; b < 8; b = b + 1) begin
                uart_rxd = data[b];
                #(BIT_PERIOD);
            end
            // Stop bit (1)
            uart_rxd = 1'b1;
            #(BIT_PERIOD);
            // Inter-byte pause
            if (post_delay_clocks > 0)
                repeat (post_delay_clocks) @(posedge clk);
        end
    endtask

    // Task to receive a byte from UART TX
    task automatic recv_uart_byte(output [7:0] data);
        integer b;
        begin
            // Wait for start bit falling edge
            @(negedge uart_txd);
            // Wait 1.5 bit periods to sample at center of bit 0
            #(BIT_PERIOD * 3 / 2);
            for (b = 0; b < 8; b = b + 1) begin
                data[b] = uart_txd;
                #(BIT_PERIOD);
            end
        end
    endtask

    // Expected 7-segment hex decoding
    function logic [6:0] exp_hex(input [3:0] val);
        case (val)
            4'h0: exp_hex = 7'b1000000;
            4'h1: exp_hex = 7'b1111001;
            4'h2: exp_hex = 7'b0100100;
            4'h3: exp_hex = 7'b0110000;
            4'h4: exp_hex = 7'b0011001;
            4'h5: exp_hex = 7'b0010010;
            4'h6: exp_hex = 7'b0000010;
            4'h7: exp_hex = 7'b1111000;
            4'h8: exp_hex = 7'b0000000;
            4'h9: exp_hex = 7'b0010000;
            4'ha: exp_hex = 7'b0001000;
            4'hb: exp_hex = 7'b0000011;
            4'hc: exp_hex = 7'b1000110;
            4'hd: exp_hex = 7'b0100010;
            4'he: exp_hex = 7'b0000110;
            4'hf: exp_hex = 7'b0001110;
            default: exp_hex = 7'b1111111;
        endcase
    endfunction

    // Test variables
    int i;
    logic [7:0] resp_token;
    logic [7:0] resp_class;
    int pass_count = 0;
    int fail_count = 0;

    always @(dut.gpio_out) begin
        $display("[%0t ns] [MON-GPIO] gpio_out changed to 0x%08x", $time, dut.gpio_out);
    end

    initial begin
        $display("\n========================================================");
        $display("  STARTING TOP-LEVEL CNN SOC FIRMWARE SIMULATION");
        $display("  Target: cnn_soc_top + PicoRV32 + Real firmware.hex");
        $display("========================================================\n");

        // Initial pin states
        uart_rxd = 1'b1; // UART idle line high
        key      = 4'b1110; // Assert resetn (KEY[0] active low)

        // Reset sequence
        repeat (20) @(posedge clk);
        key[0] = 1'b1; // Deassert reset
        $display("[%0t ns] Reset deasserted, PicoRV32 executing firmware.hex...", $time);

        // Wait for CPU to boot and initialize GPIO
        repeat (100) @(posedge clk);

        // Step 1: Send 'S' Start Token
        $display("[%0t ns] [Step 1] Sending Start Token 'S' (0x53)...", $time);
        send_uart_byte(8'h53, 200);

        // Step 2: Send 9 Conv Kernel Weights (signed 8-bit)
        $display("[%0t ns] [Step 2] Sending 9 Conv weights...", $time);
        send_uart_byte(8'sd1,  100);
        send_uart_byte(8'sd2,  100);
        send_uart_byte(8'sd1,  100);
        send_uart_byte(8'sd0,  100);
        send_uart_byte(8'sd0,  100);
        send_uart_byte(8'sd0,  100);
        send_uart_byte(-8'sd1, 100);
        send_uart_byte(-8'sd2, 100);
        send_uart_byte(-8'sd1, 100);

        // Step 3: Send Conv Bias (16-bit signed, little-endian)
        $display("[%0t ns] [Step 3] Sending Conv bias (0x0000)...", $time);
        send_uart_byte(8'h00, 100); // bias_lo
        send_uart_byte(8'h00, 100); // bias_hi

        // Step 4: Send Quantization Shift (shift_s = 2)
        $display("[%0t ns] [Step 4] Sending Quantization shift (2)...", $time);
        send_uart_byte(8'd2, 100);

        // Step 5: Send 1690 Dense Layer Weights
        // Software executes division: int n = i / 169, int p = i % 169
        // Allow 750 clock cycles (~15 us) per byte for software RV32I division
        $display("[%0t ns] [Step 5] Sending 1690 Dense weights (inter-byte delay for RV32I division)...", $time);
        for (i = 0; i < 1690; i = i + 1) begin
            send_uart_byte(8'sd1, 750);
            if ((i + 1) % 400 == 0)
                $display("   ... sent %0d / 1690 dense weights", i + 1);
        end
        $display("[%0t ns] Dense weights successfully streamed.", $time);

        // Step 6: Send 10 Dense Biases (20 bytes total, 16-bit each)
        $display("[%0t ns] [Step 6] Sending 10 Dense biases (20 bytes)...", $time);
        for (i = 0; i < 10; i = i + 1) begin
            send_uart_byte(8'h00, 150); // bias_lo
            send_uart_byte(8'h00, 150); // bias_hi
        end

        // Step 7: Send 784 Image Pixels (28x28 MNIST image)
        $display("[%0t ns] [Step 7] Streaming 784 image pixels into Image BRAM...", $time);
        for (i = 0; i < 784; i = i + 1) begin
            // Non-zero test pattern in the center, zeros on border
            int row, col;
            row = i / 28;
            col = i % 28;
            if (row >= 6 && row <= 21 && col >= 6 && col <= 21)
                send_uart_byte(8'd128, 80);
            else
                send_uart_byte(8'd0, 80);

            if ((i + 1) % 200 == 0)
                $display("   ... sent %0d / 784 image pixels", i + 1);
        end
        $display("[%0t ns] Image stream complete. Hardware Accelerator triggered!", $time);

        // Step 8: Receive Classifier Result from UART TX
        $display("[%0t ns] [Step 8] Waiting for UART response from SoC...", $time);

        fork
            begin
                recv_uart_byte(resp_token);
                recv_uart_byte(resp_class);
            end
            begin
                // Watchdog timer: 10 ms after accelerator start
                #10_000_000;
                $display("\n[ERROR] Simulation Watchdog Timeout! SoC did not respond within 10 ms.");
                $display("  dut.gpio_out        = 0x%08x", dut.gpio_out);
                $display("  dut.cpu.reg_pc      = 0x%08x", dut.cpu.reg_pc);
                $display("  dut.cpu.mem_addr    = 0x%08x", dut.cpu.mem_addr);
                $display("  dut.cpu.mem_valid   = %0b", dut.cpu.mem_valid);
                $display("  dut.cpu.mem_ready   = %0b", dut.cpu.mem_ready);
                $display("  dut.uart.rx_valid   = %0b", dut.uart.rx_valid);
                $display("  dut.re_start        = %0b", dut.re_start);
                $display("  dut.re_busy         = %0b", dut.re_busy);
                $display("  dut.result_ready    = %0b", dut.result_ready);
                $display("  dut.final_class_reg = 0x%08x", dut.final_class_reg);
                $finish;
            end
        join_any
        disable fork;

        // Step 9: Verify Response and Display Outputs
        $display("\n========================================================");
        $display("  SOC INFERENCE EXECUTION COMPLETED");
        $display("========================================================");
        $display("  Received Token: '%s' (0x%02x) [Expected: 'R']", resp_token, resp_token);
        $display("  Classified Digit: %0d (0x%02x)", resp_class, resp_class);
        $display("  HEX0 7-Segment Value: 7'b%07b", hex0);
        $display("  Expected HEX0:        7'b%07b", exp_hex(resp_class[3:0]));

        if (resp_token == "R") begin
            $display("  [PASS] UART Return Token 'R' verified.");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] Incorrect UART Return Token! Expected 'R', got '%s'", resp_token);
            fail_count = fail_count + 1;
        end

        if (resp_class <= 9) begin
            $display("  [PASS] Classified digit %0d is within valid range [0..9].", resp_class);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] Classified digit %0d out of range [0..9]!", resp_class);
            fail_count = fail_count + 1;
        end

        if (hex0 == exp_hex(resp_class[3:0])) begin
            $display("  [PASS] HEX0 7-segment display matches classified digit %0d.", resp_class);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] HEX0 mismatch! Expected 7'b%07b, got 7'b%07b", exp_hex(resp_class[3:0]), hex0);
            fail_count = fail_count + 1;
        end

        $display("\n========================================================");
        if (fail_count == 0) begin
            $display("  *** TOP-LEVEL SOC FIRMWARE SIMULATION: PASSED (ALL %0d CHECKS) ***", pass_count);
        end else begin
            $display("  *** TOP-LEVEL SOC FIRMWARE SIMULATION: FAILED (%0d FAILS) ***", fail_count);
        end
        $display("  Simulation Finished at Time: %0t ns", $time);
        $display("========================================================\n");

        $finish;
    end

endmodule
