module axis_separator (                                        
    input  wire [5:0] sym_bits,                                
    input  wire [1:0] bits_per_axis,                           
    output reg  [2:0] I_bits,                                  
    output reg  [2:0] Q_bits                                   
);                                                             
    always @(*) begin                                          
        case (bits_per_axis)                                   
            2'd1: begin                                        
                I_bits = {2'b00, sym_bits[0]};                 
                Q_bits = {2'b00, sym_bits[1]};                 
            end                                                
            2'd2: begin                                        
                I_bits = {1'b0, sym_bits[0], sym_bits[1]};     
                Q_bits = {1'b0, sym_bits[2], sym_bits[3]};     
            end                                                
            default: begin                                     
                I_bits = {sym_bits[0], sym_bits[1], sym_bits[2]}; 
                Q_bits = {sym_bits[3], sym_bits[4], sym_bits[5]}; 
            end                                               
        endcase                                               
    end                                                       
endmodule                                                     
