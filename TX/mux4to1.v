module mux4to1 (
    input [5:0] mux1,mux2,mux3,mux4;
    input[1:0] sel,
    output reg [5:0] muxout
);
always@(*) begin 
    case (sel) 
    00 : muxout = mux1; 
    01 : muxout = mux2;  
    10 : muxout = mux3; 
    11 : muxout = mux4; 
    default : muxout = mux1;  
    endcase
end
endmodule