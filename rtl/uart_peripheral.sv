`timescale 1 ns / 1 ps

module uart_peripheral #(
    parameter CLK_FREQ = 50000000,
    parameter BAUD_RATE = 115200
)(
    input  logic        clk,
    input  logic        resetn,

    // Memory-mapped interface
    input  logic        valid,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    input  logic [ 3:0] wstrb,
    output logic [31:0] rdata,
    output logic        ready,

    // Physical UART pins
    input  logic        uart_rx,
    output logic        uart_tx
);

    localparam CLOCK_DIVIDE = CLK_FREQ / BAUD_RATE;

    // Registers
    // 0x00: TX Data (Write), RX Data (Read)
    // 0x04: Status (Bit 0: TX Ready, Bit 1: RX Valid)

    logic rx_valid;
    logic [7:0] rx_data;
    logic rx_read_ack;

    logic tx_start;
    logic [7:0] tx_data;
    logic tx_ready;

    // Memory interface logic
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            ready <= 1'b0;
            rdata <= 32'h0;
            tx_start <= 1'b0;
            rx_read_ack <= 1'b0;
        end else begin
            ready <= 1'b0;
            tx_start <= 1'b0;
            rx_read_ack <= 1'b0;

            if (valid && !ready) begin
                ready <= 1'b1;
                if (wstrb != 4'b0000) begin
                    // Write
                    if (addr[3:0] == 4'h0 && tx_ready) begin
                        tx_data <= wdata[7:0];
                        tx_start <= 1'b1;
                    end
                end else begin
                    // Read
                    if (addr[3:0] == 4'h0) begin
                        rdata <= {24'h0, rx_data};
                        rx_read_ack <= 1'b1; // clear rx flag
                    end else if (addr[3:0] == 4'h4) begin
                        rdata <= {30'h0, rx_valid, tx_ready};
                    end else begin
                        rdata <= 32'h0;
                    end
                end
            end
        end
    end

    // Simple UART TX
    logic [15:0] tx_clk_cnt;
    logic [3:0] tx_bit_cnt;
    logic [9:0] tx_shift;

    assign uart_tx = tx_shift[0];
    assign tx_ready = (tx_bit_cnt == 0);

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            tx_clk_cnt <= 0;
            tx_bit_cnt <= 0;
            tx_shift <= 10'h3FF;
        end else begin
            if (tx_start && tx_ready) begin
                tx_clk_cnt <= 0;
                tx_bit_cnt <= 10; // Start(1) + Data(8) + Stop(1)
                tx_shift <= {1'b1, tx_data, 1'b0};
            end else if (tx_bit_cnt > 0) begin
                if (tx_clk_cnt == CLOCK_DIVIDE - 1) begin
                    tx_clk_cnt <= 0;
                    tx_bit_cnt <= tx_bit_cnt - 1;
                    tx_shift <= {1'b1, tx_shift[9:1]};
                end else begin
                    tx_clk_cnt <= tx_clk_cnt + 1;
                end
            end
        end
    end

    // Simple UART RX
    logic [15:0] rx_clk_cnt;
    logic [3:0] rx_bit_cnt;
    logic [7:0] rx_shift;
    logic rx_sync1, rx_sync2;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= uart_rx;
            rx_sync2 <= rx_sync1;
        end
    end

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            rx_clk_cnt <= 0;
            rx_bit_cnt <= 0;
            rx_valid <= 1'b0;
            rx_data <= 8'h0;
        end else begin
            if (rx_read_ack) begin
                rx_valid <= 1'b0;
            end

            if (rx_bit_cnt == 0) begin
                if (!rx_sync2) begin // Start bit detected (falling edge)
                    rx_clk_cnt <= CLOCK_DIVIDE / 2; // sample at middle of bit
                    rx_bit_cnt <= 9; // 8 data + 1 stop
                end
            end else begin
                if (rx_clk_cnt == CLOCK_DIVIDE - 1) begin
                    rx_clk_cnt <= 0;
                    rx_bit_cnt <= rx_bit_cnt - 1;
                    
                    if (rx_bit_cnt > 1) begin
                        rx_shift <= {rx_sync2, rx_shift[7:1]};
                    end else if (rx_bit_cnt == 1) begin
                        // Stop bit
                        if (rx_sync2 == 1'b1) begin
                            rx_data <= rx_shift;
                            rx_valid <= 1'b1;
                        end
                    end
                end else begin
                    rx_clk_cnt <= rx_clk_cnt + 1;
                end
            end
        end
    end

endmodule
