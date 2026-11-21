module symbol_assembler (                                      
    input  wire       clk,                                     
    input  wire       rst_n,                                   
    input  wire       read_bit,                                
    input  wire [2:0] win_idx,                                 
    input  wire       win_we,                                  
    input  wire       sym_valid_in,                            
    input  wire [1:0] mode_rd,                                 
    output wire [5:0] sym_bits,                                
    output wire [1:0] sym_mode                                 
);                                                             
    reg  [5:0] win;                                            
    reg  [5:0] win_nxt;                                        
    reg        bit_reg;                                        
    reg  [1:0] mode_d;                                         
    reg  [1:0] sym_mode_r;                                     

    assign sym_bits = win;                                     
    assign sym_mode = sym_mode_r;                              

    always @(*) begin                                          
        win_nxt = win;                                         
        if (sym_valid_in) win_nxt = 6'd0;                      
        if (win_we) win_nxt[win_idx] = bit_reg;                
    end                                                        

    always @(posedge clk) begin                                
        if (!rst_n) begin                                      
            win        <= 6'd0;                                
            bit_reg    <= 1'b0;                                
            mode_d     <= 2'b00;                               
            sym_mode_r <= 2'b00;                               
        end else begin                                         
            bit_reg <= read_bit;                               
            mode_d  <= mode_rd;                                
            win     <= win_nxt;                                
            if (win_we) sym_mode_r <= mode_d;                  
        end                                                    
    end                                                        
endmodule                                                      
