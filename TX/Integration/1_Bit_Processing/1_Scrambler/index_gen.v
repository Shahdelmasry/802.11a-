
module seed_gen #(
    parameter [6:0] INIT = 7'h7F          // reset value of the LFSR, must not be 0
) (
    input  wire       clk,                // postive edge clk
    input  wire       rst_n,                // negtive edge rst_n (Async)
    input  wire       start,              // 1 clk pulse: a new packet starts, capture a new seed
    output reg  [6:0] seed                // seed of the current packet (never 0)
);
    localparam [6:0] INIT_SAFE = (INIT == 7'd0) ? 7'h7F : INIT;   // protect against the lock-up state

    reg [6:0] lfsr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr <= INIT_SAFE;
            seed <= INIT_SAFE;
        end else begin
            lfsr <= {lfsr[5:0], lfsr[6] ^ lfsr[3]};   // keeps running every clock
            if (start) seed <= lfsr;                  // capture only at the start of a packet
        end
    end
endmodule
