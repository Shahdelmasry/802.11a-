module Top_Wrapper_Tx #(
    parameter DATA_WIDTH = 16   
) (
    input  wire                         clk,
    input  wire                         rst_n,

    // =========================================================================
    // Bit-Processing Control & Data Interface
    // =========================================================================
    input  wire                         tx_clear,       
    input  wire                         il_start,       
    input  wire                         scr_enable,     
    input  wire [6:0]                   scr_seed,       
    input  wire                         scr_bypass,     
    input  wire [1:0]                   coding_rate,    
    input  wire [1:0]                   modulation,     
    input  wire                         packet_end,
    input  wire                         seed_sel,
    input  wire [5:0]                   data_in,        
    input  wire [5:0]                   tail_mask,      
    output wire                         data_req,       
    output wire                         in_ready,       
    output wire                         il_busy,        
    output wire                         cfg_err,        

    // =========================================================================
    // OFDM Baseband & Post-Processing Control Interface
    // =========================================================================
    input  wire [1:0]                   mux_sel,
    input  wire                         rom_rd_en,
    input  wire [8:0]                   rom_addr,
    output wire                         rom_ready,
    input  wire                         tx_start,
    input  wire                         ifft_mode,
    input  wire                         pkt_last,       

    output wire                         mapper_capture_ready,
    output wire                         mapper_valid,   
    output wire                         mapper_last,    
    output wire                         tx_done,        

    // =========================================================================
    // DAC Output Interface
    // =========================================================================
    output wire [DATA_WIDTH-1:0]        dac_data_i,
    output wire [DATA_WIDTH-1:0]        dac_data_q
);

    // =========================================================================
    // Internal Interconnects: Bit-Processing Mapper -> OFDM TX System
    // =========================================================================
    wire [2*DATA_WIDTH-1:0] w_complex_symbol;
    wire                    w_mapper_valid;
    wire                    w_mapper_last;

    assign mapper_valid = w_mapper_valid;
    assign mapper_last  = w_mapper_last;

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
        .dac_clk              (),                 
        .dac_data_i           (dac_data_i),
        .dac_data_q           (dac_data_q)
    );

endmodule
