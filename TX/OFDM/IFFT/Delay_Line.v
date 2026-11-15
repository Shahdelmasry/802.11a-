
module Delay_Line #(
    parameter DATA_WIDTH = 16,
    parameter DELAY      = 32
)
(
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         en,
    input  wire signed [DATA_WIDTH-1:0] data_in,
    output wire signed [DATA_WIDTH-1:0] data_out
);

    reg signed [DATA_WIDTH-1:0] delay_reg [0:DELAY-1];

    integer i;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < DELAY; i = i + 1)
                delay_reg[i] <= {DATA_WIDTH{1'b0}};
        end
        else if (en) begin
            delay_reg[0] <= data_in;

            for (i = 1; i < DELAY; i = i + 1)
                delay_reg[i] <= delay_reg[i-1];
        end
    end

    assign data_out = delay_reg[DELAY-1];

endmodule
