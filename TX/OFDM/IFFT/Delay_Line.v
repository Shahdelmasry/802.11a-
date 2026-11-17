module Delay_Line #(
    parameter DATA_WIDTH = 16,
    parameter DELAY      = 32
)
(
    input  wire                         clk,
    input  wire                         rst,      // kept for interface compatibility; storage is not reset
    input  wire                         en,
    input  wire signed [DATA_WIDTH-1:0] data_in,
    output wire signed [DATA_WIDTH-1:0] data_out
);

    // The storage has no reset so that synthesis can map it to shift-register
    reg signed [DATA_WIDTH-1:0] delay_reg [0:DELAY-1];

    integer i;

    always @(posedge clk) begin
        if (en) begin
            delay_reg[0] <= data_in;

            for (i = 1; i < DELAY; i = i + 1)
                delay_reg[i] <= delay_reg[i-1];
        end
    end

    assign data_out = delay_reg[DELAY-1];

endmodule
