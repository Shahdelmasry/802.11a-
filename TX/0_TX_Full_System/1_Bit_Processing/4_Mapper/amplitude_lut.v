module amplitude_lut #(                                        
    parameter W = 16                                           
) (                                                            
    input  wire [1:0]   lut_sel,                               
    input  wire [1:0]   idx_i,                                 
    input  wire [1:0]   idx_q,                                 
    output wire [W-1:0] amp_i,                                 
    output wire [W-1:0] amp_q                                  
);                                                             
    localparam SHL = (W > 16) ? (W - 16) : 0;                  
    localparam SHR = (W < 16) ? (16 - W) : 0;                  

    function [15:0] rom16;                                     
        input [1:0] sel;                                       
        input [1:0] idx;                                       
        begin                                                  
            case ({sel, idx})                                  
                4'b00_00: rom16 = 16'd16384;                   
                4'b01_00: rom16 = 16'd11585;                   
                4'b10_00: rom16 = 16'd5181;                    
                4'b10_01: rom16 = 16'd15543;                   
                4'b11_00: rom16 = 16'd2528;                    
                4'b11_01: rom16 = 16'd7584;                    
                4'b11_10: rom16 = 16'd12641;                   
                4'b11_11: rom16 = 16'd17697;                   
                default:  rom16 = 16'd0;                       
            endcase                                            
        end                                                    
    endfunction                                                

    function [W-1:0] scale;                                    
        input [15:0] c;                                        
        reg   [31:0] t;                                        
        begin                                                  
            t = ({16'd0, c} << SHL) >> SHR;                    
            scale = t[W-1:0];                                  
        end                                                    
    endfunction                                                

    assign amp_i = scale(rom16(lut_sel, idx_i));               
    assign amp_q = scale(rom16(lut_sel, idx_q));               
endmodule                                                      
