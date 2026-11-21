module write_controller (                                      
    input  wire        clk,                                    
    input  wire        rst_n,                                  
    input  wire        wr_run,                                 
    input  wire        wr_bank,                                
    input  wire [4:0]  wr_rows,                                
    input  wire        valid_in,                               
    input  wire [4:0]  in_cnt,                                 
    input  wire [15:0] data_in,                                
    output wire        write_enable,                           
    output wire [5:0]  write_addr,                             
    output wire [15:0] write_data,                             
    output wire        wr_done                                 
);                                                             
    reg  [4:0]  wr_row;                                        
    reg  [15:0] part_buf;                                      
    reg  [3:0]  fill;                                          

    wire        take    = wr_run & valid_in;                   
    wire [4:0]  cnt_c   = (in_cnt > 5'd16) ? 5'd16 : in_cnt;   
    wire [4:0]  cnt_u   = take ? cnt_c : 5'd0;                 
    wire [31:0] mask    = (32'd1 << cnt_u) - 32'd1;            
    wire [31:0] acc     = {16'd0, part_buf} | (({16'd0, data_in} & mask) << fill); 
    wire [5:0]  total   = {2'd0, fill} + {1'b0, cnt_u};        
    wire        full    = (total >= 6'd16);                    

    assign write_enable = take & full;                         
    assign write_addr   = {wr_bank, wr_row};                   
    assign write_data   = acc[15:0];                           
    assign wr_done      = write_enable & (wr_row == (wr_rows - 5'd1)); 

    always @(posedge clk) begin                                
        if (!rst_n) begin                                      
            wr_row     <= 5'd0;                                
            part_buf   <= 16'd0;                               
            fill       <= 4'd0;                                
        end else begin                                         
            if (wr_done) begin                                 
                wr_row   <= 5'd0;                              
                part_buf <= 16'd0;                             
                fill     <= 4'd0;                              
            end else if (write_enable) begin                   
                wr_row   <= wr_row + 5'd1;                     
                part_buf <= acc[31:16];                        
                fill     <= total[3:0];                        
            end else if (take) begin                           
                part_buf <= acc[15:0];                         
                fill     <= total[3:0];                        
            end                                                
        end                                                    
    end                                                        
endmodule                                                      
