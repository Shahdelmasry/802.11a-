module matrix_memory (                                         
    input  wire        clk,                                    
    input  wire        write_enable,                           
    input  wire [5:0]  write_addr,                             
    input  wire [15:0] write_data,                             
    input  wire [5:0]  read_addr,                              
    input  wire [3:0]  read_col,                               
    output wire        read_bit                                
);                                                             
    reg  [15:0] mem [0:63];                                    
    wire [15:0] row_word;                                      

    always @(posedge clk) begin                                
        if (write_enable) mem[write_addr] <= write_data;       
    end                                                        

    assign row_word = mem[read_addr];                          
    assign read_bit = row_word[read_col];                      
endmodule                                                      
