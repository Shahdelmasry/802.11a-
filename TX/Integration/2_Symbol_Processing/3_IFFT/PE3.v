module PE3 #(
    parameter DATA_WIDTH = 16
)
(
    input  wire signed [DATA_WIDTH-1:0] Iin,
    input  wire signed [DATA_WIDTH-1:0] Qin,
    input  wire signed [DATA_WIDTH-1:0] DL_Iout,
    input  wire signed [DATA_WIDTH-1:0] DL_Qout,
    input  wire                         s0,
    input  wire                         ifft_mode,

    output wire signed [DATA_WIDTH-1:0] Iout,
    output wire signed [DATA_WIDTH-1:0] Qout,
    output wire signed [DATA_WIDTH-1:0] DL_Iin,
    output wire signed [DATA_WIDTH-1:0] DL_Qin
);

    // Extend operands BEFORE arithmetic to preserve the carry/sign bit.
    localparam EXT_WIDTH = DATA_WIDTH + 1;

    wire signed [EXT_WIDTH-1:0] Iin_ext;
    wire signed [EXT_WIDTH-1:0] Qin_ext;
    wire signed [EXT_WIDTH-1:0] DL_Iout_ext;
    wire signed [EXT_WIDTH-1:0] DL_Qout_ext;

    wire signed [EXT_WIDTH-1:0] sum_I_ext;
    wire signed [EXT_WIDTH-1:0] diff_I_ext;
    wire signed [EXT_WIDTH-1:0] sum_Q_ext;
    wire signed [EXT_WIDTH-1:0] diff_Q_ext;

    wire signed [EXT_WIDTH-1:0] sum_I_scaled;
    wire signed [EXT_WIDTH-1:0] diff_I_scaled;
    wire signed [EXT_WIDTH-1:0] sum_Q_scaled;
    wire signed [EXT_WIDTH-1:0] diff_Q_scaled;

    wire signed [DATA_WIDTH-1:0] sum_I_result;
    wire signed [DATA_WIDTH-1:0] diff_I_result;
    wire signed [DATA_WIDTH-1:0] sum_Q_result;
    wire signed [DATA_WIDTH-1:0] diff_Q_result;

    assign Iin_ext     = {Iin[DATA_WIDTH-1], Iin};
    assign Qin_ext     = {Qin[DATA_WIDTH-1], Qin};
    assign DL_Iout_ext = {DL_Iout[DATA_WIDTH-1], DL_Iout};
    assign DL_Qout_ext = {DL_Qout[DATA_WIDTH-1], DL_Qout};

    // PE3 radix-2 butterfly arithmetic.
    assign sum_I_ext  = Iin_ext + DL_Iout_ext;
    assign diff_I_ext = DL_Iout_ext - Iin_ext;
    assign sum_Q_ext  = DL_Qout_ext + Qin_ext;
    assign diff_Q_ext = DL_Qout_ext - Qin_ext;

    // IFFT normalization: divide each active butterfly result by two.
    // FFT mode retains the original DATA_WIDTH wrap/truncation behavior.
    assign sum_I_scaled  = ifft_mode ? (sum_I_ext  >>> 1) : sum_I_ext;
    assign diff_I_scaled = ifft_mode ? (diff_I_ext >>> 1) : diff_I_ext;
    assign sum_Q_scaled  = ifft_mode ? (sum_Q_ext  >>> 1) : sum_Q_ext;
    assign diff_Q_scaled = ifft_mode ? (diff_Q_ext >>> 1) : diff_Q_ext;

    assign sum_I_result  = sum_I_scaled[DATA_WIDTH-1:0];
    assign diff_I_result = diff_I_scaled[DATA_WIDTH-1:0];
    assign sum_Q_result  = sum_Q_scaled[DATA_WIDTH-1:0];
    assign diff_Q_result = diff_Q_scaled[DATA_WIDTH-1:0];

    // Preserve the original SDF routing. Bypass paths are NOT scaled.
    assign DL_Iin = s0 ? diff_I_result : Iin;
    assign Iout   = s0 ? sum_I_result  : DL_Iout;
    assign DL_Qin = s0 ? diff_Q_result : Qin;
    assign Qout   = s0 ? sum_Q_result  : DL_Qout;

endmodule
