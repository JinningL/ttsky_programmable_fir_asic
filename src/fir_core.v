`default_nettype none

module fir_core (
    input  wire [7:0] x0,
    input  wire [7:0] x1,
    input  wire [7:0] x2,
    input  wire [7:0] x3,
    output wire [7:0] y
);

    // extend width to prevent overflow
    wire [9:0] sum;

    // parallel addition (this is the accelerator!)
    assign sum = x0 + x1 + x2 + x3;

    // divide by 4 (low-pass filtering)
    assign y = sum[9:2];

endmodule