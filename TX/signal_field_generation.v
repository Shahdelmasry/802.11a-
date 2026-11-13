module input_controller 
   
    input [7:0] data_in, // data octets
    input clk, // 80 MHz master clock
    input rst_n, // Active-low reset
    input enable, // Controller enable (from top-level FSM)
    input [3:0] rate,
    input [11:0] length,
    input [8:0] ndbps,
    output reg [5:0] data_out // to scrambler (with length = 6)
);
  
 always@(posedge clk or negedge rst_n) begin
    if (!rst_n)
        input_reg <= 0;
    else if (!enable)
        input_reg <= 0;
    else
        input_reg <= data_in[5:0];
    end
    reg [8:0] ndbps;

    

   


    
endmodule