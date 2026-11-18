// second_perm.v  -  "Second Perm" part of the Read Sequencer
// Standard second permutation (forward direction, scatter into the window):
//   j = s*floor(i/s) + (i + N_CBPS - floor(16*i/N_CBPS)) mod s
// With i = m*N_BPSC + q, floor(16*i/N_CBPS) = col and N_CBPS mod s = 0 the
// position INSIDE the N_BPSC-bit symbol is
//   w = s*floor(q/s) + ((q - col) mod s)
// (q = bit number inside the symbol, col = read column).  w is combinational;
// win_idx and win_we are then registered ONE cycle so that they line up with
// the registered bit in the Symbol Assembler (bit_reg).
//------------------------------------------------------------------------------
module second_perm (                                           // begin module declaration
    input  wire       clk,                                     // 80 MHz master clock
    input  wire       rst_n,                                   // active-low synchronous reset
    input  wire       fetch_en,                                // a bit is being fetched this cycle
    input  wire [2:0] q,                                       // bit number inside the symbol (slot counter)
    input  wire [3:0] col,                                     // column of the bit being fetched
    input  wire [1:0] s,                                       // group size s of the current mode (1/2/3)
    output reg  [2:0] win_idx,                                 // window position of that bit (one cycle later)
    output reg        win_we                                   // window write strobe (one cycle later)
);                                                             // end of port list
    reg  [2:0] w;                                              // combinational window position
    reg  [2:0] base;                                           // s*floor(q/s)
    reg  [2:0] qm;                                             // q mod s
    reg  [3:0] cm4;                                            // col mod 3 (wide enough for the % operator)
    reg  [2:0] cm;                                             // col mod s
    reg  [2:0] rr;                                             // (q - col) mod s

    always @(*) begin                                          // combinational permutation logic
        base = 3'd0;                                           // default: group base 0
        qm   = 3'd0;                                           // default: q mod s = 0
        cm4  = col % 4'd3;                                     // col mod 3 (only used when s == 3)
        cm   = 3'd0;                                           // default: col mod s = 0
        rr   = 3'd0;                                           // default: no rotation
        case (s)                                               // choose the group size
            2'd2: begin                                        // s = 2 (16-QAM)
                base = {q[2:1], 1'b0};                         // 2*floor(q/2)
                qm   = {2'b00, q[0]};                          // q mod 2
                cm   = {2'b00, col[0]};                        // col mod 2
            end                                                // end of s = 2
            2'd3: begin                                        // s = 3 (64-QAM)
                base = (q >= 3'd3) ? 3'd3 : 3'd0;              // 3*floor(q/3), q in 0..5
                qm   = (q >= 3'd3) ? (q - 3'd3) : q;          // q mod 3
                cm   = cm4[2:0];                               // col mod 3
            end                                                // end of s = 3
            default: begin                                     // s = 1 (BPSK/QPSK): identity
                base = q;                                      // floor(q/1)*1 = q
                qm   = 3'd0;                                   // q mod 1 = 0
                cm   = 3'd0;                                   // col mod 1 = 0
            end                                                // end of default
        endcase                                                // end of case on s
        if (qm >= cm) rr = qm - cm;                            // (q - col) mod s without wrap
        else          rr = qm + {1'b0, s} - cm;                // wrap: add s once (qm < cm <= s-1)
        w = base + rr;                                         // final window position inside the symbol
    end                                                        // end of combinational block

    always @(posedge clk) begin                                // clocked process: align outputs with bit_reg
        if (!rst_n) begin                                      // synchronous reset asserted
            win_idx <= 3'd0;                                   // clear index
            win_we  <= 1'b0;                                   // no write pending
        end else begin                                         // normal operation
            win_idx <= w;                                      // register the window position
            win_we  <= fetch_en;                               // write strobe follows the fetch by one cycle
        end                                                    // end of reset/normal branch
    end                                                        // end of clocked process
endmodule                                                      // end of second_perm
