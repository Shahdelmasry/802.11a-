module top_wrapper_bit_proc #(                                 
    parameter W = 16                                           
) (                                                            
    input  wire           clk,                                 
    input  wire           rst_n,                               
    
    input  wire           tx_clear,
    input  wire           il_start,                            
    input  wire           scr_enable,                          
    input  wire [6:0]     scr_seed,                            
    input  wire           scr_bypass,                          
    input  wire [1:0]     coding_rate,                         
    input  wire [1:0]     modulation,                          
    input  wire           packet_end,
    input  wire           seed_sel, 
    
    input  wire [5:0]     data_in,                             
    input  wire [5:0]     tail_mask,                           
    
    output wire           data_req,                            
    output wire           in_ready,                            
    output wire           il_busy,                             
    output wire           cfg_err,                             
    
    output wire [2*W-1:0] complex_symbol_out,                  
    output wire           valid_out,                           
    output wire           last_out                             
);                                                             
    wire [15:0] wc_data;                                       
    wire [4:0]  wc_cnt;                                        
    wire        wc_valid;                                      
    wire [5:0]  sym_bits;                                      
    wire        sym_valid, sym_last;                           
    wire [1:0]  sym_mode;                                      

    assign cfg_err = (coding_rate == 2'd3)                                   
                   | ((coding_rate == 2'd1) & (modulation != 2'd3))          
                   | ((coding_rate == 2'd0) & (modulation == 2'd3));         

    tx_front_end u_front (                                     
        .clk(clk), 
        .rst_n(rst_n), 
        .scr_enable(scr_enable), 
        .scr_bypass(scr_bypass), 
        .enc_clear(tx_clear), 
        .seed(scr_seed), 
        .packet_end(packet_end),
        .seed_sel(seed_sel),
        .data_req(data_req), 
        .data_in(data_in), 
        .tail_mask(tail_mask), 
        .enc_rate(coding_rate), 
        .wc_data(wc_data), 
        .wc_cnt(wc_cnt), 
        .wc_valid(wc_valid) 
    );                                                         
    interleaver_top_cnt u_interleaver (                        
        .clk(clk), 
        .rst_n(rst_n), 
        .data_in(wc_data), 
        .valid_in(wc_valid), 
        .in_cnt(wc_cnt), 
        .start(il_start), 
        .mode_in(modulation), 
        .in_ready(in_ready), 
        .busy(il_busy), 
        .sym_bits(sym_bits), 
        .sym_valid(sym_valid), 
        .sym_last(sym_last), 
        .sym_mode(sym_mode) 
    );                                                         
    mapper_top #(.W(W)) u_mapper (                             
        .clk(clk), 
        .rst_n(rst_n), 
        .sym_bits(sym_bits), 
        .sym_valid(sym_valid), 
        .sym_last(sym_last), 
        .sym_mode(sym_mode), 
        .complex_symbol_out(complex_symbol_out), 
        .valid_out(valid_out), 
        .last_out(last_out) 
    );                                                         
endmodule                                                      
