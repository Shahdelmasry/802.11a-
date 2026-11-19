
module fifo_top #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 6,
    parameter P_SIZE = ADDR_WIDTH + 1
)
(
    input wire w_clk,
    input wire r_clk,

    input wire w_rstn,
    input wire r_rstn,

    input wire wen,
    input wire ren,

    input wire [DATA_WIDTH-1:0] data_in,
    output wire [DATA_WIDTH-1:0] data_out,

    output wire full,
    output wire empty,

    // NEW: write pointer (gray) after the 2-FF sync into r_clk, used by fifo_read_ctrl
    output wire [P_SIZE-1:0] sync_wr_ptr_out
);

wire [ADDR_WIDTH-1:0] w_addr;
wire [ADDR_WIDTH-1:0] rd_addr;

wire [P_SIZE-1:0] gray_w_ptr;
wire [P_SIZE-1:0] gray_rd_ptr;

wire [P_SIZE-1:0] sync_wr_ptr;
wire [P_SIZE-1:0] sync_rd_ptr;


// Write Controller
fifo_wr #(
    .P_SIZE(P_SIZE)
) U_FIFO_WR (
    .clk(w_clk),
    .rst(w_rstn),
    .wen(wen),
    .sync_rd_ptr(sync_rd_ptr),
    .w_addr(w_addr),
    .gray_w_ptr(gray_w_ptr),
    .full(full)
);


// Read Controller
fifo_rd #(
    .P_SIZE(P_SIZE)
) U_FIFO_RD (
    .clk(r_clk),
    .rst(r_rstn),
    .ren(ren),
    .sync_wr_ptr(sync_wr_ptr),
    .rd_addr(rd_addr),
    .empty(empty),
    .gray_rd_ptr(gray_rd_ptr)
);


// Synchronize Read Pointer to Write Domain
sync #(
    .DATA_SIZE(P_SIZE)
) U_SYNC_RD (
    .clk(w_clk),
    .rst(w_rstn),
    .unsync_ip(gray_rd_ptr),
    .sync_op(sync_rd_ptr)
);


// Synchronize Write Pointer to Read Domain
sync #(
    .DATA_SIZE(P_SIZE)
) U_SYNC_WR (
    .clk(r_clk),
    .rst(r_rstn),
    .unsync_ip(gray_w_ptr),
    .sync_op(sync_wr_ptr)
);


// FIFO Memory
mem_fifo #(
    .word(DATA_WIDTH),
    .input_data(ADDR_WIDTH)
) U_MEM_FIFO (
    .clk(w_clk),
    .rst(w_rstn),
    .wen(wen),
    .full(full),
    .data_in(data_in),
    .address_in(w_addr),
    .address_out(rd_addr),
    .data_out(data_out)
);


assign sync_wr_ptr_out = sync_wr_ptr;

endmodule
