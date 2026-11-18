// slot_counters.v  -  "Slot Counters" part of the Read Sequencer
// Enforces the project timing: one symbol slot = 6 clocks, 48 slots per block.
// Cycle 0 is the first cycle in which 'active' is high (first fetch cycle).
//   slot_cnt  0..5   : cycle inside the slot  (also q, the bit number)
//   sym_cnt   0..47  : symbol number inside the block
//   fetch_en         : active and slot_cnt < N_BPSC   (cycles 6m .. 6m+N_BPSC-1)
//   blk_done         : last cycle (slot 47, cycle 5 => cycle 287) of the block
//   sym_valid        : slot-end strobe delayed 2 cycles => cycle 6m+7
//   sym_last         : same delay, only for symbol 47
// 'go' decides at the last cycle whether the next block follows immediately.
//------------------------------------------------------------------------------
module slot_counters (                                         // begin module declaration
    input  wire       clk,                                     // 80 MHz master clock
    input  wire       rst_n,                                   // active-low synchronous reset
    input  wire       go,                                      // start (from idle) or continue (at last cycle) a block
    input  wire [2:0] N_BPSC,                                  // bits per symbol = fetch cycles per slot
    output wire [2:0] q,                                       // slot_cnt: bit number inside the symbol
    output wire       fetch_en,                                // fetch one bit this cycle
    output wire       blk_done,                                // last cycle of the block (combinational)
    output wire       sym_valid,                               // complete symbol presented this cycle
    output wire       sym_last,                                // that symbol is symbol 47
    output wire       pipe_busy                                // symbol strobes still travelling in the delay pipe
);                                                             // end of port list
    reg        active;                                         // block read in progress
    reg  [2:0] slot_cnt;                                       // cycle inside the 6-cycle slot
    reg  [5:0] sym_cnt;                                        // symbol index 0..47
    reg        sv1, sv2;                                       // 2-stage delay of the slot-end strobe
    reg        sl1, sl2;                                       // 2-stage delay of the last-symbol strobe
    wire       slot_end;                                       // last cycle of a slot
    wire       last_slot;                                      // last cycle of the last slot (end of block)

    assign q         = slot_cnt;                               // slot position is the bit number q
    assign fetch_en  = active & (slot_cnt < N_BPSC);           // fetch only during the first N_BPSC cycles of a slot
    assign slot_end  = active & (slot_cnt == 3'd5);            // 6th cycle of the slot
    assign last_slot = slot_end & (sym_cnt == 6'd47);          // 6th cycle of the 48th slot
    assign blk_done  = last_slot;                              // tells the Main FSM the bank can be released
    assign sym_valid = sv2;                                    // slot_end delayed by 2 => cycle 6m+7
    assign sym_last  = sl2;                                    // last-symbol strobe delayed by 2
    assign pipe_busy = sv1 | sv2;                              // a symbol strobe is still on its way out

    always @(posedge clk) begin                                // clocked process: counters and delay pipe
        if (!rst_n) begin                                      // synchronous reset asserted
            active   <= 1'b0;                                  // not reading
            slot_cnt <= 3'd0;                                  // slot position 0
            sym_cnt  <= 6'd0;                                  // symbol 0
            sv1      <= 1'b0;                                  // clear delay stage 1
            sv2      <= 1'b0;                                  // clear delay stage 2
            sl1      <= 1'b0;                                  // clear last-flag stage 1
            sl2      <= 1'b0;                                  // clear last-flag stage 2
        end else begin                                         // normal operation
            sv1 <= slot_end;                                   // stage 1 of the sym_valid pipe
            sv2 <= sv1;                                        // stage 2 of the sym_valid pipe
            sl1 <= last_slot;                                  // stage 1 of the sym_last pipe
            sl2 <= sl1;                                        // stage 2 of the sym_last pipe
            if (active) begin                                  // a block is being read
                if (slot_cnt == 3'd5) begin                    // end of the slot
                    slot_cnt <= 3'd0;                          // start next slot
                    if (sym_cnt == 6'd47) begin                // end of the block
                        sym_cnt <= 6'd0;                       // rewind symbol counter
                        active  <= go;                         // continue seamlessly only if Main FSM says so
                    end else begin                             // block continues
                        sym_cnt <= sym_cnt + 6'd1;             // next symbol
                    end                                        // end of sym_cnt==47 branch
                end else begin                                 // inside a slot
                    slot_cnt <= slot_cnt + 3'd1;               // next cycle of the slot
                end                                            // end of slot_cnt==5 branch
            end else if (go) begin                             // idle and a full bank is available
                active <= 1'b1;                                // next cycle is cycle 0 of the block
            end                                                // end of active branch
        end                                                    // end of reset/normal branch
    end                                                        // end of clocked process
endmodule                                                      // end of slot_counters
