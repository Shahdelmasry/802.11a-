module MUL_INV_SQRT2 #(
    parameter DATA_WIDTH = 16
)
(
    input  wire signed [DATA_WIDTH-1:0] data_in,
    output wire signed [DATA_WIDTH-1:0] data_out
);

    localparam EXT_WIDTH = DATA_WIDTH + 1;

    // Sign extension
    wire signed [EXT_WIDTH-1:0] x_ext;

    // Intermediate signals
    wire signed [EXT_WIDTH-1:0] t1;
    wire signed [EXT_WIDTH-1:0] t2;
    wire signed [EXT_WIDTH-1:0] t3;
    wire signed [EXT_WIDTH-1:0] result;

    assign x_ext = {data_in[DATA_WIDTH-1], data_in};

   
    // Y = X + (X + X/4)/64 - (X + X/4)/4
    assign t1 = x_ext + (x_ext >>> 2);

    assign t2 = t1 >>> 6;

    assign t3 = t1 >>> 2;

    assign result = x_ext + t2 - t3;

    assign data_out = result[DATA_WIDTH-1:0];

endmodule