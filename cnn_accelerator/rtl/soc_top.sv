`timescale 1 ns / 1 ps

module soc_top (
    input  logic        CLOCK_50,
    input  logic [3:0]  KEY,

    input  logic        UART_RXD,
    output logic        UART_TXD,

    output logic [6:0]  HEX0,
    output logic [6:0]  HEX1,
    output logic [6:0]  HEX2,
    output logic [6:0]  HEX3,
    output logic [6:0]  HEX4,
    output logic [6:0]  HEX5,
    output logic [6:0]  HEX6,
    output logic [6:0]  HEX7
);

    // ----------------------------------------------------------------
    // Clocking & Reset
    // ----------------------------------------------------------------
    logic        clk;
    logic        resetn;
    logic        uart_rx;
    logic        uart_tx;
    logic [31:0] gpio_out;

    assign clk      = CLOCK_50;
    assign resetn   = KEY[0];
    assign uart_rx  = UART_RXD;
    assign UART_TXD = uart_tx;

    // ----------------------------------------------------------------
    // CPU Memory Bus
    // ----------------------------------------------------------------
    logic        mem_valid;
    logic        mem_instr;
    logic        mem_ready;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [ 3:0] mem_wstrb;
    logic [31:0] mem_rdata;

    // ----------------------------------------------------------------
    // Slave Handshake Signals
    // ----------------------------------------------------------------
    logic        ram_valid,      ram_ready;
    logic [31:0] ram_rdata;

    logic        uart_valid,     uart_ready;
    logic [31:0] uart_rdata;

    logic        img_bram_valid, img_bram_ready;
    logic [31:0] img_bram_rdata;

    logic        out_bram_valid, out_bram_ready;
    logic [31:0] out_bram_rdata;

    logic        mac_ctrl_valid, mac_ctrl_ready;
    logic [31:0] mac_ctrl_rdata;

    logic        gpio_valid,     gpio_ready;
    logic [31:0] gpio_rdata;

    // ----------------------------------------------------------------
    // PicoRV32 CPU
    // ----------------------------------------------------------------
    picorv32 #(
        .PROGADDR_RESET(32'h0000_0000)
    ) cpu (
        .clk       (clk),
        .resetn    (resetn),
        .trap      (),
        .mem_valid (mem_valid),
        .mem_instr (mem_instr),
        .mem_ready (mem_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (mem_rdata)
    );

    // ----------------------------------------------------------------
    // Interconnect
    // ----------------------------------------------------------------
    soc_interconnect interconnect (
        .clk            (clk),
        .resetn         (resetn),
        .mem_valid      (mem_valid),
        .mem_instr      (mem_instr),
        .mem_ready      (mem_ready),
        .mem_addr       (mem_addr),
        .mem_wdata      (mem_wdata),
        .mem_wstrb      (mem_wstrb),
        .mem_rdata      (mem_rdata),
        .ram_valid      (ram_valid),
        .ram_ready      (ram_ready),
        .ram_rdata      (ram_rdata),
        .uart_valid     (uart_valid),
        .uart_ready     (uart_ready),
        .uart_rdata     (uart_rdata),
        .img_bram_valid (img_bram_valid),
        .img_bram_ready (img_bram_ready),
        .img_bram_rdata (img_bram_rdata),
        .out_bram_valid (out_bram_valid),
        .out_bram_ready (out_bram_ready),
        .out_bram_rdata (out_bram_rdata),
        .mac_ctrl_valid (mac_ctrl_valid),
        .mac_ctrl_ready (mac_ctrl_ready),
        .mac_ctrl_rdata (mac_ctrl_rdata),
        .gpio_valid     (gpio_valid),
        .gpio_ready     (gpio_ready),
        .gpio_rdata     (gpio_rdata)
    );

    // ----------------------------------------------------------------
    // RAM  (64 KB at 0x0000_0000)
    // ----------------------------------------------------------------
    logic [31:0] ram_memory [0:16383];

    always_ff @(posedge clk) begin
        ram_ready <= 1'b0;
        if (ram_valid && !ram_ready) begin
            ram_ready <= 1'b1;
            if (mem_wstrb[0]) ram_memory[mem_addr[15:2]][ 7: 0] <= mem_wdata[ 7: 0];
            if (mem_wstrb[1]) ram_memory[mem_addr[15:2]][15: 8] <= mem_wdata[15: 8];
            if (mem_wstrb[2]) ram_memory[mem_addr[15:2]][23:16] <= mem_wdata[23:16];
            if (mem_wstrb[3]) ram_memory[mem_addr[15:2]][31:24] <= mem_wdata[31:24];
            ram_rdata <= ram_memory[mem_addr[15:2]];
        end
    end

    // ----------------------------------------------------------------
    // UART Peripheral  (0x1000_0000)
    // ----------------------------------------------------------------
    uart_peripheral uart (
        .clk     (clk),
        .resetn  (resetn),
        .valid   (uart_valid),
        .addr    (mem_addr),
        .wdata   (mem_wdata),
        .wstrb   (mem_wstrb),
        .rdata   (uart_rdata),
        .ready   (uart_ready),
        .uart_rx (uart_rx),
        .uart_tx (uart_tx)
    );

    // ----------------------------------------------------------------
    // GPIO Peripheral  (0x5000_0000)
    // ----------------------------------------------------------------
    gpio_peripheral gpio (
        .clk      (clk),
        .resetn   (resetn),
        .valid    (gpio_valid),
        .addr     (mem_addr),
        .wdata    (mem_wdata),
        .wstrb    (mem_wstrb),
        .rdata    (gpio_rdata),
        .ready    (gpio_ready),
        .gpio_out (gpio_out)
    );

    // ----------------------------------------------------------------
    // Sliding Window  (pixel writes to 0x2000_0000 → 3x3 windows)
    // ----------------------------------------------------------------
    logic [7:0] pixel_axis_tdata;
    logic       pixel_axis_tvalid;
    logic       pixel_axis_tready;

    logic [7:0] window_data [0:2][0:2];
    logic       window_valid;
    logic       window_ready;

    assign pixel_axis_tdata  = mem_wdata[7:0];
    assign pixel_axis_tvalid = img_bram_valid & (|mem_wstrb);

    slidingWindowAXI #(
        .DATA_WIDTH(8),
        .ROW_LENGTH(28)
    ) window_gen (
        .clk           (clk),
        .rstn          (resetn),
        .s_axis_tdata  (pixel_axis_tdata),
        .s_axis_tvalid (pixel_axis_tvalid),
        .s_axis_tready (pixel_axis_tready),
        .m_axis_tdata  (window_data),
        .m_axis_tvalid (window_valid),
        .m_axis_tready (window_ready)
    );

    // ----------------------------------------------------------------
    // Datapath Top  (convolution engine — MAC → adder → quant → ReLU)
    //
    // MAC_CTRL register map  (0x4000_0000):
    //   +0x00  [0]   = start enable  (W) / [1] = result_ready (R)
    //   +0x04        = weights[31:0]
    //   +0x08        = weights[63:32]
    //   +0x0C  [7:0] = weights[71:64]
    //   +0x10 [15:0] = bias (signed)
    //   +0x14  [4:0] = shift_s
    //
    // OUT_BRAM  (0x3000_0000):
    //   +0x00        = latched relu_out (read clears result_ready flag)
    // ----------------------------------------------------------------
    logic [71:0] dp_weights;
    logic [15:0] dp_bias;
    logic [ 4:0] dp_shift_s;
    logic        dp_enable;

    logic signed [7:0] dp_relu_out;
    logic              dp_valid_out;

    logic        result_ready;
    logic [31:0] result_latch;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            dp_enable   <= 1'b0;
            dp_weights  <= '0;
            dp_bias     <= '0;
            dp_shift_s  <= '0;
        end else if (mac_ctrl_valid && mem_wstrb != 4'b0000) begin
            case (mem_addr[7:0])
                8'h00: dp_enable          <= mem_wdata[0];
                8'h04: dp_weights[31:0]   <= mem_wdata;
                8'h08: dp_weights[63:32]  <= mem_wdata;
                8'h0C: dp_weights[71:64]  <= mem_wdata[7:0];
                8'h10: dp_bias            <= mem_wdata[15:0];
                8'h14: dp_shift_s         <= mem_wdata[4:0];
                default: ;
            endcase
        end
    end

    logic [71:0] dp_pixels;
    genvar r, c;
    generate
        for (r = 0; r < 3; r++) begin : gen_row
            for (c = 0; c < 3; c++) begin : gen_col
                assign dp_pixels[8*(r*3+c+1)-1 -: 8] = window_data[r][c];
            end
        end
    endgenerate

    assign window_ready = dp_enable;

    datapath_top #(
        .DATA_WIDTH  (8),
        .PROD_WIDTH  (16),
        .SHIFT_WIDTH (5),
        .NUM_TAPS    (9)
    ) dp (
        .clk       (clk),
        .rst_n     (resetn),
        .valid_in  (window_valid & dp_enable),
        .pixels    (dp_pixels),
        .weights   (dp_weights),
        .bias      ($signed(dp_bias)),
        .shift_s   (dp_shift_s),
        .relu_out  (dp_relu_out),
        .valid_out (dp_valid_out)
    );

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            result_ready <= 1'b0;
            result_latch <= 32'h0;
        end else begin
            if (dp_valid_out) begin
                result_latch <= {{24{dp_relu_out[7]}}, dp_relu_out};
                result_ready <= 1'b1;
            end else if (out_bram_valid && mem_wstrb == 4'b0000) begin
                result_ready <= 1'b0;
            end
        end
    end

    // ----------------------------------------------------------------
    // Bus Handshake Block
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            img_bram_ready <= 1'b0;
            img_bram_rdata <= 32'h0;
            out_bram_ready <= 1'b0;
            out_bram_rdata <= 32'h0;
            mac_ctrl_ready <= 1'b0;
            mac_ctrl_rdata <= 32'h0;
        end else begin
            img_bram_ready <= img_bram_valid && (pixel_axis_tready || (mem_wstrb == 4'b0000));
            img_bram_rdata <= 32'h0;

            out_bram_ready <= out_bram_valid;
            out_bram_rdata <= result_latch;

            mac_ctrl_ready <= mac_ctrl_valid;
            mac_ctrl_rdata <= {30'h0, result_ready, dp_enable};
        end
    end

    // ----------------------------------------------------------------
    // 7-Segment Display
    // ----------------------------------------------------------------
    function [6:0] hex_decode;
        input [3:0] data;
        case(data)
            4'h0: hex_decode = 7'b1000000;
            4'h1: hex_decode = 7'b1111001;
            4'h2: hex_decode = 7'b0100100;
            4'h3: hex_decode = 7'b0110000;
            4'h4: hex_decode = 7'b0011001;
            4'h5: hex_decode = 7'b0010010;
            4'h6: hex_decode = 7'b0000010;
            4'h7: hex_decode = 7'b1111000;
            4'h8: hex_decode = 7'b0000000;
            4'h9: hex_decode = 7'b0010000;
            4'ha: hex_decode = 7'b0001000;
            4'hb: hex_decode = 7'b0000011;
            4'hc: hex_decode = 7'b1000110;
            4'hd: hex_decode = 7'b0100001;
            4'he: hex_decode = 7'b0000110;
            4'hf: hex_decode = 7'b0001110;
            default: hex_decode = 7'b1111111;
        endcase
    endfunction

    assign HEX0 = hex_decode(gpio_out[3:0]);
    assign HEX1 = hex_decode(gpio_out[7:4]);
    assign HEX2 = hex_decode(gpio_out[11:8]);
    assign HEX3 = hex_decode(gpio_out[15:12]);
    assign HEX4 = hex_decode(gpio_out[19:16]);
    assign HEX5 = hex_decode(gpio_out[23:20]);
    assign HEX6 = hex_decode(gpio_out[27:24]);
    assign HEX7 = hex_decode(gpio_out[31:28]);

endmodule