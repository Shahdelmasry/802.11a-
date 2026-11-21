module mapper_top #(                                           
    parameter W = 16                                           
) (                                                            
    input  wire           clk,                                 
    input  wire           rst_n,                               
    input  wire [5:0]     sym_bits,                            
    input  wire           sym_valid,                           
    input  wire           sym_last,                            
    input  wire [1:0]     sym_mode,                            
    output wire [2*W-1:0] complex_symbol_out,                  
    output wire           valid_out,                           
    output wire           last_out                             
);                                                             
    wire [1:0]   bits_per_axis;                                
    wire         Q_en;                                         
    wire [1:0]   LUT_SEL;                                      
    wire [2:0]   I_bits, Q_bits;                               
    wire [W-1:0] I, Q;                                         

    mapper_mode_decoder u_mapper_mode_decoder (                
        .sym_mode(sym_mode), 
        .bits_per_axis(bits_per_axis),    
        .Q_en(Q_en), 
        .LUT_SEL(LUT_SEL)                         
    );                                                         

    axis_separator u_axis_separator (                          
        .sym_bits(sym_bits), 
        .bits_per_axis(bits_per_axis),    
        .I_bits(I_bits), 
        .Q_bits(Q_bits)                       
    );                                                         

    shared_level_mapper #(.W(W)) u_shared_level_mapper (       
        .I_bits(I_bits), 
        .Q_bits(Q_bits),                      
        .bits_per_axis(bits_per_axis), 
        .Q_en(Q_en), 
        .LUT_SEL(LUT_SEL), 
        .I(I), .Q(Q)                                           
    );                                                         

    symbol_output #(.W(W)) u_symbol_output (                   
        .clk(clk), 
        .rst_n(rst_n),                              
        .I(I), 
        .Q(Q),                                          
        .sym_valid(sym_valid), 
        .sym_last(sym_last),            
        .complex_symbol_out(complex_symbol_out),               
        .valid_out(valid_out), 
        .last_out(last_out)             
    );                                                         
endmodule                                                      
