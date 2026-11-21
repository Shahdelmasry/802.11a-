module slot_counters (                                         
    input  wire       clk,                                     
    input  wire       rst_n,                                   
    input  wire       go,                                      
    input  wire [2:0] N_BPSC,                                  
    output wire [2:0] q,                                       
    output wire       fetch_en,                                
    output wire       blk_done,                                
    output wire       sym_valid,                               
    output wire       sym_last,                                
    output wire       pipe_busy                                
);                                                             
    reg        active;                                         
    reg  [2:0] slot_cnt;                                       
    reg  [5:0] sym_cnt;                                        
    reg        sv1, sv2;                                       
    reg        sl1, sl2;                                       
    wire       slot_end;                                       
    wire       last_slot;                                      

    assign q         = slot_cnt;                               
    assign fetch_en  = active & (slot_cnt < N_BPSC);           
    assign slot_end  = active & (slot_cnt == 3'd5);            
    assign last_slot = slot_end & (sym_cnt == 6'd47);          
    assign blk_done  = last_slot;                              
    assign sym_valid = sv2;                                    
    assign sym_last  = sl2;                                    
    assign pipe_busy = sv1 | sv2;                              

    always @(posedge clk) begin                                
        if (!rst_n) begin                                      
            active   <= 1'b0;                                  
            slot_cnt <= 3'd0;                                  
            sym_cnt  <= 6'd0;                                  
            sv1      <= 1'b0;                                  
            sv2      <= 1'b0;                                  
            sl1      <= 1'b0;                                  
            sl2      <= 1'b0;                                  
        end else begin                                         
            sv1 <= slot_end;                                   
            sv2 <= sv1;                                        
            sl1 <= last_slot;                                  
            sl2 <= sl1;                                        
            if (active) begin                                  
                if (slot_cnt == 3'd5) begin                    
                    slot_cnt <= 3'd0;                          
                    if (sym_cnt == 6'd47) begin                
                        sym_cnt <= 6'd0;                       
                        active  <= go;                         
                    end else begin                             
                        sym_cnt <= sym_cnt + 6'd1;             
                    end                                        
                end else begin                                 
                    slot_cnt <= slot_cnt + 3'd1;               
                end                                            
            end else if (go) begin                             
                active <= 1'b1;                                
            end                                                
        end                                                    
    end                                                        
endmodule                                                      
