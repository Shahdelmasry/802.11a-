module interleaver_top_cnt #(                                  
    parameter EARLY_ROWS   = 10,                               
    parameter EARLY_ROWS12 = 6                                 
) (                                                            
    input  wire        clk,                                    
    input  wire        rst_n,                                  
    input  wire [15:0] data_in,                                
    input  wire        valid_in,                               
    input  wire [4:0]  in_cnt,                                 
    input  wire        start,                                  
    input  wire [1:0]  mode_in,                                
    output wire        in_ready,                               
    output wire        busy,                                   
    output wire [5:0]  sym_bits,                               
    output wire        sym_valid,                              
    output wire        sym_last,                               
    output wire [1:0]  sym_mode                                
);                                                             
    wire        wr_run;                                        
    wire        wr_bank;                                       
    wire [4:0]  wr_rows;                                       
    wire        wr_done;                                       
    wire        mode_load;                                     
    wire        write_enable;                                  
    wire [5:0]  write_addr;                                    
    wire [15:0] write_data;                                    
    wire [5:0]  read_addr;                                     
    wire [3:0]  read_col;                                      
    wire        read_bit;                                      
    wire [2:0]  q;                                             
    wire [2:0]  win_idx;                                       
    wire        win_we;                                        
    wire        fetch_en;                                      
    wire        go;                                            
    wire        rd_bank;                                       
    wire        rd_active;                                     
    wire        blk_done;                                      
    wire [1:0]  bank_full;                                     
    wire [4:0]  R;                                             
    wire [2:0]  N_BPSC;                                        
    wire [1:0]  s;                                             
    wire [1:0]  mode_rd;                                       
    wire        pipe_busy;                                     

    assign busy = mode_load | wr_run | rd_active | (|bank_full) | pipe_busy; 

    wire [4:0]  wr_cnt;                                        
    main_fsm #(.EARLY_ROWS(EARLY_ROWS), .EARLY_ROWS12(EARLY_ROWS12)) u_main_fsm (           
        .clk       (clk),                                      
        .rst_n     (rst_n),                                    
        .start     (start),                                    
        .wr_done   (wr_done),                                  
        .blk_done  (blk_done),                                 
        .write_enable (write_enable),                          
        .wr_rows   (wr_rows),                                  
        .wr_cnt    (wr_cnt),                                   
        .wr_run    (wr_run),                                   
        .wr_bank   (wr_bank),                                  
        .mode_load (mode_load),                                
        .in_ready  (in_ready),                                 
        .go        (go),                                       
        .rd_bank   (rd_bank),                                  
        .rd_active (rd_active),                                
        .bank_full (bank_full)                                 
    );                                                         

    mode_register u_mode_register (                            
        .clk       (clk),                                      
        .rst_n     (rst_n),                                    
        .mode_in   (mode_in),                                  
        .mode_load (mode_load),                                
        .wr_bank   (wr_bank),                                  
        .rd_bank   (rd_bank),                                  
        .wr_rows   (wr_rows),                                  
        .mode_rd   (mode_rd),                                  
        .R         (R),                                        
        .N_BPSC    (N_BPSC),                                   
        .s         (s)                                         
    );                                                         

    write_controller u_write_controller (                      
        .clk          (clk),                                   
        .rst_n        (rst_n),                                 
        .wr_run       (wr_run),                                
        .wr_bank      (wr_bank),                               
        .wr_rows      (wr_rows),                               
        .valid_in     (valid_in),                              
        .in_cnt       (in_cnt),                                
        .data_in      (data_in),                               
        .write_enable (write_enable),                          
        .write_addr   (write_addr),                            
        .write_data   (write_data),                            
        .wr_done      (wr_done)                                
    );                                                         

    matrix_memory u_matrix_memory (                            
        .clk          (clk),                                   
        .write_enable (write_enable),                          
        .write_addr   (write_addr),                            
        .write_data   (write_data),                            
        .read_addr    (read_addr),                             
        .read_col     (read_col),                              
        .read_bit     (read_bit)                               
    );                                                         

    slot_counters u_slot_counters (                            
        .clk       (clk),                                      
        .rst_n     (rst_n),                                    
        .go        (go),                                       
        .N_BPSC    (N_BPSC),                                   
        .q         (q),                                        
        .fetch_en  (fetch_en),                                 
        .blk_done  (blk_done),                                 
        .sym_valid (sym_valid),                                
        .sym_last  (sym_last),                                 
        .pipe_busy (pipe_busy)                                 
    );                                                         

    read_addr_gen u_read_addr_gen (                            
        .clk       (clk),                                      
        .rst_n     (rst_n),                                    
        .fetch_en  (fetch_en),                                 
        .R         (R),                                        
        .rd_bank   (rd_bank),                                  
        .read_addr (read_addr),                                
        .read_col  (read_col)                                  
    );                                                         

    second_perm u_second_perm (                                
        .clk      (clk),                                       
        .rst_n    (rst_n),                                     
        .fetch_en (fetch_en),                                  
        .q        (q),                                         
        .col      (read_col),                                  
        .s        (s),                                         
        .win_idx  (win_idx),                                   
        .win_we   (win_we)                                     
    );                                                         

    symbol_assembler u_symbol_assembler (                      
        .clk          (clk),                                   
        .rst_n        (rst_n),                                 
        .read_bit     (read_bit),                              
        .win_idx      (win_idx),                               
        .win_we       (win_we),                                
        .sym_valid_in (sym_valid),                             
        .mode_rd      (mode_rd),                               
        .sym_bits     (sym_bits),                              
        .sym_mode     (sym_mode)                               
    );                                                         
endmodule                                                      
