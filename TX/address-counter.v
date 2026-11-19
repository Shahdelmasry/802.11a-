module address_counter (
    input clk,rst,
    input en,
    output add_count
);
always @(posedge clk or negedge rst) begin 
    if (!rst) 
        add_count<=0;
    else if (add_count == 319)
        add_count<=0;
    else 
        add_count <= add_count+1;

end 
    
endmodule