module enc_adapter (                                           
    input  wire [1:0]  rate_sel,                               
    input  wire [11:0] data_out,                               
    input  wire [8:0]  data_out_23,                            
    input  wire [7:0]  data_out_34,                            
    output reg  [15:0] wc_data,                                
    output reg  [4:0]  wc_cnt                                  
);                                                             
    always @(*) begin                                          
        case (rate_sel)                                        
            2'd0:    begin wc_data = {4'd0, data_out};      wc_cnt = 5'd12; end 
            2'd1:    begin wc_data = {7'd0, data_out_23};   wc_cnt = 5'd9;  end 
            2'd2:    begin wc_data = {8'd0, data_out_34};   wc_cnt = 5'd8;  end 
            default: begin wc_data = 16'd0;                 wc_cnt = 5'd0;  end 
        endcase                                                
    end                                                        
endmodule                                                      
