module pam_path #(                                             
    parameter W = 16                                           
) (                                                            
    input  wire [2:0]   bits,                                  
    input  wire [1:0]   bits_per_axis,                         
    input  wire [W-1:0] amp,                                   
    output reg  [1:0]   idx,                                   
    output wire [W-1:0] level                                  
);                                                             
    reg sign_pos;                                              

    always @(*) begin                                          
        case (bits_per_axis)                                   
            2'd1: begin                                        
                sign_pos = bits[0];                            
                idx      = 2'd0;                               
            end                                                
            2'd2: begin                                        
                sign_pos = bits[1];                            
                idx      = {1'b0, ~bits[0]};                   
            end                                                
            default: begin                                     
                sign_pos = bits[2];                            
                if (bits[1]) idx = {1'b0, bits[0]};            
                else         idx = {1'b1, ~bits[0]};           
            end                                                
        endcase                                                
    end                                                        

    assign level = sign_pos ? amp : ({W{1'b0}} - amp);         
endmodule                                                      
