module mode_register (                                         
    input  wire       clk,                                     
    input  wire       rst_n,                                   
    input  wire [1:0] mode_in,                                 
    input  wire       mode_load,                               
    input  wire       wr_bank,                                 
    input  wire       rd_bank,                                 
    output wire [4:0] wr_rows,                                 
    output wire [1:0] mode_rd,                                 
    output wire [4:0] R,                                       
    output wire [2:0] N_BPSC,                                  
    output wire [1:0] s                                        
);                                                             
    reg  [1:0] mode_bank0;                                     
    reg  [1:0] mode_bank1;                                     
    wire [1:0] mode_wr;                                        

    function [4:0] rows_of;                                    
        input [1:0] m;                                         
        begin                                                  
            case (m)                                           
                2'b00:   rows_of = 5'd3;                       
                2'b01:   rows_of = 5'd6;                       
                2'b10:   rows_of = 5'd12;                      
                default: rows_of = 5'd18;                      
            endcase                                            
        end                                                    
    endfunction                                                

    function [2:0] nbpsc_of;                                   
        input [1:0] m;                                         
        begin                                                  
            case (m)                                           
                2'b00:   nbpsc_of = 3'd1;                      
                2'b01:   nbpsc_of = 3'd2;                      
                2'b10:   nbpsc_of = 3'd4;                      
                default: nbpsc_of = 3'd6;                      
            endcase                                            
        end                                                    
    endfunction                                                

    function [1:0] s_of;                                       
        input [1:0] m;                                         
        begin                                                  
            case (m)                                           
                2'b00:   s_of = 2'd1;                          
                2'b01:   s_of = 2'd1;                          
                2'b10:   s_of = 2'd2;                          
                default: s_of = 2'd3;                          
            endcase                                            
        end                                                    
    endfunction                                                

    assign mode_wr = wr_bank ? mode_bank1 : mode_bank0;        
    assign mode_rd = rd_bank ? mode_bank1 : mode_bank0;        
    assign wr_rows = rows_of(mode_wr);                         
    assign R       = rows_of(mode_rd);                         
    assign N_BPSC  = nbpsc_of(mode_rd);                        
    assign s       = s_of(mode_rd);                            

    always @(posedge clk) begin                                
        if (!rst_n) begin                                      
            mode_bank0 <= 2'b00;                               
            mode_bank1 <= 2'b00;                               
        end else if (mode_load) begin                          
            if (wr_bank) mode_bank1 <= mode_in;                
            else         mode_bank0 <= mode_in;                
        end                                                    
    end                                                        
endmodule                                                      
