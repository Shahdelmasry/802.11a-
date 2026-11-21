module second_perm (                                           
    input  wire       clk,                                     
    input  wire       rst_n,                                   
    input  wire       fetch_en,                                
    input  wire [2:0] q,                                       
    input  wire [3:0] col,                                     
    input  wire [1:0] s,                                       
    output reg  [2:0] win_idx,                                 
    output reg        win_we                                   
);                                                             
    reg  [2:0] w;                                              
    reg  [2:0] base;                                           
    reg  [2:0] qm;                                             
    reg  [3:0] cm4;                                            
    reg  [2:0] cm;                                             
    reg  [2:0] rr;                                             

    always @(*) begin                                          
        base = 3'd0;                                           
        qm   = 3'd0;                                           
        cm4  = col % 4'd3;                                     
        cm   = 3'd0;                                           
        rr   = 3'd0;                                           
        case (s)                                               
            2'd2: begin                                        
                base = {q[2:1], 1'b0};                         
                qm   = {2'b00, q[0]};                          
                cm   = {2'b00, col[0]};                        
            end                                                
            2'd3: begin                                        
                base = (q >= 3'd3) ? 3'd3 : 3'd0;              
                qm   = (q >= 3'd3) ? (q - 3'd3) : q;          
                cm   = cm4[2:0];                               
            end                                                
            default: begin                                     
                base = q;                                      
                qm   = 3'd0;                                   
                cm   = 3'd0;                                   
            end                                                
        endcase                                                
        if (qm >= cm) rr = qm - cm;                            
        else          rr = qm + {1'b0, s} - cm;                
        w = base + rr;                                         
    end                                                        

    always @(posedge clk) begin                                
        if (!rst_n) begin                                      
            win_idx <= 3'd0;                                   
            win_we  <= 1'b0;                                   
        end else begin                                         
            win_idx <= w;                                      
            win_we  <= fetch_en;                               
        end                                                    
    end                                                        
endmodule                                                      
