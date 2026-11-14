module data_counter (
    input clk,
    input reset,
    input enable,
    input [11:0] Length,
    output reg start_of_data,
    output reg end_of_data,
    output reg [11:0] data_count
);
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            data_count <= 12'd0;
        end else if (enable) begin
           if (data_count == Length - 1) begin
			end_of_data = 1'b1;
            data_count <= 12'd0; // Reset counter after reaching Length
            end else begin
			start_of_data = (data_count == 0) ? 1'b1 : 1'b0;
            end
        end
    end

endmodule
