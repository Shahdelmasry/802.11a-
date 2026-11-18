// amplitude_lut.v - the shared "Amplitude LUT" of the Shared Level Mapper.
// ONE table for all four modulations (selected by lut_sel) with two read ports,
// so the I path and the Q path share it.  Entry = |level| * K_MOD as an
// UNSIGNED magnitude in Q2.(W-2) fixed point (1.0 = 2^(W-2)):
//   BPSK   K=1        : idx0 = 1.0000
//   QPSK   K=1/sqrt2  : idx0 = 0.7071
//   16-QAM K=1/sqrt10 : idx0 = 1*K = 0.3162, idx1 = 3*K = 0.9487
//   64-QAM K=1/sqrt42 : idx0..3 = 1,3,5,7 *K = 0.1543,0.4629,0.7715,1.0801
// Constants below are Q2.14 (W=16) values = round(x * 16384).  For W<>16 they
// are shifted (left: exact, right: truncated).  W must be in 8..32.
//------------------------------------------------------------------------------
module amplitude_lut #(                                        // begin module declaration with parameter
    parameter W = 16                                           // width of I and Q (two's complement)
) (                                                            // begin port list
    input  wire [1:0]   lut_sel,                               // modulation select (mode code)
    input  wire [1:0]   idx_i,                                 // magnitude index of the I axis (0 -> |1|, 1 -> |3|, 2 -> |5|, 3 -> |7|)
    input  wire [1:0]   idx_q,                                 // magnitude index of the Q axis
    output wire [W-1:0] amp_i,                                 // amplitude for the I axis
    output wire [W-1:0] amp_q                                  // amplitude for the Q axis
);                                                             // end of port list
    localparam SHL = (W > 16) ? (W - 16) : 0;                  // left shift when W is wider than 16
    localparam SHR = (W < 16) ? (16 - W) : 0;                  // right shift when W is narrower than 16

    function [15:0] rom16;                                     // the table in Q2.14
        input [1:0] sel;                                       // modulation select
        input [1:0] idx;                                       // magnitude index
        begin                                                  // function body
            case ({sel, idx})                                  // address = {mode, index}
                4'b00_00: rom16 = 16'd16384;                   // BPSK   : 1
                4'b01_00: rom16 = 16'd11585;                   // QPSK   : 1/sqrt(2)
                4'b10_00: rom16 = 16'd5181;                    // 16-QAM : 1/sqrt(10)
                4'b10_01: rom16 = 16'd15543;                   // 16-QAM : 3/sqrt(10)
                4'b11_00: rom16 = 16'd2528;                    // 64-QAM : 1/sqrt(42)
                4'b11_01: rom16 = 16'd7584;                    // 64-QAM : 3/sqrt(42)
                4'b11_10: rom16 = 16'd12641;                   // 64-QAM : 5/sqrt(42)
                4'b11_11: rom16 = 16'd17697;                   // 64-QAM : 7/sqrt(42)
                default:  rom16 = 16'd0;                       // index not used by this modulation
            endcase                                            // end of case
        end                                                    // function body end
    endfunction                                                // end of rom16

    function [W-1:0] scale;                                    // convert Q2.14 to Q2.(W-2)
        input [15:0] c;                                        // Q2.14 constant
        reg   [31:0] t;                                        // wide temporary
        begin                                                  // function body
            t = ({16'd0, c} << SHL) >> SHR;                    // shift left or right depending on W
            scale = t[W-1:0];                                  // keep W bits
        end                                                    // function body end
    endfunction                                                // end of scale

    assign amp_i = scale(rom16(lut_sel, idx_i));               // read port 1 (I axis)
    assign amp_q = scale(rom16(lut_sel, idx_q));               // read port 2 (Q axis)
endmodule                                                      // end of amplitude_lut
