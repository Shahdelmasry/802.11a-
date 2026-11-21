module shared_level_mapper #(                                  
    parameter W = 16                                           
) (                                                            
    input  wire [2:0]   I_bits,                                
    input  wire [2:0]   Q_bits,                                
    input  wire [1:0]   bits_per_axis,                         
    input  wire         Q_en,                                  
    input  wire [1:0]   LUT_SEL,                               
    output wire [W-1:0] I,                                     
    output wire [W-1:0] Q                                      
);                                                             
    wire [1:0]   idx_i, idx_q;                                 
    wire [W-1:0] amp_i, amp_q;                                 
    wire [W-1:0] level_q;                                      

    pam_path #(.W(W)) u_i_path (                               
        .bits(I_bits), 
        .bits_per_axis(bits_per_axis),          
        .amp(amp_i), 
        .idx(idx_i), 
        .level(I)                    
    );                                                         

    pam_path #(.W(W)) u_q_path (                               
        .bits(Q_bits), 
        .bits_per_axis(bits_per_axis),          
        .amp(amp_q), 
        .idx(idx_q), 
        .level(level_q)              
    );                                                         

    amplitude_lut #(.W(W)) u_amplitude_lut (                   
        .lut_sel(LUT_SEL), 
        .idx_i(idx_i), 
        .idx_q(idx_q),       
        .amp_i(amp_i), 
        .amp_q(amp_q)                           
    );                                                         

    assign Q = Q_en ? level_q : {W{1'b0}};                     
endmodule                                                      
