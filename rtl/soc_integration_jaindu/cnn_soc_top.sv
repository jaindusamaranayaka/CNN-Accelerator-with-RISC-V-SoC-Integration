`timescale 1 ns / 1 ps
module cnn_soc_top (
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
    logic        clk;
    logic        resetn;
    logic        uart_rx;
    logic        uart_tx;
    logic [31:0] gpio_out;
    assign clk      = CLOCK_50;
    assign resetn   = KEY[0];
    assign uart_rx  = UART_RXD;
    assign UART_TXD = uart_tx;
    logic        mem_valid;
    logic        mem_instr;
    logic        mem_ready;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [ 3:0] mem_wstrb;
    logic [31:0] mem_rdata;
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
    logic        class_weight_valid;
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
    soc_bus_interconnect u_interconnect (
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
        .gpio_rdata     (gpio_rdata),
        .class_weight_valid(class_weight_valid)
    );
    logic [31:0] ram_memory [0:16383];
    initial $readmemh("firmware.hex", ram_memory);
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
    uart_serial_controller uart (
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
    display_gpio_peripheral gpio (
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
    logic [13:0] bram_addr;
    logic [31:0] bram_rdata;
    logic [31:0] img_base;
    logic [31:0] img_len;
    logic        re_start;
    logic        re_done;
    logic        re_busy;

    image_buffer_bram #(
        .DEPTH(1024)
    ) img_bram (
        .clk(clk),
        .a_addr(mem_addr),
        .a_wdata(mem_wdata),
        .a_wstrb(mem_wstrb),
        .a_en(img_bram_valid && (|mem_wstrb)),
        .a_rdata(),
        .b_addr(bram_addr),
        .b_rdata(bram_rdata)
    );
    assign img_bram_rdata = 32'h0;

    logic pixel_axis_tuser;
    logic [7:0] pixel_axis_tdata;
    logic       pixel_axis_tvalid;
    logic       pixel_axis_tready;

    pixel_stream_reader re (
        .clk(clk),
        .resetn(resetn),
        .start(re_start),
        .img_base(img_base),
        .img_len(img_len),
        .done(re_done),
        .busy(re_busy),
        .bram_addr(bram_addr),
        .bram_rdata(bram_rdata),
        .m_axis_tdata(pixel_axis_tdata),
        .m_axis_tvalid(pixel_axis_tvalid),
        .m_axis_tuser(pixel_axis_tuser),
        .m_axis_tready(pixel_axis_tready)
    );

    logic [7:0] window_data [0:2][0:2];
    logic       window_valid;
    logic       window_ready;

    slidingWindowAXIBRAM #(
        .DATA_WIDTH(8),
        .ROW_LENGTH(28),
        .PADDING(0)
    ) window_gen (
        .clk           (clk),
        .rstn          (resetn),
        .s_axis_tdata  (pixel_axis_tdata),
        .s_axis_tvalid (pixel_axis_tvalid),
        .s_axis_tuser  (pixel_axis_tuser),
        .s_axis_tready (pixel_axis_tready),
        .m_axis_tdata  (window_data),
        .m_axis_tvalid (window_valid),
        .m_axis_tready (1'b1)
    );
    logic [71:0] dp_weights;
    logic [15:0] dp_bias;
    logic [ 4:0] dp_shift_s;
    logic        dp_enable;
    logic        result_ready;
    logic [31:0] result_latch;
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            dp_enable   <= 1'b1;
            re_start    <= 1'b0;
            img_base    <= '0;
            img_len     <= '0;
            dp_weights  <= '0;
            dp_bias     <= '0;
            dp_shift_s  <= '0;
        end else begin
            re_start <= 1'b0;
            if (mac_ctrl_valid && mem_wstrb != 4'b0000) begin
                case (mem_addr[7:0])
                    8'h00: re_start           <= mem_wdata[0] && !re_busy;
                    8'h04: img_base           <= mem_wdata;
                    8'h08: img_len            <= mem_wdata;
                    8'h0C: dp_weights[31:0]   <= mem_wdata;
                    8'h10: dp_weights[63:32]  <= mem_wdata;
                    8'h14: dp_weights[71:64]  <= mem_wdata[7:0];
                    8'h18: dp_bias            <= mem_wdata[15:0];
                    8'h1C: dp_shift_s         <= mem_wdata[4:0];
                    default: ;
                endcase
            end
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

    logic class_valid;
    logic [3:0] class_id;

    cnn_core nn_pipeline (
        .clk          (clk),
        .rst_n        (resetn),
        .accel_start  (re_start),
        .weights      (dp_weights),
        .bias         (dp_bias),
        .shift_s      (dp_shift_s),
        .valid_in     (window_valid & dp_enable),
        .pixels       (dp_pixels),
        .weight_wr_en (class_weight_valid && (|mem_wstrb)),
        .weight_addr  (mem_addr),
        .weight_wdata (mem_wdata),
        .class_valid  (class_valid),
        .class_id     (class_id)
    );

    logic [31:0] final_class_reg;
    logic class_ready_flag;

    assign result_ready = class_ready_flag;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            final_class_reg <= 0;
            class_ready_flag <= 0;
        end else begin
            if (class_valid) begin
                final_class_reg <= {28'h0, class_id};
                class_ready_flag <= 1'b1;
            end else if (re_start || (out_bram_valid && !out_bram_ready && mem_wstrb == 4'b0000)) begin
                class_ready_flag <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            img_bram_ready <= 1'b0;
            out_bram_ready <= 1'b0;
            out_bram_rdata <= 32'h0;
            mac_ctrl_ready <= 1'b0;
            mac_ctrl_rdata <= 32'h0;
        end else begin
            img_bram_ready <= 1'b0;
            if (img_bram_valid && !img_bram_ready)
                img_bram_ready <= 1'b1;

            out_bram_ready <= 1'b0;
            if (out_bram_valid && !out_bram_ready)
                out_bram_ready <= 1'b1;

            out_bram_rdata <= final_class_reg;

            mac_ctrl_ready <= 1'b0;
            if (mac_ctrl_valid && !mac_ctrl_ready)
                mac_ctrl_ready <= 1'b1;

            if (mac_ctrl_valid && !mac_ctrl_ready && mem_wstrb == 4'b0000) begin
                case (mem_addr[7:0])
                    8'h00: mac_ctrl_rdata <= {30'h0, result_ready, re_busy};
                    8'h04: mac_ctrl_rdata <= img_base;
                    8'h08: mac_ctrl_rdata <= img_len;
                    default: mac_ctrl_rdata <= 32'h0;
                endcase
            end else begin
                mac_ctrl_rdata <= 32'h0;
            end
        end
    end
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
            4'hd: hex_decode = 7'b0100010;
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
