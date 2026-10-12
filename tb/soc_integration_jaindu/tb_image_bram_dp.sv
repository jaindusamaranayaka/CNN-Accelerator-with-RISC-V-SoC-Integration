module tb_image_bram_dp;
    localparam int DEPTH_WORDS = 512;
    localparam int WADDR_W = $clog2(DEPTH_WORDS);
    localparam int BADDR_W = $clog2(DEPTH_WORDS) + 2;

    logic clk;
    logic a_we;
    logic [WADDR_W-1:0] a_waddr;
    logic [31:0] a_wdata;
    logic [3:0] a_wstrb;
    logic [BADDR_W-1:0] b_raddr;
    logic [7:0] b_rdata;

    localparam int NUM_BYTES = DEPTH_WORDS * 4;

    image_bram_dp #(
        .DEPTH_WORDS(DEPTH_WORDS)
    ) dut (
        .clk(clk),
        .a_we(a_we),
        .a_waddr(a_waddr),
        .a_wdata(a_wdata),
        .a_wstrb(a_wstrb),
        .b_raddr(b_raddr),
        .b_rdata(b_rdata)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    logic [7:0] model_mem [0:NUM_BYTES-1];

    int checks = 0;
    int mismatches = 0;
    int prev_addr = -1;
    initial begin
        
        a_we = 0;
        a_wstrb = 0;
        b_raddr = 0;
        
        repeat (2) @(posedge clk);

        for (int i = 0; i < DEPTH_WORDS; i ++) begin
            write_word(i, $urandom(), 4'b1111);
        end
        write_word(0, $urandom(), 4'b0001);
        write_word(1, $urandom(), 4'b0100);
        write_word(2, $urandom(), 4'b1000);
        write_word(3, $urandom(), 4'b0110);
        write_word(300, $urandom(), 4'b0011);
        $display("Writing Phase completed.");

        
        for (int h = 0; h < NUM_BYTES+1; h++) begin
            @(negedge clk);
            if (h < NUM_BYTES) begin
                b_raddr = h;
            end
            #1;
            if (prev_addr >= 0) begin
                checks++;
                if (b_rdata != model_mem[prev_addr]) begin 
                    mismatches++;
                    $display("Address: %h, Expected Value: %h, Actual Value: %h", prev_addr, model_mem[prev_addr] , b_rdata );
                end
            end
            if (h < NUM_BYTES) begin
                prev_addr = h;
            end
            
        end
        $display("Checks: %0d, Mismatches: %0d", checks, mismatches);
        $finish();
    end

    task automatic write_word (
        input logic [WADDR_W-1:0] addr,
        input logic [31:0] data,
        input logic [3:0] strobe
    );
        @(negedge clk);
        a_we = 1;
        a_waddr = addr;
        a_wdata = data;
        a_wstrb = strobe;
        for (int j = 0; j < 4; j++) begin
            if (strobe[j]) begin
                model_mem[addr * 4 + j] = data[j * 8 +: 8];
            end 
        end
        @(negedge clk);
        a_we = 0;

    endtask


endmodule