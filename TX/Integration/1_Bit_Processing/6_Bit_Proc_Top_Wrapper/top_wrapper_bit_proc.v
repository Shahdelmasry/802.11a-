// top_wrapper.v - bit-processing chain:  Scrambler -> Convolutional Encoder -> enc_adapter -> Interleaver -> Mapper
//------------------------------------------------------------------------------
module top_wrapper_bit_proc #(                                 // begin module declaration with parameter
    parameter W = 16                                           // width of I and Q of the Mapper (Q2.(W-2)); 16 = updated configuration
) (                                                            // begin port list
    input  wire           clk,                                 // 80 MHz master clock
    input  wire           rst_n,                               // active-low reset (Interleaver/Mapper synchronous, Scrambler/Encoder asynchronous)
    
    input  wire           tx_clear,//from fsm at the start of each packet & signal field                             // pulse: clear the Encoder history (packet / SIGNAL / DATA field start)
    input  wire           il_start,                            // level: request an Interleaver block, hold until in_ready = 1
    input  wire           scr_enable,                          // high for exactly W+2 cycles per OFDM symbol
    input  wire [6:0]     scr_seed,                            // Scrambler seed of THIS symbol (sampled in E .. E+1)
    input  wire           scr_bypass,                          // 1: SIGNAL field, Scrambler skipped
    input  wire [1:0]     coding_rate,                         // 0: 1/2, 1: 2/3, 2: 3/4 (3 is illegal)
    input  wire [1:0]     modulation,                          // 0: BPSK, 1: QPSK, 2: 16-QAM, 3: 64-QAM
    input  wire           packet_end,
    input  wire           seed_sel, 
    
    input  wire [5:0]     data_in,                             // 6 data bits (bit 0 oldest), valid when data_req = 1
    input  wire [5:0]     tail_mask,                           // 1 = clear this bit after scrambling (tail bits), same cycle as data_in
    
    output wire           data_req,                            // a data word is consumed in THIS cycle (window E+2 .. E+W+1)
    output wire           in_ready,                            // Interleaver write window open (handshake of il_start)
    output wire           il_busy,                             // Interleaver: a block is in flight
    output wire           cfg_err,                             // debug: illegal coding_rate / modulation combination (combinational)
    
    output wire [2*W-1:0] complex_symbol_out,                  // {Q, I}
    output wire           valid_out,                           // complex_symbol_out valid
    output wire           last_out                             // 48th complex symbol of the OFDM symbol
);                                                             // end of port list
    wire [15:0] wc_data;                                       // Encoder word for the Write Controller
    wire [4:0]  wc_cnt;                                        // valid bits in wc_data
    wire        wc_valid;                                      // wc_data valid
    wire [5:0]  sym_bits;                                      // Interleaver -> Mapper
    wire        sym_valid, sym_last;                           // Interleaver -> Mapper strobes
    wire [1:0]  sym_mode;                                      // Interleaver -> Mapper mode

    // optional consistency check of the two configuration inputs (802.11a legal pairs); pure combinational, no effect on the datapath
    assign cfg_err = (coding_rate == 2'd3)                                   // code 3 does not exist
                   | ((coding_rate == 2'd1) & (modulation != 2'd3))          // 2/3 only exists with 64-QAM (48 Mbps)
                   | ((coding_rate == 2'd0) & (modulation == 2'd3));         // 64-QAM 1/2 does not exist

    tx_front_end u_front (                                     // Scrambler + tail clear + Encoder + enc_adapter
        .clk(clk), 
        .rst_n(rst_n), 
        .scr_enable(scr_enable), 
        .scr_bypass(scr_bypass), 
        .enc_clear(tx_clear), 
        .seed(scr_seed), // control and seed
        .packet_end(packet_end),
        .seed_sel(seed_sel),
        .data_req(data_req), 
        .data_in(data_in), 
        .tail_mask(tail_mask), 
        .enc_rate(coding_rate), // data
        .wc_data(wc_data), 
        .wc_cnt(wc_cnt), 
        .wc_valid(wc_valid) // to the Write Controller
    );                                                         // end of front end
    interleaver_top_cnt u_interleaver (                        // Interleaver half (Write Controller + early read inside)
        .clk(clk), 
        .rst_n(rst_n), 
        .data_in(wc_data), 
        .valid_in(wc_valid), 
        .in_cnt(wc_cnt), // coded bits and their count
        .start(il_start), 
        .mode_in(modulation), 
        .in_ready(in_ready), 
        .busy(il_busy), // control and status
        .sym_bits(sym_bits), 
        .sym_valid(sym_valid), 
        .sym_last(sym_last), 
        .sym_mode(sym_mode) // to the Mapper
    );                                                         // end of Interleaver
    mapper_top #(.W(W)) u_mapper (                             // Mapper half
        .clk(clk), 
        .rst_n(rst_n), 
        .sym_bits(sym_bits), 
        .sym_valid(sym_valid), 
        .sym_last(sym_last), 
        .sym_mode(sym_mode), // from the Interleaver
        .complex_symbol_out(complex_symbol_out), 
        .valid_out(valid_out), 
        .last_out(last_out) // to downstream
    );                                                         // end of Mapper
endmodule                                                      // end of top_wrapper
