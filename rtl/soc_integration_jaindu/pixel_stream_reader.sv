`timescale 1ns / 1ps

module pixel_stream_reader (
    input  logic clk,
    input  logic resetn,

    input  logic        start,
    input  logic [31:0] img_base,
    input  logic [31:0] img_len,
    output logic        done,
    output logic        busy,

    output logic [13:0] bram_addr,
    input  logic [31:0] bram_rdata,

    output logic [ 7:0] m_axis_tdata,
    output logic        m_axis_tvalid,
    output logic        m_axis_tuser,
    input  logic        m_axis_tready
);

    typedef enum logic [1:0] { IDLE, READ_REQ, READ_WAIT, STREAM } state_t;
    state_t state, next_state;

    logic [31:0] count;
    logic [1:0]  byte_idx;
    logic [31:0] current_word;

    assign busy = (state != IDLE);
    assign done = (state == IDLE) && (count == img_len) && (img_len > 0);

    always_comb begin
        case (byte_idx)
            2'b00: m_axis_tdata = current_word[7:0];
            2'b01: m_axis_tdata = current_word[15:8];
            2'b10: m_axis_tdata = current_word[23:16];
            2'b11: m_axis_tdata = current_word[31:24];
        endcase
    end

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= IDLE;
            count <= 0;
            bram_addr <= 0;
            byte_idx <= 0;
            m_axis_tvalid <= 0;
            m_axis_tuser <= 0;
            current_word <= 0;
        end else begin
            case (state)
                IDLE: begin
                    m_axis_tvalid <= 0;
                    if (start) begin
                        state <= READ_REQ;
                        count <= 0;
                        bram_addr <= img_base[15:2];
                        byte_idx <= img_base[1:0];
                    end
                end

                READ_REQ: begin
                    state <= READ_WAIT;
                end

                READ_WAIT: begin
                    current_word <= bram_rdata;
                    m_axis_tvalid <= 1;
                    m_axis_tuser <= (count == 0);
                    state <= STREAM;
                end

                STREAM: begin
                    if (m_axis_tready) begin
                        count <= count + 1;
                        if (count + 1 == img_len) begin
                            state <= IDLE;
                            m_axis_tvalid <= 0;
                        end else if (byte_idx == 2'b11) begin
                            byte_idx <= 0;
                            bram_addr <= bram_addr + 1;
                            state <= READ_REQ;
                            m_axis_tvalid <= 0;
                        end else begin
                            byte_idx <= byte_idx + 1;
                            m_axis_tuser <= 1'b0;
                        end
                    end
                end
            endcase
        end
    end

endmodule
