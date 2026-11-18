// mapper_top.v - IEEE 802.11a Mapper
// Blocks: Mapper Mode Decoder, Axis Separator, Shared Level Mapper
//         (I path + shared Amplitude LUT + Q path), Symbol Output.
// Input : sym_bits[5:0] (b0 first), sym_valid, sym_last, sym_mode
// Output: complex_symbol_out = {Q,I}, each W-bit two's complement Q2.(W-2)
//         (W=16: 1.0 = 16384), valid_out = sym_valid + 1 cycle, last_out.
//------------------------------------------------------------------------------
module mapper_top #(                                           // begin module declaration with parameter
    parameter W = 16                                           // width of I and Q
) (                                                            // begin port list
    input  wire           clk,                                 // 80 MHz master clock
    input  wire           rst_n,                               // active-low synchronous reset
    input  wire [5:0]     sym_bits,                            // one symbol, bits in final interleaved order
    input  wire           sym_valid,                           // sym_bits valid
    input  wire           sym_last,                            // sym_bits is symbol 47
    input  wire [1:0]     sym_mode,                            // mode of this symbol
    output wire [2*W-1:0] complex_symbol_out,                  // {Q, I}
    output wire           valid_out,                           // complex_symbol_out valid
    output wire           last_out                             // last symbol of the OFDM symbol
);                                                             // end of port list
    wire [1:0]   bits_per_axis;                                // bits per axis from the decoder
    wire         Q_en;                                         // Q axis enable from the decoder
    wire [1:0]   LUT_SEL;                                      // amplitude table select from the decoder
    wire [2:0]   I_bits, Q_bits;                               // axis bit groups
    wire [W-1:0] I, Q;                                         // signed axis values

    mapper_mode_decoder u_mapper_mode_decoder (                // Mapper Mode Decoder
        .sym_mode(sym_mode), .bits_per_axis(bits_per_axis),    // mode in, group size out
        .Q_en(Q_en), .LUT_SEL(LUT_SEL)                         // Q enable and table select out
    );                                                         // end of decoder

    axis_separator u_axis_separator (                          // Axis Separator
        .sym_bits(sym_bits), .bits_per_axis(bits_per_axis),    // symbol bits and group size in
        .I_bits(I_bits), .Q_bits(Q_bits)                       // axis groups out
    );                                                         // end of separator

    shared_level_mapper #(.W(W)) u_shared_level_mapper (       // Shared Level Mapper
        .I_bits(I_bits), .Q_bits(Q_bits),                      // axis groups in
        .bits_per_axis(bits_per_axis), .Q_en(Q_en), .LUT_SEL(LUT_SEL), // controls in
        .I(I), .Q(Q)                                           // signed values out
    );                                                         // end of level mapper

    symbol_output #(.W(W)) u_symbol_output (                   // Symbol Output
        .clk(clk), .rst_n(rst_n),                              // clock and reset
        .I(I), .Q(Q),                                          // values in
        .sym_valid(sym_valid), .sym_last(sym_last),            // strobes in
        .complex_symbol_out(complex_symbol_out),               // registered {Q,I} out
        .valid_out(valid_out), .last_out(last_out)             // registered strobes out
    );                                                         // end of output stage
endmodule                                                      // end of mapper_top
