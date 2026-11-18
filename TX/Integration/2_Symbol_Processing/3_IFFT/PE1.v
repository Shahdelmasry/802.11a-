
module PE1 #(
    parameter DATA_WIDTH = 16
)
(
    input wire signed [DATA_WIDTH-1:0] Iin,
    input wire signed [DATA_WIDTH-1:0] Qin,

    input wire signed [DATA_WIDTH-1:0] DL_Iout,
    input wire signed [DATA_WIDTH-1:0] DL_Qout,

    input wire s0,
    input wire s1,
    input wire s2,
    input wire ifft_mode,

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

    // W64_8 outputs
    wire signed [DATA_WIDTH-1:0] Iout_W64_8;
    wire signed [DATA_WIDTH-1:0] Qout_W64_8;

    // First MUX outputs
    wire signed [DATA_WIDTH-1:0] I_mux1;
    wire signed [DATA_WIDTH-1:0] Q_mux1;

    // Two's complement
    wire signed [DATA_WIDTH-1:0] neg_I_mux1;

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

    // Instantiate W64_8 using PE3 delay-line inputs
    W64_8 #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_W64_8 (
        .Iin  (DL_Iin_PE3),
        .Qin  (DL_Qin_PE3),
        .Iout (Iout_W64_8),
        .Qout (Qout_W64_8)
    );

    // First MUX: bypass or W64_8
    assign I_mux1 = s1 ? Iout_W64_8 : DL_Iin_PE3;
    assign Q_mux1 = s1 ? Qout_W64_8 : DL_Qin_PE3;

    // Two's complement
    assign neg_I_mux1 = -I_mux1;

    // Second MUX: direct or multiplication by -j
    assign DL_Iin = s2 ? Q_mux1 : I_mux1;
    assign DL_Qin = s2 ? neg_I_mux1 : Q_mux1;

    // PE3 outputs remain the external PE outputs
    assign Iout = Iout_PE3;
    assign Qout = Qout_PE3;

endmodule
