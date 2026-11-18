// mode_register.v  -  "Mode Register"
// Holds one 2-bit modulation-mode code PER BANK (ping-pong) and decodes it into
// the parameters the rest of the Interleaver needs:
//   code 00 BPSK  : R= 3, N_BPSC=1, s=1
//   code 01 QPSK  : R= 6, N_BPSC=2, s=1
//   code 10 16-QAM: R=12, N_BPSC=4, s=2
//   code 11 64-QAM: R=18, N_BPSC=6, s=3
// R = N_CBPS/16 = number of 16-bit rows of the block.   s = max(N_BPSC/2,1).
//------------------------------------------------------------------------------
module mode_register (                                         // begin module declaration
    input  wire       clk,                                     // 80 MHz master clock
    input  wire       rst_n,                                   // active-low synchronous reset
    input  wire [1:0] mode_in,                                 // mode requested by upstream together with start
    input  wire       mode_load,                               // one-cycle pulse from Main FSM: latch mode_in
    input  wire       wr_bank,                                 // bank currently owned by the write side
    input  wire       rd_bank,                                 // bank currently owned by the read side
    output wire [4:0] wr_rows,                                 // R of the write-side bank (rows to write)
    output wire [1:0] mode_rd,                                 // raw mode code of the read-side bank
    output wire [4:0] R,                                       // R of the read-side bank (row counter wrap)
    output wire [2:0] N_BPSC,                                  // coded bits per subcarrier of the read-side bank
    output wire [1:0] s                                        // second-permutation group size of the read-side bank
);                                                             // end of port list
    reg  [1:0] mode_bank0;                                     // mode code latched for bank 0
    reg  [1:0] mode_bank1;                                     // mode code latched for bank 1
    wire [1:0] mode_wr;                                        // mode code of the bank owned by the write side

    function [4:0] rows_of;                                    // decode mode code -> R (rows)
        input [1:0] m;                                         // function argument: mode code
        begin                                                  // function body start
            case (m)                                           // select on the mode code
                2'b00:   rows_of = 5'd3;                       // BPSK   -> 3 rows  (48 bits)
                2'b01:   rows_of = 5'd6;                       // QPSK   -> 6 rows  (96 bits)
                2'b10:   rows_of = 5'd12;                      // 16-QAM -> 12 rows (192 bits)
                default: rows_of = 5'd18;                      // 64-QAM -> 18 rows (288 bits)
            endcase                                            // end of case
        end                                                    // function body end
    endfunction                                                // end of rows_of

    function [2:0] nbpsc_of;                                   // decode mode code -> N_BPSC
        input [1:0] m;                                         // function argument: mode code
        begin                                                  // function body start
            case (m)                                           // select on the mode code
                2'b00:   nbpsc_of = 3'd1;                      // BPSK   : 1 bit per symbol
                2'b01:   nbpsc_of = 3'd2;                      // QPSK   : 2 bits per symbol
                2'b10:   nbpsc_of = 3'd4;                      // 16-QAM : 4 bits per symbol
                default: nbpsc_of = 3'd6;                      // 64-QAM : 6 bits per symbol
            endcase                                            // end of case
        end                                                    // function body end
    endfunction                                                // end of nbpsc_of

    function [1:0] s_of;                                       // decode mode code -> s = max(N_BPSC/2,1)
        input [1:0] m;                                         // function argument: mode code
        begin                                                  // function body start
            case (m)                                           // select on the mode code
                2'b00:   s_of = 2'd1;                          // BPSK   : s = 1
                2'b01:   s_of = 2'd1;                          // QPSK   : s = 1
                2'b10:   s_of = 2'd2;                          // 16-QAM : s = 2
                default: s_of = 2'd3;                          // 64-QAM : s = 3
            endcase                                            // end of case
        end                                                    // function body end
    endfunction                                                // end of s_of

    assign mode_wr = wr_bank ? mode_bank1 : mode_bank0;        // pick the write-side bank's mode code
    assign mode_rd = rd_bank ? mode_bank1 : mode_bank0;        // pick the read-side bank's mode code
    assign wr_rows = rows_of(mode_wr);                         // rows the write side must collect
    assign R       = rows_of(mode_rd);                         // rows used by the read side
    assign N_BPSC  = nbpsc_of(mode_rd);                        // bits per symbol used by the read side
    assign s       = s_of(mode_rd);                            // s used by the second permutation

    always @(posedge clk) begin                                // clocked process: the two mode latches
        if (!rst_n) begin                                      // synchronous reset asserted
            mode_bank0 <= 2'b00;                               // bank 0 defaults to BPSK
            mode_bank1 <= 2'b00;                               // bank 1 defaults to BPSK
        end else if (mode_load) begin                          // Main FSM accepted a new block
            if (wr_bank) mode_bank1 <= mode_in;                // write-side bank is 1: latch into bank 1
            else         mode_bank0 <= mode_in;                // write-side bank is 0: latch into bank 0
        end                                                    // otherwise both latches hold their value
    end                                                        // end of clocked process
endmodule                                                      // end of mode_register
