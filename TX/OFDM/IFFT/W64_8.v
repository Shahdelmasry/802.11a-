
module W64_8 #(
    parameter DATA_WIDTH = 16
)(
    input  wire signed [DATA_WIDTH-1:0] Iin,
    input  wire signed [DATA_WIDTH-1:0] Qin,

    output wire signed [DATA_WIDTH-1:0] Iout,
    output wire signed [DATA_WIDTH-1:0] Qout
);

    localparam EXT_WIDTH = DATA_WIDTH + 1;

    localparam signed [EXT_WIDTH-1:0] MAXV =
        {2'b00, {(DATA_WIDTH-1){1'b1}}};

    localparam signed [EXT_WIDTH-1:0] MINV =
        {2'b11, {(DATA_WIDTH-1){1'b0}}};

    wire signed [EXT_WIDTH-1:0] I_ext;
    wire signed [EXT_WIDTH-1:0] Q_ext;

    wire signed [EXT_WIDTH-1:0] sum_IQ;
    wire signed [EXT_WIDTH-1:0] diff_QI;

    wire signed [EXT_WIDTH-1:0] scaled_I;
    wire signed [EXT_WIDTH-1:0] scaled_Q;

    assign I_ext = {Iin[DATA_WIDTH-1], Iin};
    assign Q_ext = {Qin[DATA_WIDTH-1], Qin};

    // W64^8 = (1-j)/sqrt(2)
    // Iout = (I + Q)/sqrt(2)
    // Qout = (Q - I)/sqrt(2)

    assign sum_IQ = I_ext + Q_ext;
    assign diff_QI = Q_ext - I_ext;

    MUL_INV_SQRT2 #(
        .DATA_WIDTH(EXT_WIDTH)
    ) U_MUL_I (
        .data_in  (sum_IQ),
        .data_out (scaled_I)
    );

    MUL_INV_SQRT2 #(
        .DATA_WIDTH(EXT_WIDTH)
    ) U_MUL_Q (
        .data_in  (diff_QI),
        .data_out (scaled_Q)
    );

    assign Iout =
        (scaled_I > MAXV) ? {1'b0, {(DATA_WIDTH-1){1'b1}}} :
        (scaled_I < MINV) ? {1'b1, {(DATA_WIDTH-1){1'b0}}} :
                            scaled_I[DATA_WIDTH-1:0];

    assign Qout =
        (scaled_Q > MAXV) ? {1'b0, {(DATA_WIDTH-1){1'b1}}} :
        (scaled_Q < MINV) ? {1'b1, {(DATA_WIDTH-1){1'b0}}} :
                            scaled_Q[DATA_WIDTH-1:0];

endmodule
