module board_test(
    input CLOCK_50,
    input [17:0] SW,
    input [3:0] KEY,

    output [17:0] LEDR,
    output [3:0] LEDG,

    output [6:0] HEX0,
    output [6:0] HEX1,
    output [6:0] HEX2,
    output [6:0] HEX3,
    output [6:0] HEX4,
    output [6:0] HEX5,
    output [6:0] HEX6,
    output [6:0] HEX7
);

reg [31:0] counter;

always @(posedge CLOCK_50)
    counter <= counter + 1;

// Switches -> LEDs
assign LEDR = SW;

// Buttons -> Green LEDs
assign LEDG = ~KEY;

// Counter on seven-segment displays
assign HEX0 = ~counter[22:16];
assign HEX1 = ~counter[23:17];
assign HEX2 = ~counter[24:18];
assign HEX3 = ~counter[25:19];
assign HEX4 = ~counter[26:20];
assign HEX5 = ~counter[27:21];
assign HEX6 = ~counter[28:22];
assign HEX7 = ~counter[29:23];

endmodule