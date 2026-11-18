// symbol_output.v - "Symbol Output"
// The single register stage of the Mapper: X = I + jQ is registered together
// with valid_out and last_out, so valid_out = sym_valid delayed by ONE cycle.
// complex_symbol_out = {Q, I}  (Q in the upper W bits, I in the lower W bits).
// The data register is loaded only when sym_valid is high.
//------------------------------------------------------------------------------
module symbol_output #(                                        // begin module declaration with parameter
    parameter W = 16                                           // width of I and Q
) (                                                            // begin port list
    input  wire           clk,                                 // 80 MHz master clock
    input  wire           rst_n,                               // active-low synchronous reset
    input  wire [W-1:0]   I,                                   // signed I value (combinational)
    input  wire [W-1:0]   Q,                                   // signed Q value (combinational)
    input  wire           sym_valid,                           // symbol strobe from the Interleaver
    input  wire           sym_last,                            // last symbol of the OFDM symbol
    output reg  [2*W-1:0] complex_symbol_out,                  // registered {Q, I}
    output reg            valid_out,                           // complex_symbol_out is valid
    output reg            last_out                             // symbol 47 of the OFDM symbol
);                                                             // end of port list
    always @(posedge clk) begin                                // clocked process: output register
        if (!rst_n) begin                                      // synchronous reset asserted
            complex_symbol_out <= {2*W{1'b0}};                 // clear data
            valid_out          <= 1'b0;                        // no valid symbol
            last_out           <= 1'b0;                        // no last flag
        end else begin                                         // normal operation
            valid_out <= sym_valid;                            // strobe delayed by one cycle
            last_out  <= sym_valid & sym_last;                 // last flag only together with a valid symbol
            if (sym_valid) complex_symbol_out <= {I, Q};       // load the symbol when it is valid
        end                                                    // end of reset/normal branch
    end                                                        // end of clocked process
endmodule                                                      // end of symbol_output
