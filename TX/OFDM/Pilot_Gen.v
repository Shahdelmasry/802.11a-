module Pilot_Gen 
 (
    input                clk,
    input                rst,
    input                sym_advance,
    output signed [1:0]  pilot_out
 );
    localparam seed= 7'h7f ;
    reg [6:0] lfsr;
    wire feedback;

    
    assign feedback = lfsr[6] ^ lfsr[3] ;
    assign pilot_out = feedback ? 2'b11 : 2'b01;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lfsr <= seed;
        end else if (sym_advance) begin
            lfsr <= {lfsr[5:0], feedback};
        end
    end

endmodule //Pilot_Gen