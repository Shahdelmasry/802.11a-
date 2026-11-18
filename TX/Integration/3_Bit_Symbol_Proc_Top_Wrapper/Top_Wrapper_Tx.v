// Top_Wrapper_Tx.v - Complete OFDM Transmitter Top Wrapper
// Integrates:
//   1. top_wrapper_bit_proc (Scrambler -> Encoder -> Adapter -> Interleaver -> Mapper)
//   2. OFDM_TX_System_Top   (Pilot Insertion -> IFFT -> CP -> Preamble Mux -> Upsampling -> FIR -> DAC)
//------------------------------------------------------------------------------
module Top_Wrapper_Tx #(
    parameter DATA_WIDTH = 16   // Width of I and Q (Q2.(DATA_WIDTH-2)); maps to W in bit_proc
) (
    input  wire                         clk,
    input  wire                         rst_n,

    // =========================================================================
    // Bit-Processing Control & Data Interface
    // =========================================================================
    input  wire                         tx_clear,       // Pulse: clear Encoder history (packet / SIGNAL / DATA start)
    input  wire                         il_start,       // Level: request Interleaver block, hold until in_ready = 1
    input  wire                         scr_enable,     // High for exactly W+2 cycles per OFDM symbol
    input  wire [6:0]                   scr_seed,       // Scrambler seed of current symbol
    input  wire                         scr_bypass,     // 1: SIGNAL field, Scrambler skipped
    input  wire [1:0]                   coding_rate,    // 0: 1/2, 1: 2/3, 2: 3/4 (3 is illegal)
    input  wire [1:0]                   modulation,     // 0: BPSK, 1: QPSK, 2: 16-QAM, 3: 64-QAM
    input  wire                         packet_end,
    input  wire                         seed_sel,

    input  wire [5:0]                   data_in,        // 6 data bits (bit 0 oldest), valid when data_req = 1
    input  wire [5:0]                   tail_mask,      // 1 = clear bit after scrambling (tail bits)

    output wire                         data_req,       // Data word consumed in current cycle
    output wire                         in_ready,       // Interleaver write window open
    output wire                         il_busy,        // Interleaver block in flight
    output wire                         cfg_err,        // Debug: illegal coding_rate / modulation pair

    // =========================================================================
    // OFDM Baseband & Post-Processing Control Interface
    // =========================================================================
    input  wire [1:0]                   mux_sel,
    input  wire                         rom_rd_en,
    input  wire [8:0]                   rom_addr,
    output wire                         rom_ready,
    input  wire                         tx_start,
    input  wire                         ifft_mode,
    input  wire                         pkt_last,       // Current symbol is the last of the packet

    output wire                         mapper_capture_ready,
    output wire                         tx_done,        // Last sample of the packet's last symbol delivered

    // =========================================================================
    // DAC Output Interface
    // =========================================================================
    //output wire                         dac_clk, Does Not Matter ??
    output wire [DATA_WIDTH-1:0]        dac_data_i,
    output wire [DATA_WIDTH-1:0]        dac_data_q
);

    // =========================================================================
    // Internal Interconnects: Bit-Processing Mapper -> OFDM TX System
    // =========================================================================
    wire [2*DATA_WIDTH-1:0] w_complex_symbol;
    wire                    w_mapper_valid;
    wire                    w_mapper_last;

    // =========================================================================
    // 1. Bit-Processing Chain
    // =========================================================================
    top_wrapper_bit_proc #(
        .W(DATA_WIDTH)
    ) u_bit_proc (
        .clk                (clk),
        .rst_n              (rst_n),

        .tx_clear           (tx_clear),
        .il_start           (il_start),
        .scr_enable         (scr_enable),
        .scr_seed           (scr_seed),
        .scr_bypass         (scr_bypass),
        .coding_rate        (coding_rate),
        .modulation         (modulation),
        .packet_end         (packet_end),
        .seed_sel           (seed_sel),

        .data_in            (data_in),
        .tail_mask          (tail_mask),

        .data_req           (data_req),
        .in_ready           (in_ready),
        .il_busy            (il_busy),
        .cfg_err            (cfg_err),

        .complex_symbol_out (w_complex_symbol),
        .valid_out          (w_mapper_valid),
        .last_out           (w_mapper_last)
    );

    // =========================================================================
    // 2. OFDM Modulation & Post-Processing Chain
    // =========================================================================
    OFDM_TX_System_Top #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_ofdm_tx_sys (
        .clk                  (clk),
        .rst_n                (rst_n),

        .mux_sel              (mux_sel),
        .rom_rd_en            (rom_rd_en),
        .rom_addr             (rom_addr),
        .rom_ready            (rom_ready),
        .tx_start             (tx_start),
        .ifft_mode            (ifft_mode),

        .mapper_data          (w_complex_symbol),
        .mapper_valid         (w_mapper_valid),
        .mapper_last          (w_mapper_last),
        .pkt_last             (pkt_last),

        .mapper_capture_ready (mapper_capture_ready),
        .tx_done              (tx_done),

        .dac_clk              (clk),
        .dac_data_i           (dac_data_i),
        .dac_data_q           (dac_data_q)
    );

endmodule