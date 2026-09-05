`timescale 1 ns / 1 ps

module soc_interconnect (
    input  logic        clk,
    input  logic        resetn,

    // PicoRV32 Master Interface
    input  logic        mem_valid,
    input  logic        mem_instr,
    output logic        mem_ready,
    input  logic [31:0] mem_addr,
    input  logic [31:0] mem_wdata,
    input  logic [ 3:0] mem_wstrb,
    output logic [31:0] mem_rdata,

    // Slave 0: RAM/ROM (0x0000_0000)
    output logic        ram_valid,
    input  logic        ram_ready,
    input  logic [31:0] ram_rdata,

    // Slave 1: UART (0x1000_0000)
    output logic        uart_valid,
    input  logic        uart_ready,
    input  logic [31:0] uart_rdata,

    // Slave 2: Image BRAM (0x2000_0000)
    output logic        img_bram_valid,
    input  logic        img_bram_ready,
    input  logic [31:0] img_bram_rdata,

    // Slave 3: Output BRAM (0x3000_0000)
    output logic        out_bram_valid,
    input  logic        out_bram_ready,
    input  logic [31:0] out_bram_rdata,

    // Slave 4: MAC Control (0x4000_0000)
    output logic        mac_ctrl_valid,
    input  logic        mac_ctrl_ready,
    input  logic [31:0] mac_ctrl_rdata,

    // Slave 5: GPIO/Display (0x5000_0000)
    output logic        gpio_valid,
    input  logic        gpio_ready,
    input  logic [31:0] gpio_rdata
);

    // Address Decoder
    logic sel_ram;
    logic sel_uart;
    logic sel_img_bram;
    logic sel_out_bram;
    logic sel_mac_ctrl;
    logic sel_gpio;

    assign sel_ram      = (mem_addr[31:28] == 4'h0);
    assign sel_uart     = (mem_addr[31:28] == 4'h1);
    assign sel_img_bram = (mem_addr[31:28] == 4'h2);
    assign sel_out_bram = (mem_addr[31:28] == 4'h3);
    assign sel_mac_ctrl = (mem_addr[31:28] == 4'h4);
    assign sel_gpio     = (mem_addr[31:28] == 4'h5);

    // Route Valid signal to selected slave
    assign ram_valid      = mem_valid & sel_ram;
    assign uart_valid     = mem_valid & sel_uart;
    assign img_bram_valid = mem_valid & sel_img_bram;
    assign out_bram_valid = mem_valid & sel_out_bram;
    assign mac_ctrl_valid = mem_valid & sel_mac_ctrl;
    assign gpio_valid     = mem_valid & sel_gpio;

    // Route Ready signal from selected slave
    always_comb begin
        mem_ready = 1'b0;
        if (sel_ram)      mem_ready = ram_ready;
        if (sel_uart)     mem_ready = uart_ready;
        if (sel_img_bram) mem_ready = img_bram_ready;
        if (sel_out_bram) mem_ready = out_bram_ready;
        if (sel_mac_ctrl) mem_ready = mac_ctrl_ready;
        if (sel_gpio)     mem_ready = gpio_ready;
    end

    // Route Read Data from selected slave
    always_comb begin
        mem_rdata = 32'h0;
        if (sel_ram)      mem_rdata = ram_rdata;
        if (sel_uart)     mem_rdata = uart_rdata;
        if (sel_img_bram) mem_rdata = img_bram_rdata;
        if (sel_out_bram) mem_rdata = out_bram_rdata;
        if (sel_mac_ctrl) mem_rdata = mac_ctrl_rdata;
        if (sel_gpio)     mem_rdata = gpio_rdata;
    end

endmodule
