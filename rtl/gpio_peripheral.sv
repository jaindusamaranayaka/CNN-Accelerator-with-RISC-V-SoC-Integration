`timescale 1 ns / 1 ps

module gpio_peripheral (
    input  logic        clk,
    input  logic        resetn,

    // Memory-mapped interface
    input  logic        valid,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    input  logic [ 3:0] wstrb,
    output logic [31:0] rdata,
    output logic        ready,

    // GPIO output
    output logic [31:0] gpio_out
);

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            ready <= 1'b0;
            rdata <= 32'h0;
            gpio_out <= 32'h0;
        end else begin
            ready <= 1'b0;
            
            if (valid && !ready) begin
                ready <= 1'b1;
                
                if (wstrb != 4'b0000) begin
                    // Write
                    if (addr[3:0] == 4'h0) begin
                        if (wstrb[0]) gpio_out[7:0]   <= wdata[7:0];
                        if (wstrb[1]) gpio_out[15:8]  <= wdata[15:8];
                        if (wstrb[2]) gpio_out[23:16] <= wdata[23:16];
                        if (wstrb[3]) gpio_out[31:24] <= wdata[31:24];
                    end
                end else begin
                    // Read
                    if (addr[3:0] == 4'h0) begin
                        rdata <= gpio_out;
                    end else begin
                        rdata <= 32'h0;
                    end
                end
            end
        end
    end

endmodule
