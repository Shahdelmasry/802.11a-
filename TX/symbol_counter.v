module symbol_counter (
    input clk,
    input rst,
    input [15:0] nsym,
    input symbol_valid,
    input last_valid,
    input mapper_capture_ready,
    output last_sym
);
reg counter = 0;
always @(posedge clk or negedge rst ) begin
    if (!rst) begin 
        counter <=0;
        last_sym <=0;
    end
    else if (symbol_valid && last_valid && mapper_capture_ready ) begin 
            if (counter == nsym) begin
                last_sym <= 1;
                counter <= 0;
            end 
        else 
            counter <= counter +1 ; 
    end
          
end

endmodule