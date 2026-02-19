`default_nettype none

module tt_um_fir_filter (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // Internal wires between modules
    wire [7:0] x0, x1, x2, x3;
    wire [7:0] y;

    // -----------------------
    // Delay Line
    // -----------------------
    delay_line delay_inst (
        .clk(clk),
        .rst_n(rst_n),
        .din(ui_in),
        .x0(x0),
        .x1(x1),
        .x2(x2),
        .x3(x3)
    );

    // -----------------------
    // FIR Core
    // -----------------------
    fir_core fir_inst (
        .x0(x0),
        .x1(x1),
        .x2(x2),
        .x3(x3),
        .y(y)
    );

    // -----------------------
    // Outputs
    // -----------------------
    assign uo_out = y;

    // We don't use bidirectional pins
    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;

    // prevent warnings
    wire _unused = &{ena, uio_in, 1'b0};

endmodule