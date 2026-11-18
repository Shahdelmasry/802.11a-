// tx_front_end.v - Scrambler -> tail zeroing -> Convolutional Encoder -> rate-select adapter.
// The Scrambler and the Encoder are instantiated UNCHANGED (their ports are used exactly as documented).
//   normal path : data_in -> Scrambler -> (clear tail bits) -> Encoder          (Encoder enable = Scrambler out_valid)
//   bypass path : data_in -> 1 register -> Encoder   (SIGNAL field: not scrambled; same 1-cycle latency)
// The Encoder history register is cleared only by `rst_n`, and the pad bits after the tail leave it non-zero, so the
// external MAC pulses enc_clear (top_wrapper port tx_clear) at every packet start (a packet always starts from the all-zero encoder state).
// Output: wc_data / wc_cnt / wc_valid for the Write Controller (12, 9 or 8 valid bits per cycle).
//------------------------------------------------------------------------------
module tx_front_end (                                          // begin module declaration
    input  wire        clk,                                    // 80 MHz master clock
    input  wire        rst_n,                                  // active-low reset (the blocks use it as asynchronous `rst`)
    input  wire        scr_enable,                             // Scrambler enable from the external MAC (W+2 cycles per symbol)
    input  wire        scr_bypass,                             // 1: SIGNAL field, skip the Scrambler
    input  wire        enc_clear,                              // pulse at a packet start: clear the Encoder history (its only reset is rst)
    input  wire [6:0]  seed,                                   // Scrambler seed of the current symbol
    input  wire [5:0]  data_in,                                // 6 data bits (bit 0 oldest)
    input  wire [5:0]  tail_mask,                              // 1 = clear this bit after scrambling (the six tail bits), same cycle as data_in
    input  wire [1:0]  enc_rate,                               // Encoder rate code of the packet (0: 1/2, 1: 2/3, 2: 3/4)
    input  wire        packet_end,
    input  wire        seed_sel,                               // 0 = use the external seed , 1 = use the internal seed generator
    output wire        data_req,                               // a word must be on data_in in THIS cycle (derived from scr_enable, see below)
    output wire [15:0] wc_data,                                // to Write Controller data_in
    output wire [4:0]  wc_cnt,                                 // to Write Controller in_cnt
    output wire        wc_valid                                // to Write Controller valid_in
);    
    wire [6:0]  seed_used;// we can remove it later                                                       
    wire [5:0]  scr_out;                                       // scrambled word
    wire        scr_valid;                                     // scrambled word valid
    wire [5:0]  enc_in;                                        // word entering the Encoder
    wire        enc_en;                                        // Encoder enable
    wire [11:0] e_d12;                                         // Encoder bus 1/2
    wire [8:0]  e_d23;                                         // Encoder bus 2/3
    wire [7:0]  e_d34;                                         // Encoder bus 3/4
    reg  [5:0]  data_d1, mask_d1;                              // data and tail mask delayed by one cycle (align with the Scrambler output)
    reg         req_d1;                                        // data_req delayed by one cycle
    reg  [1:0]  rate_d1;                                       // Encoder rate delayed by one cycle (align with the registered Encoder outputs)
    reg         en_d1, en_d2;                              // scr_enable delayed by one and two cycles (Scrambler word window)
    reg         clr_q;                                         // registered clear pulse (glitch-free source of the asynchronous Encoder reset)
    wire        enc_rst_n = rst_n & ~clr_q;                    // Encoder reset: global reset or packet-start clear

    // The Scrambler consumes word 0 two cycles after its enable rises (IDLE -> lut -> scrambling), so the word window is
    // data_req = scr_enable AND scr_enable(2 cycles ago) = cycles E+2 .. E+W+1.  Knowledge of this Scrambler latency stays local.
    assign data_req = scr_enable & en_d2;                      // word window of the Scrambler
    always @(posedge clk ) begin                                // alignment registers
        data_d1 <= data_in;                                    // word, for the bypass path
        mask_d1 <= tail_mask;                                  // tail mask, for the normal path
        req_d1  <= data_req;                                   // valid, for the bypass path
        rate_d1 <= enc_rate;                                   // rate for the output multiplexer
        en_d1   <= rst_n & scr_enable;                         // one cycle old enable
        en_d2   <= rst_n & en_d1;                              // two cycles old enable
        clr_q   <= enc_clear;                                  // one cycle later: asserts the Encoder reset for one cycle
    end                                                        // end of alignment registers

    scrambler #(.DATA_LENGTH(6)) u_scrambler (                 // the user's Scrambler, unchanged
        .clk(clk), 
        .rst_n(rst_n),                                // clock and (asynchronous, active-low) reset
        .enable(scr_enable & ~scr_bypass), 
        .seed(seed),        // enable (held off in bypass) and seed
        .data_in(data_in),
        .packet_end(packet_end), 
        .seed_sel(seed_sel),
        .out_valid(scr_valid), 
        .data_out(scr_out), // data and result
        .seed_used(seed_used)
    );                                                         // end of Scrambler

    assign enc_in = scr_bypass ? data_d1 : (scr_out & ~mask_d1); // SIGNAL: raw word; DATA: scrambled word with tail bits cleared
    assign enc_en = scr_bypass ? req_d1  : scr_valid;          // Encoder enable follows the valid word, not the whole packet

    convolution_encoder #(.DATA_WIDTH(6)) u_encoder (          // the user's Encoder, unchanged
        .clk(clk), 
        .rst_n(enc_rst_n),                            // clock and (asynchronous, active-low) reset incl. packet-start clear
        .enable(enc_en), 
        .data_in(enc_in), 
        .rate(enc_rate),    // enable, data and rate code
        .data_out(e_d12), 
        .data_out_23(e_d23), 
        .data_out_34(e_d34), 
        .out_valid(wc_valid) // the three buses and the valid
    );                                                         // end of Encoder

    enc_adapter u_adapter (                                // rate-select adapter
        .rate_sel(rate_d1), 
        .data_out(e_d12), 
        .data_out_23(e_d23), 
        .data_out_34(e_d34), // aligned select and buses
        .wc_data(wc_data), 
        .wc_cnt(wc_cnt)                     // to the Write Controller
    );                                                         // end of adapter
endmodule                                                      // end of tx_front_end
