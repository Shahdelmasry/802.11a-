// shared_level_mapper.v - "Shared Level Mapper"
// I path + shared Amplitude LUT + Q path.  Purely combinational.
//   I = signed level of the I axis, Q = signed level of the Q axis (0 when Q_en=0)
// Number format: two's complement, W bits, Q2.(W-2) (W=16: 1.0 = 16384, range -2..+2).
//------------------------------------------------------------------------------
module shared_level_mapper #(                                  // begin module declaration with parameter
    parameter W = 16                                           // width of I and Q
) (                                                            // begin port list
    input  wire [2:0]   I_bits,                                // Gray bits of the I axis
    input  wire [2:0]   Q_bits,                                // Gray bits of the Q axis
    input  wire [1:0]   bits_per_axis,                         // 1, 2 or 3
    input  wire         Q_en,                                  // 0 forces Q to zero (BPSK)
    input  wire [1:0]   LUT_SEL,                               // amplitude table select
    output wire [W-1:0] I,                                     // signed I value
    output wire [W-1:0] Q                                      // signed Q value
);                                                             // end of port list
    wire [1:0]   idx_i, idx_q;                                 // magnitude indices of the two paths
    wire [W-1:0] amp_i, amp_q;                                 // magnitudes returned by the shared LUT
    wire [W-1:0] level_q;                                      // Q level before the Q_en gate

    pam_path #(.W(W)) u_i_path (                               // I path
        .bits(I_bits), .bits_per_axis(bits_per_axis),          // Gray bits and group size
        .amp(amp_i), .idx(idx_i), .level(I)                    // LUT amplitude in, index out, signed level out
    );                                                         // end of I path

    pam_path #(.W(W)) u_q_path (                               // Q path
        .bits(Q_bits), .bits_per_axis(bits_per_axis),          // Gray bits and group size
        .amp(amp_q), .idx(idx_q), .level(level_q)              // LUT amplitude in, index out, signed level out
    );                                                         // end of Q path

    amplitude_lut #(.W(W)) u_amplitude_lut (                   // the one shared table
        .lut_sel(LUT_SEL), .idx_i(idx_i), .idx_q(idx_q),       // select and the two indices
        .amp_i(amp_i), .amp_q(amp_q)                           // the two amplitudes
    );                                                         // end of LUT

    assign Q = Q_en ? level_q : {W{1'b0}};                     // BPSK: Q = 0
endmodule                                                      // end of shared_level_mapper
