// symbol_assembler.v  -  "Symbol Assembler"
// Replaces the old 288-bit output buffer.  A 6-bit window collects the N_BPSC
// bits of one symbol; each bit is written to position win_idx (second
// permutation).  Bits are first registered (bit_reg) so that bit, win_idx and
// win_we are aligned.  The window is cleared by sym_valid, so unused upper bits
// are always 0.  sym_mode is latched with the data so that the last symbol of a
// block keeps ITS mode even though the read-side parameters switch one cycle
// before that symbol is consumed.
// Output timing: window is complete and stable in the sym_valid cycle (6m+7).
//------------------------------------------------------------------------------
module symbol_assembler (                                      // begin module declaration
    input  wire       clk,                                     // 80 MHz master clock
    input  wire       rst_n,                                   // active-low synchronous reset
    input  wire       read_bit,                                // bit from Matrix Memory (fetch cycle)
    input  wire [2:0] win_idx,                                 // window position (aligned with bit_reg)
    input  wire       win_we,                                  // window write strobe (aligned with bit_reg)
    input  wire       sym_valid_in,                            // window is complete this cycle (clear after it)
    input  wire [1:0] mode_rd,                                 // mode code of the read-side bank (fetch cycle)
    output wire [5:0] sym_bits,                                // assembled symbol, b0 = first bit
    output wire [1:0] sym_mode                                 // mode code that belongs to sym_bits
);                                                             // end of port list
    reg  [5:0] win;                                            // the symbol window register
    reg  [5:0] win_nxt;                                        // next value of the window (combinational)
    reg        bit_reg;                                        // registered memory bit
    reg  [1:0] mode_d;                                         // mode code delayed to match bit_reg
    reg  [1:0] sym_mode_r;                                     // mode code latched with the window data

    assign sym_bits = win;                                     // the window is presented directly
    assign sym_mode = sym_mode_r;                              // latched mode code is presented directly

    always @(*) begin                                          // combinational next-window logic
        win_nxt = win;                                         // default: hold
        if (sym_valid_in) win_nxt = 6'd0;                      // symbol consumed: clear for the next one
        if (win_we) win_nxt[win_idx] = bit_reg;                // write the bit (wins over the clear, same edge)
    end                                                        // end of combinational block

    always @(posedge clk) begin                                // clocked process
        if (!rst_n) begin                                      // synchronous reset asserted
            win        <= 6'd0;                                // empty window
            bit_reg    <= 1'b0;                                // clear bit register
            mode_d     <= 2'b00;                               // clear delayed mode
            sym_mode_r <= 2'b00;                               // clear latched mode
        end else begin                                         // normal operation
            bit_reg <= read_bit;                               // capture the memory bit
            mode_d  <= mode_rd;                                // delay mode by one cycle like the bit
            win     <= win_nxt;                                // update the window
            if (win_we) sym_mode_r <= mode_d;                  // latch mode of the bit being written
        end                                                    // end of reset/normal branch
    end                                                        // end of clocked process
endmodule                                                      // end of symbol_assembler
