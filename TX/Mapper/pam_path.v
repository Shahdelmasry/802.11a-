// pam_path.v - one axis path (used for I and for Q) of the Shared Level Mapper.
// Gray decoding per IEEE 802.11a (first bit = sign, 1 = positive):
//   1 bit : 0 -> -1, 1 -> +1
//   2 bits: 00 -> -3, 01 -> -1, 11 -> +1, 10 -> +3
//   3 bits: 000 -> -7, 001 -> -5, 011 -> -3, 010 -> -1,
//           110 -> +1, 111 -> +3, 101 -> +5, 100 -> +7
// Implemented as  sign + magnitude index (0->|1|,1->|3|,2->|5|,3->|7|) and the
// magnitude comes from the shared Amplitude LUT (amp, already times K_MOD).
//   level = sign ? +amp : -amp      (two's complement, W bits)
//------------------------------------------------------------------------------
module pam_path #(                                             // begin module declaration with parameter
    parameter W = 16                                           // width of the signed level
) (                                                            // begin port list
    input  wire [2:0]   bits,                                  // right-aligned Gray bits of this axis (MSB = first bit)
    input  wire [1:0]   bits_per_axis,                         // 1, 2 or 3 valid bits
    input  wire [W-1:0] amp,                                   // magnitude from the shared Amplitude LUT
    output reg  [1:0]   idx,                                   // magnitude index sent to the LUT
    output wire [W-1:0] level                                  // signed level in Q2.(W-2)
);                                                             // end of port list
    reg sign_pos;                                              // 1 = positive level

    always @(*) begin                                          // combinational Gray decode
        case (bits_per_axis)                                   // choose on the group size
            2'd1: begin                                        // 1 bit per axis
                sign_pos = bits[0];                            // the single bit is the sign
                idx      = 2'd0;                               // magnitude is always |1|
            end                                                // end of 1-bit case
            2'd2: begin                                        // 2 bits per axis
                sign_pos = bits[1];                            // first bit is the sign
                idx      = {1'b0, ~bits[0]};                   // second bit 1 -> |1| (idx 0), 0 -> |3| (idx 1)
            end                                                // end of 2-bit case
            default: begin                                     // 3 bits per axis
                sign_pos = bits[2];                            // first bit is the sign
                if (bits[1]) idx = {1'b0, bits[0]};            // b1b2 = 10 -> |1|, 11 -> |3|
                else         idx = {1'b1, ~bits[0]};           // b1b2 = 01 -> |5|, 00 -> |7|
            end                                                // end of 3-bit case
        endcase                                                // end of case
    end                                                        // end of combinational block

    assign level = sign_pos ? amp : ({W{1'b0}} - amp);         // apply the sign (two's complement negate)
endmodule                                                      // end of pam_path
