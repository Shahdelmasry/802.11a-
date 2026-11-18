// read_addr_gen.v  -  "Read Addr Gen" part of the Read Sequencer
// Implements the FIRST permutation purely through the read order:
//   bit index i (0,1,2,...) is fetched from row = i mod R, column = floor(i/R)
// using two counters (no dividers).  This equals the standard's
//   i = (N_CBPS/16)*(k mod 16) + floor(k/16)    with k = 16*row + col.
// The counters are zero between blocks because col (4 bits) wraps 15 -> 0
// exactly when the last bit of a block has been fetched.
//------------------------------------------------------------------------------
module read_addr_gen (                                         // begin module declaration
    input  wire       clk,                                     // 80 MHz master clock
    input  wire       rst_n,                                   // active-low synchronous reset
    input  wire       fetch_en,                                // this cycle fetches one bit
    input  wire [4:0] R,                                       // rows of the current block (3/6/12/18)
    input  wire       rd_bank,                                 // bank being read
    output wire [5:0] read_addr,                               // {rd_bank,row[4:0]} to the memory
    output wire [3:0] read_col                                 // column to the memory 16:1 mux (also to Second Perm)
);                                                             // end of port list
    reg  [4:0] row;                                            // current row counter = i mod R
    reg  [3:0] col;                                            // current column counter = floor(i/R)
    wire       last_row;                                       // row counter is at its wrap value R-1

    assign last_row  = (row == (R - 5'd1));                    // true when row == R-1
    assign read_addr = {rd_bank, row};                         // bank bit above the row index
    assign read_col  = col;                                    // column counter drives the column mux

    always @(posedge clk) begin                                // clocked process: row/col counters
        if (!rst_n) begin                                      // synchronous reset asserted
            row <= 5'd0;                                       // restart at row 0
            col <= 4'd0;                                       // restart at column 0
        end else if (fetch_en) begin                           // only advance when a bit is fetched
            if (last_row) begin                                // bottom of the column reached
                row <= 5'd0;                                   // wrap to the top row
                col <= col + 4'd1;                             // move to the next column (wraps 15 -> 0 at block end)
            end else begin                                     // still inside the column
                row <= row + 5'd1;                             // go one row down
            end                                                // end of last_row branch
        end                                                    // no fetch: hold both counters
    end                                                        // end of clocked process
endmodule                                                      // end of read_addr_gen
