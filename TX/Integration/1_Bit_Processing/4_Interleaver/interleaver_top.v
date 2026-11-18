// Blocks: Main FSM, Mode Register, Write Controller, Matrix Memory (2 banks),
//         Read Sequencer (= read_addr_gen + second_perm + slot_counters),
//         Symbol Assembler.
// Output interface to the Mapper: sym_bits[5:0] + sym_valid + sym_last + sym_mode.
//------------------------------------------------------------------------------
module interleaver_top_cnt #(                                  // begin module declaration (with one parameter)
    parameter EARLY_ROWS   = 10,                               // early read start for 64-QAM blocks (R=18) after this many rows (0 = original timing)
    parameter EARLY_ROWS12 = 6                                 // early read start for 16-QAM blocks (R=12) after this many rows (0 = original timing)
) (                                                             // end of parameter list, begin port list
    input  wire        clk,                                    // 80 MHz master clock
    input  wire        rst_n,                                  // active-low synchronous reset
    input  wire [15:0] data_in,                                // coded-bit word = one matrix row (bit0 = earliest)
    input  wire        valid_in,                               // data_in valid (used only while in_ready=1)
    input  wire [4:0]  in_cnt,                                 // NEW: number of valid bits in data_in (0..16), see write_controller
    input  wire        start,                                  // request a new block (level; hold until in_ready)
    input  wire [1:0]  mode_in,                                // modulation of that block: 00/01/10/11
    output wire        in_ready,                               // upstream may send the R words now
    output wire        busy,                                   // block in flight (start .. last symbol issued)
    output wire [5:0]  sym_bits,                               // one symbol, bits in final interleaved order
    output wire        sym_valid,                              // sym_bits valid (one cycle per 6 cycles)
    output wire        sym_last,                               // sym_bits is symbol 47 of the OFDM symbol
    output wire [1:0]  sym_mode                                // mode of the block that sym_bits belongs to
);                                                             // end of port list
    wire        wr_run;                                        // write window open
    wire        wr_bank;                                       // bank being written
    wire [4:0]  wr_rows;                                       // R of the block being written
    wire        wr_done;                                       // last row written
    wire        mode_load;                                     // latch mode_in
    wire        write_enable;                                  // memory write strobe
    wire [5:0]  write_addr;                                    // memory write address
    wire [15:0] write_data;                                    // memory write data
    wire [5:0]  read_addr;                                     // memory read address
    wire [3:0]  read_col;                                      // memory column select
    wire        read_bit;                                      // bit read from memory
    wire [2:0]  q;                                             // bit number inside the symbol
    wire [2:0]  win_idx;                                       // window position
    wire        win_we;                                        // window write strobe
    wire        fetch_en;                                      // fetch strobe
    wire        go;                                            // start/continue reading
    wire        rd_bank;                                       // bank being read
    wire        rd_active;                                     // read side busy
    wire        blk_done;                                      // last cycle of the block
    wire [1:0]  bank_full;                                     // bank-full flags
    wire [4:0]  R;                                             // rows of the read-side block
    wire [2:0]  N_BPSC;                                        // bits per symbol of the read-side block
    wire [1:0]  s;                                             // s of the read-side block
    wire [1:0]  mode_rd;                                       // mode code of the read-side bank
    wire        pipe_busy;                                     // strobes still in the sym_valid pipe

    assign busy = mode_load | wr_run | rd_active | (|bank_full) | pipe_busy; // block in flight anywhere in the pipeline

    wire [4:0]  wr_cnt;                                        // NEW: rows of the current block already stored
    main_fsm #(.EARLY_ROWS(EARLY_ROWS), .EARLY_ROWS12(EARLY_ROWS12)) u_main_fsm (           // Main FSM instance (early start enabled by the parameter)
        .clk       (clk),                                      // clock
        .rst_n     (rst_n),                                    // reset
        .start     (start),                                    // request from upstream
        .wr_done   (wr_done),                                  // from Write Controller
        .blk_done  (blk_done),                                 // from Slot Counters
        .write_enable (write_enable),                          // NEW: memory write strobe (row counting)
        .wr_rows   (wr_rows),                                  // NEW: R of the block being written
        .wr_cnt    (wr_cnt),                                   // NEW: stored-row count
        .wr_run    (wr_run),                                   // to Write Controller
        .wr_bank   (wr_bank),                                  // to Write Controller / Mode Register
        .mode_load (mode_load),                                // to Mode Register
        .in_ready  (in_ready),                                 // to upstream
        .go        (go),                                       // to Slot Counters
        .rd_bank   (rd_bank),                                  // to Read Addr Gen / Mode Register
        .rd_active (rd_active),                                // status
        .bank_full (bank_full)                                 // status
    );                                                         // end of u_main_fsm

    mode_register u_mode_register (                            // Mode Register instance
        .clk       (clk),                                      // clock
        .rst_n     (rst_n),                                    // reset
        .mode_in   (mode_in),                                  // requested mode
        .mode_load (mode_load),                                // latch strobe
        .wr_bank   (wr_bank),                                  // write-side bank
        .rd_bank   (rd_bank),                                  // read-side bank
        .wr_rows   (wr_rows),                                  // to Write Controller
        .mode_rd   (mode_rd),                                  // to Symbol Assembler
        .R         (R),                                        // to Read Addr Gen
        .N_BPSC    (N_BPSC),                                   // to Slot Counters
        .s         (s)                                         // to Second Perm
    );                                                         // end of u_mode_register

    write_controller u_write_controller (                      // Write Controller instance
        .clk          (clk),                                   // clock
        .rst_n        (rst_n),                                 // reset
        .wr_run       (wr_run),                                // window open
        .wr_bank      (wr_bank),                               // bank to fill
        .wr_rows      (wr_rows),                               // rows in this block
        .valid_in     (valid_in),                              // word valid
        .in_cnt       (in_cnt),                                // NEW: valid-bit count
        .data_in      (data_in),                               // word
        .write_enable (write_enable),                          // to memory
        .write_addr   (write_addr),                            // to memory
        .write_data   (write_data),                            // to memory
        .wr_done      (wr_done)                                // to Main FSM
    );                                                         // end of u_write_controller

    matrix_memory u_matrix_memory (                            // Matrix Memory instance
        .clk          (clk),                                   // clock
        .write_enable (write_enable),                          // write strobe
        .write_addr   (write_addr),                            // write address
        .write_data   (write_data),                            // write data
        .read_addr    (read_addr),                             // read address
        .read_col     (read_col),                              // column select
        .read_bit     (read_bit)                               // selected bit
    );                                                         // end of u_matrix_memory

    slot_counters u_slot_counters (                            // Slot Counters instance
        .clk       (clk),                                      // clock
        .rst_n     (rst_n),                                    // reset
        .go        (go),                                       // start/continue
        .N_BPSC    (N_BPSC),                                   // fetch cycles per slot
        .q         (q),                                        // bit number in symbol
        .fetch_en  (fetch_en),                                 // fetch strobe
        .blk_done  (blk_done),                                 // block end
        .sym_valid (sym_valid),                                // symbol strobe to Mapper
        .sym_last  (sym_last),                                 // last-symbol strobe to Mapper
        .pipe_busy (pipe_busy)                                 // status
    );                                                         // end of u_slot_counters

    read_addr_gen u_read_addr_gen (                            // Read Addr Gen instance
        .clk       (clk),                                      // clock
        .rst_n     (rst_n),                                    // reset
        .fetch_en  (fetch_en),                                 // fetch strobe
        .R         (R),                                        // rows
        .rd_bank   (rd_bank),                                  // bank
        .read_addr (read_addr),                                // to memory
        .read_col  (read_col)                                  // to memory and Second Perm
    );                                                         // end of u_read_addr_gen

    second_perm u_second_perm (                                // Second Perm instance
        .clk      (clk),                                       // clock
        .rst_n    (rst_n),                                     // reset
        .fetch_en (fetch_en),                                  // fetch strobe
        .q        (q),                                         // bit number in symbol
        .col      (read_col),                                  // column
        .s        (s),                                         // group size
        .win_idx  (win_idx),                                   // to Symbol Assembler
        .win_we   (win_we)                                     // to Symbol Assembler
    );                                                         // end of u_second_perm

    symbol_assembler u_symbol_assembler (                      // Symbol Assembler instance
        .clk          (clk),                                   // clock
        .rst_n        (rst_n),                                 // reset
        .read_bit     (read_bit),                              // bit from memory
        .win_idx      (win_idx),                               // window position
        .win_we       (win_we),                                // window write strobe
        .sym_valid_in (sym_valid),                             // clear after the symbol is consumed
        .mode_rd      (mode_rd),                               // read-side mode code
        .sym_bits     (sym_bits),                              // to Mapper
        .sym_mode     (sym_mode)                               // to Mapper
    );                                                         // end of u_symbol_assembler
endmodule                                                      // end of interleaver_top_cnt
