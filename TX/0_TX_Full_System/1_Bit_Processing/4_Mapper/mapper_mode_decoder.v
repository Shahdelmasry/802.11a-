module mapper_mode_decoder (                                   
    input  wire [1:0] sym_mode,                                
    output reg  [1:0] bits_per_axis,                           
    output wire       Q_en,                                    
    output wire [1:0] LUT_SEL                                  
);                                                             
    assign LUT_SEL = sym_mode;                                 
    assign Q_en    = (sym_mode != 2'b00);                      

    always @(*) begin                                          
        case (sym_mode)                                        
            2'b00:   bits_per_axis = 2'd1;                     
            2'b01:   bits_per_axis = 2'd1;                     
            2'b10:   bits_per_axis = 2'd2;                     
            default: bits_per_axis = 2'd3;                     
        endcase                                                
    end                                                        
endmodule                                                      
