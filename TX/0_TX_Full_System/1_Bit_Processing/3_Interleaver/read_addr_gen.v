module read_addr_gen (                                         
    input  wire       clk,                                     
    input  wire       rst_n,                                   
    input  wire       fetch_en,                                
    input  wire [4:0] R,                                       
    input  wire       rd_bank,                                 
    output wire [5:0] read_addr,                               
    output wire [3:0] read_col                                 
);                                                             
    reg  [4:0] row;                                            
    reg  [3:0] col;                                            
    wire       last_row;                                       

    assign last_row  = (row == (R - 5'd1));                    
    assign read_addr = {rd_bank, row};                         
    assign read_col  = col;                                    

    always @(posedge clk) begin                                
        if (!rst_n) begin                                      
            row <= 5'd0;                                       
            col <= 4'd0;                                       
        end else if (fetch_en) begin                           
            if (last_row) begin                                
                row <= 5'd0;                                   
                col <= col + 4'd1;                             
            end else begin                                     
                row <= row + 5'd1;                             
            end                                                
        end                                                    
    end                                                        
endmodule                                                      
