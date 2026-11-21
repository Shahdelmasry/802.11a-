module tx_front_end (                                          
    input  wire        clk,                                    
    input  wire        rst_n,                                  
    input  wire        scr_enable,                             
    input  wire        scr_bypass,                             
    input  wire        enc_clear,                              
    input  wire [6:0]  seed,                                   
    input  wire [5:0]  data_in,                                
    input  wire [5:0]  tail_mask,                              
    input  wire [1:0]  enc_rate,                               
    input  wire        packet_end,
    input  wire        seed_sel,                               
    output wire        data_req,                               
    output wire [15:0] wc_data,                               
    output wire [4:0]  wc_cnt,                                
    output wire        wc_valid                               
);    
    wire [6:0]  seed_used;                                                   
    wire [5:0]  scr_out;                                      
    wire        scr_valid;                                    
    wire [5:0]  enc_in;                                       
    wire        enc_en;                                       
    wire [11:0] e_d12;                                        
    wire [8:0]  e_d23;                                        
    wire [7:0]  e_d34;                                        
    reg  [5:0]  data_d1, mask_d1;                             
    reg         req_d1;                                       
    reg  [1:0]  rate_d1;                                      
    reg         en_d1, en_d2;                                 
    reg         clr_q;                                        
    wire        enc_rst_n = rst_n & ~clr_q;                   

    assign data_req = scr_enable & en_d2;                      
    always @(posedge clk ) begin                               
        data_d1 <= data_in;                                    
        mask_d1 <= tail_mask;                                  
        req_d1  <= data_req;                                   
        rate_d1 <= enc_rate;                                   
        en_d1   <= rst_n & scr_enable;                         
        en_d2   <= rst_n & en_d1;                              
        clr_q   <= enc_clear;                                  
    end                                                        

    scrambler #(.DATA_LENGTH(6)) u_scrambler (                 
        .clk(clk), 
        .rst_n(rst_n),                               
        .enable(scr_enable & ~scr_bypass), 
        .seed(seed),        
        .data_in(data_in),
        .packet_end(packet_end), 
        .seed_sel(seed_sel),
        .out_valid(scr_valid), 
        .data_out(scr_out), 
        .seed_used(seed_used)
    );                                                         

    assign enc_in = scr_bypass ? data_d1 : (scr_out & ~mask_d1); 
    assign enc_en = scr_bypass ? req_d1  : scr_valid;            

    convolution_encoder #(.DATA_WIDTH(6)) u_encoder (          
        .clk(clk), 
        .rst_n(enc_rst_n),                            
        .enable(enc_en), 
        .data_in(enc_in), 
        .rate(enc_rate),    
        .data_out(e_d12), 
        .data_out_23(e_d23), 
        .data_out_34(e_d34), 
        .out_valid(wc_valid) 
    );                                                        

    enc_adapter u_adapter (                                
        .rate_sel(rate_d1), 
        .data_out(e_d12), 
        .data_out_23(e_d23), 
        .data_out_34(e_d34), 
        .wc_data(wc_data), 
        .wc_cnt(wc_cnt)                     
    );                                      
endmodule                                   
