// axis_separator.v - "Axis Separator"
// Splits sym_bits (b0 = first bit = sym_bits[0]) into the I-axis and Q-axis
// groups exactly as IEEE 802.11a Table 81-83 assigns them:
//   BPSK   : I = b0
//   QPSK   : I = b0,      Q = b1
//   16-QAM : I = b0 b1,   Q = b2 b3
//   64-QAM : I = b0 b1 b2, Q = b3 b4 b5
// Outputs are right-aligned: bit (bits_per_axis-1) holds the FIRST bit of the
// group (the sign bit of the Gray code), bit 0 holds the last bit.
// For BPSK the Q group is don't-care (Q is forced to 0 later by Q_en).
//------------------------------------------------------------------------------
module axis_separator (                                        // begin module declaration
    input  wire [5:0] sym_bits,                                // one symbol from the Interleaver
    input  wire [1:0] bits_per_axis,                           // 1, 2 or 3 bits per axis
    output reg  [2:0] I_bits,                                  // right-aligned bits of the I axis
    output reg  [2:0] Q_bits                                   // right-aligned bits of the Q axis
);                                                             // end of port list
    always @(*) begin                                          // combinational split
        case (bits_per_axis)                                   // choose on the group size
            2'd1: begin                                        // BPSK / QPSK
                I_bits = {2'b00, sym_bits[0]};                 // I = b0
                Q_bits = {2'b00, sym_bits[1]};                 // Q = b1 (ignored for BPSK)
            end                                                // end of 1-bit case
            2'd2: begin                                        // 16-QAM
                I_bits = {1'b0, sym_bits[0], sym_bits[1]};     // I = b0 (MSB) b1
                Q_bits = {1'b0, sym_bits[2], sym_bits[3]};     // Q = b2 (MSB) b3
            end                                                // end of 2-bit case
            default: begin                                     // 64-QAM
                I_bits = {sym_bits[0], sym_bits[1], sym_bits[2]}; // I = b0 (MSB) b1 b2
                Q_bits = {sym_bits[3], sym_bits[4], sym_bits[5]}; // Q = b3 (MSB) b4 b5
            end                                                // end of 3-bit case
        endcase                                                // end of case
    end                                                        // end of combinational block
endmodule                                                      // end of axis_separator
