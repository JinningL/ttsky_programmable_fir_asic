`default_nettype none

module delay_line (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] sample_in,

    output wire [7:0] x0,   // x[n]
    output wire [7:0] x1,   // x[n-1]
    output wire [7:0] x2,   // x[n-2]
    output wire [7:0] x3    // x[n-3]
);

    // 4-stage shift register
    reg [7:0] d0, d1, d2, d3;

    // shift on every clock
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            d0 <= 0;
            d1 <= 0;
            d2 <= 0;
            d3 <= 0;
        end else begin
            d3 <= d2;
            d2 <= d1;
            d1 <= d0;
            d0 <= sample_in;
        end
    end

    assign x0 = d0;
    assign x1 = d1;
    assign x2 = d2;
    assign x3 = d3;

endmodule