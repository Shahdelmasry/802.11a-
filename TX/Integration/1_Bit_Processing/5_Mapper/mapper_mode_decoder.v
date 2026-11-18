// mapper_mode_decoder.v - "Mapper Mode Decoder"
// Turns the 2-bit mode code (sym_mode, travelling with the data) into the
// control signals of the Mapper datapath:
//   code 00 BPSK  : bits_per_axis=1, Q_en=0
//   code 01 QPSK  : bits_per_axis=1, Q_en=1
//   code 10 16-QAM: bits_per_axis=2, Q_en=1
//   code 11 64-QAM: bits_per_axis=3, Q_en=1
// LUT_SEL is the mode code itself (selects the amplitude table incl. K_MOD).
//------------------------------------------------------------------------------
module mapper_mode_decoder (                                   // begin module declaration
    input  wire [1:0] sym_mode,                                // mode code that belongs to the symbol
    output reg  [1:0] bits_per_axis,                           // bits that form the I (and the Q) axis value
    output wire       Q_en,                                    // 1: Q axis used, 0: Q forced to zero (BPSK)
    output wire [1:0] LUT_SEL                                  // amplitude-table select
);                                                             // end of port list
    assign LUT_SEL = sym_mode;                                 // table select equals the mode code
    assign Q_en    = (sym_mode != 2'b00);                      // every mode except BPSK uses the Q axis

    always @(*) begin                                          // combinational decode
        case (sym_mode)                                        // choose on the mode code
            2'b00:   bits_per_axis = 2'd1;                     // BPSK   : 1 bit on I
            2'b01:   bits_per_axis = 2'd1;                     // QPSK   : 1 bit on I, 1 bit on Q
            2'b10:   bits_per_axis = 2'd2;                     // 16-QAM : 2 bits per axis
            default: bits_per_axis = 2'd3;                     // 64-QAM : 3 bits per axis
        endcase                                                // end of case
    end                                                        // end of combinational block
endmodule                                                      // end of mapper_mode_decoder
