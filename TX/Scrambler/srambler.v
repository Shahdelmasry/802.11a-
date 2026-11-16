// Top module
module scrambler #(
    parameter DATA_LENGTH = 6
) (
    input  wire                        clk,        // postive edge clk 
    input  wire                        rst,        // negtive edge rst
    input  wire                        enable,     // from fsm: 1 = valid data word, 0 = pause (the packet is NOT restarted)
    input  wire                        packet_end, // from fsm: 1 with the last word of the packet (1 alone = abort)
    input  wire                        seed_sel,   // 0 = use the external seed , 1 = use the internal seed generator
    input  wire    [6:0]               seed,       // external seed (used when seed_sel = 0)
    input  wire [DATA_LENGTH-1:0]      data_in,    // from fsm after adding service bits and padding     

    output wire                        out_valid,  // that should go to fsm 
    output wire [DATA_LENGTH-1:0]      data_out,   // scrambled data
    output wire [6:0]                  seed_used   // the seed of the current packet (valid from the cycle after the packet starts)
);
    wire [6:0]             index;
    wire                   mem_en, scr_en, pkt_start;
    wire [DATA_LENGTH-1:0] seq;
    wire [6:0]             gen_seed;

    assign seed_used = seed_sel ? gen_seed : seed;

    seed_gen u_gen (
        .clk(clk),
        .rst(rst),
        .start(pkt_start),
        .seed(gen_seed));

    seed_to_index #(.DATA_LENGTH(DATA_LENGTH)) seed_to_index (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .packet_end(packet_end),
        .seed(seed_used),
        .pkt_start(pkt_start),
        .mem_en(mem_en),
        .scr_en(scr_en),
        .index(index));

    Memory #(.DATA_LENGTH(DATA_LENGTH)) mem (
        .clk(clk),
        .rst(rst),
        .en(mem_en),
        .index(index),
        .data_out(seq));

    scr #(.DATA_LENGTH(DATA_LENGTH)) scr (
        .clk(clk),
        .rst(rst),
        .en(scr_en),
        .seq_in(seq),
        .data_in(data_in),
        .data_vld(out_valid),
        .data_out(data_out));
endmodule
