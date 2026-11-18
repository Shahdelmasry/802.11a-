// main_fsm.v  -  "Main FSM"
// Ping-pong control.  The diagram shows states IDLE/WRITE/READ plus wr_bank,
// rd_bank and bank_full[1:0].  Because the write side and the read side work at
// the same time (different banks), the FSM is realised as two coupled state
// bits:   write side : IDLE (wr_run=0) / WRITE (wr_run=1)
//         read  side : IDLE (rd_active=0) / READ (rd_active=1)
// Protocol:
//   start (level)  : request to begin a block.  Accepted in the cycle where
//                    the write side is IDLE and the write bank is free; that
//                    cycle mode_load=1 latches mode_in.  Hold start until
//                    in_ready rises.
//   go (combinational, one cycle): "a full block starts being read next cycle"
//                    (either from IDLE, or seamlessly at the last cycle of the
//                    current block when the other bank is already full).
//   blk_done (from slot_counters): last cycle of the block being read.
//------------------------------------------------------------------------------
module main_fsm #(                                             // begin module declaration (with one parameter)
    parameter EARLY_ROWS   = 0,                                // 0 = original behaviour; n>0 = early read start for 18-row blocks (64-QAM) once n rows are written
    parameter EARLY_ROWS12 = 0                                 // same for 12-row blocks (16-QAM); 0 = no early start
) (                                                             // end of parameter list, begin port list
    input  wire       clk,                                     // 80 MHz master clock
    input  wire       rst_n,                                   // active-low synchronous reset
    input  wire       start,                                   // upstream request to begin a new block
    input  wire       wr_done,                                 // Write Controller: last row of block written (this cycle)
    input  wire       blk_done,                                // Read Sequencer: last cycle of the block being read
    output reg        wr_run,                                  // write window open (WRITE state)
    output reg        wr_bank,                                 // bank the write side is filling
    input  wire       write_enable,                            // Write Controller memory write strobe (counted to know how many rows are stored)
    input  wire [4:0] wr_rows,                                 // R of the block being written (18 = 64-QAM)
    output reg  [4:0] wr_cnt,                                  // rows of the current block already stored in the memory
    output wire       mode_load,                               // pulse: latch mode_in into wr_bank's mode latch
    output wire       in_ready,                                // upstream may send data words now
    output wire       go,                                      // start/continue reading a full bank next cycle
    output reg        rd_bank,                                 // bank the read side is (or will be) reading
    output reg        rd_active,                               // read side busy (READ state)
    output reg  [1:0] bank_full                                // per-bank "complete block stored" flags
);                                                             // end of port list
    wire [1:0] bf_eff;                                         // bank_full including a block completing right now
    wire [1:0] bf_clr;                                         // bank being released by blk_done this cycle
    wire       blk_done_q;                                     // blk_done qualified by rd_active
    wire       early_ok;                                       // the block being written may already be read (early start)
    wire [1:0] rdy;                                            // per bank: block complete OR early-start condition reached

    assign blk_done_q = blk_done & rd_active;                  // ignore blk_done when the read side is idle
    assign bf_eff = bank_full | {(wr_done & wr_bank), (wr_done & ~wr_bank)}; // set flag of wr_bank when its last row lands
    assign bf_clr = {(blk_done_q & rd_bank), (blk_done_q & ~rd_bank)};        // flag of rd_bank to clear on block end
    assign mode_load = start & ~wr_run & ~bank_full[wr_bank];  // accept start: write side idle and bank free
    assign in_ready  = wr_run;                                 // words accepted exactly while the write window is open
    // Early start: the first R fetches of a 64-QAM block read rows 0,1,...,17 one per clock, so reading may begin once EARLY_ROWS rows
    // are stored, provided rows keep arriving at >= 1 row per 2 clocks (the slowest Encoder rate, 3/4 = 8 bits/clock).
    assign early_ok = wr_run & (((EARLY_ROWS   != 0) & (wr_rows == 5'd18) & (wr_cnt >= EARLY_ROWS)) |   // 64-QAM block, enough rows stored
                              ((EARLY_ROWS12 != 0) & (wr_rows == 5'd12) & (wr_cnt >= EARLY_ROWS12))); // 16-QAM block (fetches only 4 of every 6 clocks)
    assign rdy[0] = bf_eff[0] | (early_ok & ~wr_bank);         // bank 0 readable: full, or being written and early condition met
    assign rdy[1] = bf_eff[1] | (early_ok &  wr_bank);         // bank 1 readable: full, or being written and early condition met
    assign go = rd_active ? (blk_done_q & rdy[~rd_bank])       // READ: continue only at block end if next bank is readable
                          : rdy[rd_bank];                      // IDLE: start as soon as rd_bank is readable

    always @(posedge clk) begin                                // clocked process: all FSM state
        if (!rst_n) begin                                      // synchronous reset asserted
            wr_run     <= 1'b0;                                // write side idle
            wr_bank    <= 1'b0;                                // first block is written into bank 0
            rd_bank    <= 1'b0;                                // first block is read from bank 0
            rd_active  <= 1'b0;                                // read side idle
            bank_full  <= 2'b00;                               // both banks empty
            wr_cnt     <= 5'd0;                                // no rows stored
        end else begin                                         // normal operation
            if (mode_load) wr_run <= 1'b1;                     // IDLE -> WRITE when start is accepted
            if (wr_done) begin                                 // last row of the block has been written
                wr_run  <= 1'b0;                               // WRITE -> IDLE
                wr_bank <= ~wr_bank;                           // next block goes into the other bank
            end                                                // end of wr_done branch
            if (wr_done) wr_cnt <= 5'd0;                       // block complete: restart the row count
            else if (write_enable) wr_cnt <= wr_cnt + 5'd1;    // one more row stored in the memory
            bank_full <= bf_eff & ~bf_clr;                     // set flag on completion, clear flag on release
            if (rd_active) begin                               // read side is in READ
                if (blk_done_q) begin                          // last cycle of the block
                    rd_bank   <= ~rd_bank;                     // ping-pong: next block lives in the other bank
                    rd_active <= go;                           // stay READ only if the other bank is already full
                end                                            // end of blk_done branch
            end else if (go) begin                             // read side IDLE and a full bank is available
                rd_active <= 1'b1;                             // IDLE -> READ
            end                                                // end of read-side branch
        end                                                    // end of reset/normal branch
    end                                                        // end of clocked process
endmodule                                                      // end of main_fsm
