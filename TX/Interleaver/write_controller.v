// write_controller.v  -  "Write Controller"
// Assembles the upstream bit stream into 16-bit words and stores each complete
// word as one row of the Matrix Memory.
//   in_cnt  = number of valid bits in data_in this cycle (0..16); they are the
//             LOW in_cnt bits data_in[in_cnt-1:0], data_in[0] = earliest bit.
//   Bit order: coded bit k = 16*row + c is bit c of row 'row' (LSB = earliest).
// Internal buffer: part_buf (bits waiting) and fill (how many, 0..15).
// A write happens in the SAME cycle in which fill + in_cnt reaches 16 or more
// (so in_cnt = 16 with an empty buffer behaves exactly like the old pass-through).
// Excess bits (fill + in_cnt - 16) stay in the buffer for the next word.
// At most one word completes per cycle (in_cnt <= 16, fill <= 15), so one
// memory write port is enough and no upstream stall is needed.
// wr_done is combinational: high in the cycle of the LAST row write.
// At wr_done the buffer is cleared so bits of the next symbol never mix with it;
//------------------------------------------------------------------------------
module write_controller (                                      // begin module declaration
    input  wire        clk,                                    // 80 MHz master clock
    input  wire        rst_n,                                  // active-low synchronous reset
    input  wire        wr_run,                                 // write window open (from Main FSM)
    input  wire        wr_bank,                                // bank to write (from Main FSM)
    input  wire [4:0]  wr_rows,                                // number of rows R of this block (3/6/12/18)
    input  wire        valid_in,                               // upstream: data_in carries in_cnt valid bits
    input  wire [4:0]  in_cnt,                                 // NEW: number of valid bits in data_in (0..16, >16 treated as 16)
    input  wire [15:0] data_in,                                // upstream bits, valid ones in the low in_cnt positions
    output wire        write_enable,                           // memory write strobe
    output wire [5:0]  write_addr,                             // memory write address {bank,row[4:0]}
    output wire [15:0] write_data,                             // memory write data (the assembled row word)
    output wire        wr_done                                // this write completes the block
);                                                             // end of port list
    reg  [4:0]  wr_row;                                        // index of the row to be written next
    reg  [15:0] part_buf;                                      // buffered bits (valid in the low 'fill' positions, rest zero)
    reg  [3:0]  fill;                                          // number of buffered bits (0..15)

    wire        take    = wr_run & valid_in;                   // bits are accepted only while the window is open
    wire [4:0]  cnt_c   = (in_cnt > 5'd16) ? 5'd16 : in_cnt;   // clamp the count to 16
    wire [4:0]  cnt_u   = take ? cnt_c : 5'd0;                 // bits actually taken this cycle
    wire [31:0] mask    = (32'd1 << cnt_u) - 32'd1;            // ones in the low cnt_u positions: hides unused data_in bits
    wire [31:0] acc     = {16'd0, part_buf} | (({16'd0, data_in} & mask) << fill); // buffered bits first, new bits placed above them
    wire [5:0]  total   = {2'd0, fill} + {1'b0, cnt_u};        // bits available this cycle (0..31)
    wire        full    = (total >= 6'd16);                    // a complete 16-bit word is available

    assign write_enable = take & full;                         // write only when a complete word exists
    assign write_addr   = {wr_bank, wr_row};                   // bank bit on top, row index below
    assign write_data   = acc[15:0];                           // the assembled word (earliest bit in bit 0)
    assign wr_done      = write_enable & (wr_row == (wr_rows - 5'd1)); // last row of the block is being written

    always @(posedge clk) begin                                // clocked process: row counter, buffer, fill, error flag
        if (!rst_n) begin                                      // synchronous reset asserted
            wr_row     <= 5'd0;                                // start again at row 0
            part_buf   <= 16'd0;                               // drop any partially assembled word
            fill       <= 4'd0;                                // no buffered bits
        end else begin                                         // normal operation
            if (wr_done) begin                                 // block complete
                wr_row   <= 5'd0;                              // rewind for the next block
                part_buf <= 16'd0;                             // next symbol starts with an empty buffer
                fill     <= 4'd0;                              // no leftover bits are carried over
            end else if (write_enable) begin                   // a word is written, block not finished
                wr_row   <= wr_row + 5'd1;                     // advance to the next row
                part_buf <= acc[31:16];                        // keep the excess bits (earliest first)
                fill     <= total[3:0];                       // total-16 = low 4 bits of total (total is 16..31)
            end else if (take) begin                           // bits accepted but the word is not complete yet
                part_buf <= acc[15:0];                         // keep everything in the buffer
                fill     <= total[3:0];                        // total < 16 here, so 4 bits are enough
            end                                                // no bits: hold buffer and counters
        end                                                    // end of reset/normal branch
    end                                                        // end of clocked process
endmodule                                                      // end of write_controller
