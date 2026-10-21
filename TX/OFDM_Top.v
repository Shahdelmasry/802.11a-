
module OFDM_Top (
    input              clk,
    input              rst,

    // Mapper interface
    input      [31:0]  mapper_data,
    input              mapper_valid,
    output             mapper_ready,

    // IFFT input interface
    output     [31:0]  ifft_in_data,
    output             ifft_in_valid,
    input              ifft_in_ready
);

    wire signed [1:0] pilot_polarity;
    wire              sym_advance;

    Pilot_Gen dut1 (
        .clk         (clk),
        .rst         (rst),
        .sym_advance (sym_advance),
        .pilot_out   (pilot_polarity)
    );

    Pilot_Insertion dut2 (
        .clk          (clk),
        .rst          (rst),

        .in_data      (mapper_data),
        .in_valid     (mapper_valid),
        .in_ready     (mapper_ready),

        .pilot_in     (pilot_polarity),
        .sym_advance  (sym_advance),

        .out_data     (ifft_in_data),
        .out_valid    (ifft_in_valid),
        .out_ready    (ifft_in_ready)
    );

endmodule
