
module OFDM_TX_System_Top #(
    parameter DATA_WIDTH = 16
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // Master FSM controls
    input  wire [1:0]                   mux_sel,
    input  wire                         rom_rd_en,
    input  wire [8:0]                   rom_addr,
    output wire                         rom_ready,
    input  wire                         tx_start,
    input  wire                         ifft_mode,

    // External Mapper interface
    input  wire [31:0]                  mapper_data,
    input  wire                         mapper_valid,
    input  wire                         mapper_last,
    input  wire                         pkt_last,      // FSM: current symbol is the last of the packet

    // Pilot Insertion status for Master FSM
    output wire                         mapper_capture_ready,
    output wire                         tx_done,       // last sample of the packet's last symbol delivered

    // DAC interface
    output wire                         dac_clk,
    output wire [DATA_WIDTH-1:0]        dac_data_i,
    output wire [DATA_WIDTH-1:0]        dac_data_q
);

    // IFFT + CP stream to post-processing chain
    wire signed [DATA_WIDTH-1:0] ifft_stream_i;
    wire signed [DATA_WIDTH-1:0] ifft_stream_q;

    wire                         ifft_stream_valid;
    wire                         ifft_stream_ready;
    wire                         ifft_stream_last;
    wire [6:0]                   ifft_stream_index;

    // =====================================================
    // PILOT INSERTION + IFFT + PING-PONG BUFFER + CP
    // =====================================================

    FFT64_OFDM_Tx_Top #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_fft64_ofdm_tx (
        .clk                  (clk),
        .rst                  (rst_n),
        .start                (tx_start),
        .ifft_mode            (ifft_mode),

        .mapper_data          (mapper_data),
        .mapper_valid         (mapper_valid),
        .mapper_last          (mapper_last),
        .pkt_last             (pkt_last),
        .mapper_capture_ready (mapper_capture_ready),
        .tx_done              (tx_done),

        .out_valid            (ifft_stream_valid),
        .out_ready            (ifft_stream_ready),
        .out_last             (ifft_stream_last),
        .out_index            (ifft_stream_index),
        .I_out                (ifft_stream_i),
        .Q_out                (ifft_stream_q)
    );

    // =====================================================
    // PREAMBLE / IFFT MUX + UPSAMPLING + FIR + DAC
    // =====================================================

    pp_top #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_post_processing (
        .clk          (clk),
        .rst_n        (rst_n),

        .mux_sel      (mux_sel),
        .rom_rd_en    (rom_rd_en),
        .rom_addr     (rom_addr),
        .rom_ready    (rom_ready),

        .ifft_data_i  (ifft_stream_i),
        .ifft_data_q  (ifft_stream_q),
        .ifft_valid   (ifft_stream_valid),
        .ifft_last    (ifft_stream_last),
        .ifft_ready   (ifft_stream_ready),

        .dac_clk      (dac_clk),
        .dac_data_i   (dac_data_i),
        .dac_data_q   (dac_data_q)
    );

endmodule
