module Memory #(
    parameter DATA_LENGTH = 6
) (
    input  wire                     clk, //postive edge clk 
    input  wire                     rst, //negtive edge rst (Asynch)
    input  wire [6:0]               index, //from 1 to 126 there is a place for 0 but we will never use it. 
    input  wire                     en,   // from (seed to index) file // fsm doesnot need to send it  
    output reg  [DATA_LENGTH-1:0]   data_out // sequance of seed 
);
///////////////memory genration 
    reg rom [0:126];     // a 127 register to hold all possiable sequance 

    initial $readmemb("rom8.mem", rom); //'one time' in the hardware it will be a rom 
   
////////////////updating seq each clk 
  
    integer i;
    integer addr;

    always @(posedge clk or negedge rst) 
    begin
        if (!rst) 
        begin
            data_out <= {DATA_LENGTH{1'b0}};
        end
        else if(en)
        begin
            for (i = 0; i < DATA_LENGTH; i = i + 1) 
            begin
                addr = (index + i) % 127; //to make it wrap around 
                data_out[i] <= rom[addr];
            end
        end
    end

endmodule