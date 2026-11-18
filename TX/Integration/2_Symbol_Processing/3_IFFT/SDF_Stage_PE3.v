
module SDF_Stage_PE3 #(
    parameter DATA_WIDTH = 16,
    parameter DELAY      = 8
)
(
    input wire clk,
    input wire rst,
    input wire sample_en,

    input wire signed [DATA_WIDTH-1:0] Iin,
    input wire signed [DATA_WIDTH-1:0] Qin,

    input wire s0,
    input wire ifft_mode,

    output wire signed [DATA_WIDTH-1:0] Iout,
    output wire signed [DATA_WIDTH-1:0] Qout
);

    wire signed [DATA_WIDTH-1:0] DL_Iin;
    wire signed [DATA_WIDTH-1:0] DL_Qin;

    wire signed [DATA_WIDTH-1:0] DL_Iout;
    wire signed [DATA_WIDTH-1:0] DL_Qout;

    // PE3
    PE3 #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_PE3 (
        .Iin      (Iin),
        .Qin      (Qin),

        .DL_Iout  (DL_Iout),
        .DL_Qout  (DL_Qout),

        .s0       (s0),
        .ifft_mode(ifft_mode),

        .Iout     (Iout),
        .Qout     (Qout),

        .DL_Iin   (DL_Iin),
        .DL_Qin   (DL_Qin)
    );

    // I Delay Line
    Delay_Line #(
        .DATA_WIDTH(DATA_WIDTH),
        .DELAY(DELAY)
    ) u_DL_I (
        .clk      (clk),
        .rst      (rst),
        .en       (sample_en),
        .data_in  (DL_Iin),
        .data_out (DL_Iout)
    );

    // Q Delay Line
    Delay_Line #(
        .DATA_WIDTH(DATA_WIDTH),
        .DELAY(DELAY)
    ) u_DL_Q (
        .clk      (clk),
        .rst      (rst),
        .en       (sample_en),
        .data_in  (DL_Qin),
        .data_out (DL_Qout)
    );

endmodule
