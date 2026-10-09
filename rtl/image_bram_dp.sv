module image_bram_dp #(
    parameter int DEPTH_WORDS = 512,
    localparam int WADDR_W = $clog2(DEPTH_WORDS) ,// Word address width
    localparam int BADDR_W = $clog2(DEPTH_WORDS) + 2 // Byte address width
) (
    input logic clk,
    input logic a_we,
    input logic [WADDR_W-1:0] a_waddr,
    input logic [31:0] a_wdata,
    input logic [3:0] a_wstrb,
    input logic [BADDR_W-1:0] b_raddr,
    output logic [7:0] b_rdata
);
    // Same Clock for both reading and writing, CPU writes the image before starting the accelerator, so the ports
    // never touch the same address in the same cycle.

    // Little Endian addressing
    

    // 4 Banks
    genvar k;
    generate 
        for (k = 0; k < 4; k++) begin : banks
            (* ramstyle = "M9K" *) logic [7:0] mem_arr [0:DEPTH_WORDS-1]; // To instantiate M9K blocks in FPGA
            logic [7:0] read_reg;

            always_ff @(posedge clk) begin
                if (a_we && a_wstrb[k]) begin
                    mem_arr[a_waddr] <= a_wdata[8*k +: 8]; 
                end
                read_reg <= mem_arr[b_raddr[BADDR_W-1:2]];
            end
        end
    endgenerate

    // Delayed Bank Select
    logic [1:0] bsel_q;

    always_ff @(posedge clk) begin
        bsel_q <= b_raddr[1:0];
    end

    // Output Selector
    always_comb begin
        case (bsel_q)
            2'b00  : b_rdata = banks[0].read_reg;
            2'b01  : b_rdata = banks[1].read_reg;
            2'b10  : b_rdata = banks[2].read_reg;
            2'b11  : b_rdata = banks[3].read_reg;
            default: b_rdata = banks[0].read_reg;
        endcase

    end
endmodule
