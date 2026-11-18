// matrix_memory.v  -  "Matrix Memory"
// Two banks (addr[5] = bank) of 32 x 16-bit words; only rows 0..17 of each bank
// are used.  Row-wide synchronous write, asynchronous (LUTRAM style) row read,
// followed by a 16:1 column multiplexer that returns ONE bit (read_bit).
// The memory has no reset (RAM); content is only meaningful after it is written.
//------------------------------------------------------------------------------
module matrix_memory (                                         // begin module declaration
    input  wire        clk,                                    // 80 MHz master clock (write port clock)
    input  wire        write_enable,                           // write strobe
    input  wire [5:0]  write_addr,                             // {bank,row[4:0]} to write
    input  wire [15:0] write_data,                             // 16-bit row word to store
    input  wire [5:0]  read_addr,                              // {bank,row[4:0]} to read
    input  wire [3:0]  read_col,                               // column (bit) select inside the row word
    output wire        read_bit                                // the selected single bit
);                                                             // end of port list
    reg  [15:0] mem [0:63];                                    // 64 words of 16 bits (2 banks x 32 rows)
    wire [15:0] row_word;                                      // row word fetched asynchronously by read_addr

    always @(posedge clk) begin                                // clocked process: write port
        if (write_enable) mem[write_addr] <= write_data;       // store the row word when enabled
    end                                                        // end of write process

    assign row_word = mem[read_addr];                          // asynchronous row read (LUTRAM behaviour)
    assign read_bit = row_word[read_col];                      // 16:1 column mux: pick bit 'read_col' of the row
endmodule                                                      // end of matrix_memory
