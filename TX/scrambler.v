// Top module
module scrambler #(
    parameter DATA_LENGTH = 6
) (
    input  wire                        clk,// postive edge clk 
    input  wire                        rst,// negtive edge rst
    input  wire                        enable,// that come from fsm 
    input  wire    [6:0]               seed,  // from fsm  
    input  wire [DATA_LENGTH-1:0]      data_in,  //from fsm after adding service bits and padding     

    output reg                         out_valid, // that should go to fsm 
    output wire [DATA_LENGTH-1:0]      data_out // fsm : output data that should go to scrambler 
);
    wire [6:0]             index;
    wire                   mem_en, scr_en;
    wire [DATA_LENGTH-1:0] seq;

    seed_to_index #(.DATA_LENGTH(DATA_LENGTH)) seed_to_index (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .seed(seed),
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
