
module PE2 #(
    parameter DATA_WIDTH = 16
)
(
    input  wire signed [DATA_WIDTH-1:0] Iin,
    input  wire signed [DATA_WIDTH-1:0] Qin,

    input  wire signed [DATA_WIDTH-1:0] DL_Iout,
    input  wire signed [DATA_WIDTH-1:0] DL_Qout,

    input  wire s0,
    input  wire s1,
    input  wire ifft_mode,

    output wire signed [DATA_WIDTH-1:0] Iout,
    output wire signed [DATA_WIDTH-1:0] Qout,

    output wire signed [DATA_WIDTH-1:0] DL_Iin,
    output wire signed [DATA_WIDTH-1:0] DL_Qin
);

    // PE3 outputs
    wire signed [DATA_WIDTH-1:0] Iout_PE3;
    wire signed [DATA_WIDTH-1:0] Qout_PE3;

    wire signed [DATA_WIDTH-1:0] DL_Iin_PE3;
    wire signed [DATA_WIDTH-1:0] DL_Qin_PE3;

    // Negation block
    wire signed [DATA_WIDTH-1:0]  neg_DL_Iin;

    // Instantiate PE3
    PE3 #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_PE3 (
        .Iin      (Iin),
        .Qin      (Qin),
        .DL_Iout  (DL_Iout),
        .DL_Qout  (DL_Qout),
        .s0       (s0),
        .ifft_mode(ifft_mode),

        .Iout     (Iout_PE3),
        .Qout     (Qout_PE3),
        .DL_Iin   (DL_Iin_PE3),
        .DL_Qin   (DL_Qin_PE3)
    );

    // Two's complement
    assign neg_DL_Iin = -DL_Iin_PE3;

    // PE2 output routing
    assign DL_Iin = s1 ? DL_Qin_PE3 : DL_Iin_PE3;
    assign DL_Qin = s1 ? neg_DL_Iin : DL_Qin_PE3;

    // PE3 outputs are PE2 outputs
    assign Iout = Iout_PE3;
    assign Qout = Qout_PE3;

endmodule
