// Reads one image from the shared memory and streams it to the sliding window one pixel per clock.

// A one cycle 'start' pulse reads img_base and img_len. (Ignored during busy is high)
// Pixels are read from img_base, img_base + 1, .... and so on.
// First pixel of an image is marked with m_axis_tuser = 1
// After image, DRAIN zero-valued pixels are sent to flush the last windows out of sliding window (DRAIN = 2 for PADDING = 0)
// Busy is high until the very last pixel (including DRAIN) has been sent.

// Memory has 1-cycle latency for reading, hence every pixel is considered as a request with three flags (valid, first, zero). 
// Flags will be registered once to make sure they leave the module in the same cycle as the memory data

// img_len >= 1
// No backpressure support as of now


module image_reader #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_W = 11, // Byte address width of image memory
    parameter int DRAIN = 2 // Flush pixels 
) (
    input logic clk,
    input logic rstn,

    // Control from CPU registers   
    input logic start, // 1 cycle pulse indicating start of a read
    input logic [ADDR_W-1:0] img_base, // Byte address of first pixel
    input logic [ADDR_W-1:0] img_len, // Total number of pixels
    output logic busy, // Kept high until last pixel

    // Image memory read port with 1 cycle latency
    output logic [ADDR_W-1:0] mem_raddr, // Sent to memory (BRAM)
    input logic [DATA_WIDTH-1:0] mem_rdata, // Received from (BRAM)

    // AXI Stream master 
    output logic [DATA_WIDTH-1:0] m_axis_tdata, // Sent to sliding window
    output logic m_axis_tvalid,
    output logic m_axis_tuser, // Indicate first pixel of an image
    input logic m_axis_tready 
);
    logic [ADDR_W-1:0] addr; // Address requested current cycle
    logic [ADDR_W-1:0] count; // Number of issued requests in current state
    logic [ADDR_W-1:0] len_q; // Image length 

    assign mem_raddr = addr;

    typedef enum logic [1:0] {
        S_IDLE = 2'b00, // Waiting for 1 cycle 'start' pulse
        S_READ = 2'b01, // One real pixel request every cycle
        S_DRAIN = 2'b10 // DRAIN zero-pixel requests per image
    } state_t;

    state_t current_state;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            current_state <= S_IDLE;
            addr <= '0;
            count <= '0;
            len_q <= '0;
        end else begin
            case (current_state) 
                // Latches the image location and size
                // Start pulse is only accepted here, and it is ignored during a run
                S_IDLE: begin
                    if (start) begin
                        addr <= img_base;
                        len_q <= img_len;
                        count <= '0;
                        current_state <= S_READ;
                    end
                end

                // Requests pixels (img_base , img_base + 1, ..., img_base + len - 1) per cycle
                S_READ: begin
                    if (count == len_q - 1) begin // Last pixel
                        count <= '0;
                        current_state <= S_DRAIN;
                    end else begin
                        addr <= addr + 1;
                        count <= count + 1;
                    end
                end

                // Issues zero-pixels for DRAIN requests
                S_DRAIN: begin
                    if (count == DRAIN - 1) begin
                        count <= '0;
                        current_state <= S_IDLE;
                    end else begin
                        count <= count + 1;
                    end
                end
                
                default: current_state <= S_IDLE;

            endcase
        end
    end

    // Flags
    logic req_valid; // A pixel is requested (real or DRAIN)
    logic req_first; // First pixel
    logic req_zero; // DRAIN zero-pixel

    always_comb begin
        req_valid = ((current_state == S_READ) || (current_state == S_DRAIN));
        req_first = ((current_state == S_READ) && count == 0);
        req_zero = (current_state == S_DRAIN);

    end

    // Flags delayed via registers to line up with memory's 1 cycle read latency
    logic valid_q;
    logic first_q;
    logic zero_q;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            valid_q <= 0;
            first_q <= 0;
            zero_q <= 0;
        end else begin
            valid_q <= req_valid;
            first_q <= req_first;
            zero_q <= req_zero;
        end
    end

    assign m_axis_tvalid = valid_q;
    assign m_axis_tuser = first_q;
    assign m_axis_tdata = zero_q ? '0 : mem_rdata; // DRAIN pixels are zero

    // Busy until state is IDLE and last pixel left the module
    assign busy = ((current_state != S_IDLE) || valid_q); 

    // synthesis translate_off
    always @(posedge clk) begin
        if (rstn && m_axis_tvalid) begin
            assert(m_axis_tready)
            else $error("Reader doesn't support backpressure.");
        end
    end 
    // synthesis translate_on
    
endmodule