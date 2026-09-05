`timescale 1 ns / 1 ps

module soc_top (
    input  logic        CLOCK_50,
    input  logic [3:0]  KEY, // KEY[0] used for reset

    // UART pins
    input  logic        UART_RXD,
    output logic        UART_TXD,

    // 7-Segment Displays
    output logic [6:0]  HEX0,
    output logic [6:0]  HEX1,
    output logic [6:0]  HEX2,
    output logic [6:0]  HEX3,
    output logic [6:0]  HEX4,
    output logic [6:0]  HEX5,
    output logic [6:0]  HEX6,
    output logic [6:0]  HEX7
);

    // Internal signals matching old port names
    logic        clk;
    logic        resetn;
    logic        uart_rx;
    logic        uart_tx;
    logic [31:0] gpio_out;

    assign clk = CLOCK_50;
    assign resetn = KEY[0]; // Active low reset from push button
    assign uart_rx = UART_RXD;
    assign UART_TXD = uart_tx;

    // ==========================================
    // Interconnect Signals
    // ==========================================
    logic        mem_valid;
    logic        mem_instr;
    logic        mem_ready;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [ 3:0] mem_wstrb;
    logic [31:0] mem_rdata;

    // Slaves
    logic        ram_valid;
    logic        ram_ready;
    logic [31:0] ram_rdata;

    logic        uart_valid;
    logic        uart_ready;
    logic [31:0] uart_rdata;

    logic        img_bram_valid;
    logic        img_bram_ready;
    logic [31:0] img_bram_rdata;

    logic        out_bram_valid;
    logic        out_bram_ready;
    logic [31:0] out_bram_rdata;

    logic        mac_ctrl_valid;
    logic        mac_ctrl_ready;
    logic [31:0] mac_ctrl_rdata;

    logic        gpio_valid;
    logic        gpio_ready;
    logic [31:0] gpio_rdata;

    // ==========================================
    // PicoRV32 CPU
    // ==========================================
    picorv32 #(
        .PROGADDR_RESET(32'h0000_0000)
    ) cpu (
        .clk        (clk),
        .resetn     (resetn),
        .trap       (),

        .mem_valid  (mem_valid),
        .mem_instr  (mem_instr),
        .mem_ready  (mem_ready),
        .mem_addr   (mem_addr),
        .mem_wdata  (mem_wdata),
        .mem_wstrb  (mem_wstrb),
        .mem_rdata  (mem_rdata)
    );

    // ==========================================
    // Interconnect FSM
    // ==========================================
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

    // ==========================================
    // Memory (RAM/ROM Stub)
    // ==========================================
    // Simple 64KB RAM
    logic [31:0] ram_memory [0:16383]; // 16K x 32bit = 64KB
    
    always_ff @(posedge clk) begin
        ram_ready <= 1'b0;
        if (ram_valid && !ram_ready) begin
            ram_ready <= 1'b1;
            if (mem_wstrb[0]) ram_memory[mem_addr[15:2]][7:0]   <= mem_wdata[7:0];
            if (mem_wstrb[1]) ram_memory[mem_addr[15:2]][15:8]  <= mem_wdata[15:8];
            if (mem_wstrb[2]) ram_memory[mem_addr[15:2]][23:16] <= mem_wdata[23:16];
            if (mem_wstrb[3]) ram_memory[mem_addr[15:2]][31:24] <= mem_wdata[31:24];
            ram_rdata <= ram_memory[mem_addr[15:2]];
        end
    end

    // ==========================================
    // Peripherals
    // ==========================================
    uart_peripheral uart (
        .clk        (clk),
        .resetn     (resetn),
        .valid      (uart_valid),
        .addr       (mem_addr),
        .wdata      (mem_wdata),
        .wstrb      (mem_wstrb),
        .rdata      (uart_rdata),
        .ready      (uart_ready),
        .uart_rx    (uart_rx),
        .uart_tx    (uart_tx)
    );

    gpio_peripheral gpio (
        .clk        (clk),
        .resetn     (resetn),
        .valid      (gpio_valid),
        .addr       (mem_addr),
        .wdata      (mem_wdata),
        .wstrb      (mem_wstrb),
        .rdata      (gpio_rdata),
        .ready      (gpio_ready),
        .gpio_out   (gpio_out)
    );

    // ==========================================
    // Hardware Accelerator: Sliding Window (AXI Stream)
    // ==========================================
    // Streaming interface signals
    logic [7:0]  pixel_axis_tdata;
    logic        pixel_axis_tvalid;
    logic        pixel_axis_tready;

    // 3x3 Window output from sliding window
    logic [7:0]  window_data [0:2][0:2];
    logic        window_valid;
    logic        window_ready;

    // Always ready to consume 3x3 windows for now (until Stage 1 feature1 is attached)
    assign window_ready = 1'b1;

    // When CPU writes to Image BRAM address range (0x2000_0000), stream the byte into the sliding window
    assign pixel_axis_tdata  = mem_wdata[7:0];
    assign pixel_axis_tvalid = img_bram_valid && (|mem_wstrb);

    // Sliding window instance (28x28 grayscale image, so row length = 28)
    slidingWindowAXI #(
        .DATA_WIDTH(8),
        .ROW_LENGTH(28)
    ) window_gen (
        .clk           (clk),
        .rstn          (resetn),

        // Slave stream (Input pixel stream from CPU)
        .s_axis_tdata  (pixel_axis_tdata),
        .s_axis_tvalid (pixel_axis_tvalid),
        .s_axis_tready (pixel_axis_tready),

        // Master stream (3x3 Matrix Output to future CNN stages)
        .m_axis_tdata  (window_data),
        .m_axis_tvalid (window_valid),
        .m_axis_tready (window_ready)
    );

    // ==========================================
    // CNN Hardware Accelerator
    // ==========================================
    logic [31:0] cnn_class_result;
    logic        cnn_done;
    logic [2:0]  dummy_kernel [0:2]; 
    
    // Assign dummy kernel to all zeros for now
    assign dummy_kernel[0] = 3'b000;
    assign dummy_kernel[1] = 3'b000;
    assign dummy_kernel[2] = 3'b000;

    logic cnn_start;
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            cnn_start <= 1'b0;
        end else if (mac_ctrl_valid && mem_wstrb != 4'b0000) begin
            cnn_start <= mem_wdata[0]; // Start pulse when CPU writes to bit 0 of MAC_CTRL (0x4000_0000)
        end else begin
            cnn_start <= 1'b0; 
        end
    end

    cnn_acc my_cnn (
        .clk          (clk),
        .rst          (~resetn),
        .start        (cnn_start),
        .window_data  (window_data),
        .window_valid (window_valid),
        .kernel       (dummy_kernel),
        .class_result (cnn_class_result),
        .done         (cnn_done)
    );

    // Bus Handshaking & Control Registers
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            img_bram_ready <= 1'b0;
            img_bram_rdata <= 32'h0;

            out_bram_ready <= 1'b0;
            out_bram_rdata <= 32'h0;

            mac_ctrl_ready <= 1'b0;
            mac_ctrl_rdata <= 32'h0;
        end else begin
            // Handshake for Image BRAM writes: acknowledge when slave is ready
            img_bram_ready <= img_bram_valid && (pixel_axis_tready || (mem_wstrb == 4'b0000));
            img_bram_rdata <= 32'h0;

            // Output BRAM interface
            out_bram_ready <= out_bram_valid;
            out_bram_rdata <= cnn_class_result;

            // MAC Control & Status register interface (0x4000_0000)
            // Bit 0: Start, Bit 1: CNN Done flag
            mac_ctrl_ready <= mac_ctrl_valid;
            mac_ctrl_rdata <= {30'h0, cnn_done, 1'b0};
        end
    end

    // ==========================================
    // 7-Segment Display Decoders
    // ==========================================
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

    // Drive 7-segment displays from the gpio_out register
    assign HEX0 = hex_decode(gpio_out[3:0]);
    assign HEX1 = hex_decode(gpio_out[7:4]);
    assign HEX2 = hex_decode(gpio_out[11:8]);
    assign HEX3 = hex_decode(gpio_out[15:12]);
    assign HEX4 = hex_decode(gpio_out[19:16]);
    assign HEX5 = hex_decode(gpio_out[23:20]);
    assign HEX6 = hex_decode(gpio_out[27:24]);
    assign HEX7 = hex_decode(gpio_out[31:28]);

endmodule