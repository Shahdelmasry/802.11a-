module Pilot_Gen 
 (
    input                clk,
    input                rst,
    input                start,
    input                sym_advance,
    output signed [1:0]  pilot_out
 );
    localparam seed= 7'h7f ;
    reg [6:0] lfsr;
    wire feedback;

    
    assign feedback = lfsr[6] ^ lfsr[3] ;
    assign pilot_out = feedback ? 2'b11 : 2'b01;

    // start (new packet) reloads the all-ones seed so that every packet
    // begins with p0. start has priority over sym_advance.
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            lfsr <= seed;
        end else if (start) begin
            lfsr <= seed;
        end else if (sym_advance) begin
            lfsr <= {lfsr[5:0], feedback};
        end
    end

endmodule //Pilot_Gen 
