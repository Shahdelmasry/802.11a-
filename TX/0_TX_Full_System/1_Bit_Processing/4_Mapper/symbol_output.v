module symbol_output #(                                        
    parameter W = 16                                           
) (                                                            
    input  wire           clk,                                 
    input  wire           rst_n,                               
    input  wire [W-1:0]   I,                                   
    input  wire [W-1:0]   Q,                                   
    input  wire           sym_valid,                           
    input  wire           sym_last,                            
    output reg  [2*W-1:0] complex_symbol_out,                  
    output reg            valid_out,                           
    output reg            last_out                             
);                                                             
    always @(posedge clk) begin                                
        if (!rst_n) begin                                      
            complex_symbol_out <= {2*W{1'b0}};                 
            valid_out          <= 1'b0;                        
            last_out           <= 1'b0;                        
        end else begin                                         
            valid_out <= sym_valid;                            
            last_out  <= sym_valid & sym_last;                 
            if (sym_valid) complex_symbol_out <= {I, Q};       
        end                                                    
    end                                                        
endmodule                                                      
