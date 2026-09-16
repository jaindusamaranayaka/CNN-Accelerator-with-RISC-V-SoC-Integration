`timescale 1ns / 1ps

module lineBufferAXIBRAM #(
    parameter int DATA_WIDTH = 8,
    parameter int ROW_LENGTH = 8
)(
    input logic clk,
    input logic rstn,
    input logic wr_en,
    input logic [DATA_WIDTH-1:0] data_in,
    output logic [DATA_WIDTH-1:0] data_out
);

    (* ramstyle = "M9K" *)    logic [DATA_WIDTH-1:0] mem [0:ROW_LENGTH-1];
    logic [$clog2(ROW_LENGTH)-1:0] ptr;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            ptr <= '0;
        end else begin
            if (wr_en) begin
                if(ptr == ROW_LENGTH - 1) begin
                    ptr <= '0;
                end else begin 
                    ptr <= ptr + 1;
                end
            end
        end    
    end


    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            data_out <= '0;
        end else if (wr_en) begin
            mem[ptr] <= data_in;
            data_out <= mem[ptr];
        end
    end
endmodule