module scr #(
    parameter DATA_LENGTH = 6
) (
    input  wire                         clk,//postive edge clk 
    input  wire                         rst_n,// negtive edge rst (Asynch)
    input  wire   [DATA_LENGTH-1:0]     seq_in, // from memory 
    input  wire   [DATA_LENGTH-1:0]     data_in,//from fsm 
    input  wire                         en,  // from seed to index file   
    output reg   [DATA_LENGTH-1:0]     data_out, // output data that should go to scrambler 
    output reg                         data_vld // that should go to fsm 

    );
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
        begin
            data_out <= {DATA_LENGTH{1'b0}};
            data_vld<= 0;
        end
        else begin
            data_vld<= en;    
            if(en)
                begin
                    for (i = 0; i < DATA_LENGTH; i = i + 1) 
                        begin
                         data_out[i] <= data_in[i]^seq_in[i];
                        end
        end
        end
    end
    
endmodule