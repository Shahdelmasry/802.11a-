module main_fsm #(                                             
    parameter EARLY_ROWS   = 0,                                
    parameter EARLY_ROWS12 = 0                                 
) (                                                            
    input  wire       clk,                                     
    input  wire       rst_n,                                   
    input  wire       start,                                   
    input  wire       wr_done,                                 
    input  wire       blk_done,                                
    output reg        wr_run,                                  
    output reg        wr_bank,                                 
    input  wire       write_enable,                            
    input  wire [4:0] wr_rows,                                 
    output reg  [4:0] wr_cnt,                                  
    output wire       mode_load,                               
    output wire       in_ready,                                
    output wire       go,                                      
    output reg        rd_bank,                                 
    output reg        rd_active,                               
    output reg  [1:0] bank_full                                
);                                                             
    wire [1:0] bf_eff;                                         
    wire [1:0] bf_clr;                                         
    wire       blk_done_q;                                     
    wire       early_ok;                                       
    wire [1:0] rdy;                                            

    assign blk_done_q = blk_done & rd_active;                  
    assign bf_eff = bank_full | {(wr_done & wr_bank), (wr_done & ~wr_bank)}; 
    assign bf_clr = {(blk_done_q & rd_bank), (blk_done_q & ~rd_bank)};       
    assign mode_load = start & ~wr_run & ~bank_full[wr_bank];  
    assign in_ready  = wr_run;                                 
    assign early_ok = wr_run & (((EARLY_ROWS   != 0) & (wr_rows == 5'd18) & (wr_cnt >= EARLY_ROWS)) | 
                              ((EARLY_ROWS12 != 0) & (wr_rows == 5'd12) & (wr_cnt >= EARLY_ROWS12))); 
    assign rdy[0] = bf_eff[0] | (early_ok & ~wr_bank);         
    assign rdy[1] = bf_eff[1] | (early_ok &  wr_bank);         
    assign go = rd_active ? (blk_done_q & rdy[~rd_bank]) : rdy[rd_bank];                      

    always @(posedge clk) begin                                
        if (!rst_n) begin                                      
            wr_run     <= 1'b0;                                
            wr_bank    <= 1'b0;                                
            rd_bank    <= 1'b0;                                
            rd_active  <= 1'b0;                                
            bank_full  <= 2'b00;                               
            wr_cnt     <= 5'd0;                                
        end else begin                                         
            if (mode_load) wr_run <= 1'b1;                     
            if (wr_done) begin                                 
                wr_run  <= 1'b0;                               
                wr_bank <= ~wr_bank;                           
            end                                                
            if (wr_done) wr_cnt <= 5'd0;                       
            else if (write_enable) wr_cnt <= wr_cnt + 5'd1;    
            bank_full <= bf_eff & ~bf_clr;                     
            if (rd_active) begin                               
                if (blk_done_q) begin                          
                    rd_bank   <= ~rd_bank;                     
                    rd_active <= go;                           
                end                                            
            end else if (go) begin                             
                rd_active <= 1'b1;                             
            end                                                
        end                                                    
    end                                                        
endmodule                                                      
