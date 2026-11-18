
module Complex_Conjugate
#(
    parameter DATA_WIDTH = 16
)
(
    input  wire [2*DATA_WIDTH-1:0] data_in,
    output wire [2*DATA_WIDTH-1:0] data_out
);

    wire signed [DATA_WIDTH-1:0] I_in;
    wire signed [DATA_WIDTH-1:0] Q_in;

    wire signed [DATA_WIDTH-1:0] I_out;
    wire signed [DATA_WIDTH-1:0] Q_out;

    localparam signed [DATA_WIDTH-1:0] MIN_VALUE =
        {1'b1, {(DATA_WIDTH-1){1'b0}}};

    localparam signed [DATA_WIDTH-1:0] MAX_VALUE =
        {1'b0, {(DATA_WIDTH-1){1'b1}}};

    // Unpack complex input
    assign I_in = data_in[2*DATA_WIDTH-1:DATA_WIDTH];
    assign Q_in = data_in[DATA_WIDTH-1:0];

    // Real part remains unchanged
    assign I_out = I_in;

    // Imaginary part is negated
    // Saturation prevents overflow for minimum negative value
    assign Q_out = (Q_in == MIN_VALUE) ?
                   MAX_VALUE : -Q_in;

    // Pack complex output
    assign data_out = {I_out, Q_out};

endmodule
