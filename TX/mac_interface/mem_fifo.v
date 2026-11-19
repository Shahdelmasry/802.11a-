module mem_fifo #(
    parameter word = 8,
    parameter input_data =6,
    parameter depth=(1<<input_data)
) (
    input    wire                    clk,//mac clk 
    input    wire                    rst,
    input    wire                    wen,
    input    wire                    full,
    input    wire   [word-1:0]       data_in,
    input    wire   [input_data-1:0] address_in,
    input    wire   [input_data-1:0] address_out,
    output   wire   [word-1:0]       data_out

) ;

// memory 8*64
    reg[word-1:0] mem [0:depth-1];
integer  i;
//write 
    always @(posedge clk or negedge rst ) 
    begin
        if (!rst) 
            begin
                for(i=0;i<depth;i=i+1) 
                mem[i] <= {word{1'b0}} ;
            end 
        else if (wen && !full)  
            begin
                mem[address_in] <= data_in;
            end 
    end
//read 
assign data_out=mem[address_out];
    
endmodule