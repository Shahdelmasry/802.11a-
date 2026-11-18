module Twiddle_Sequencer #(
    parameter PHASE_OFFSET = 8
)(
    input  wire [5:0] sample_count,

    output wire [5:0] twiddle_k,
    output wire       multiplier_enable,
    output wire [2:0] group_r,
    output wire [2:0] index_n
);

    wire [5:0] phase_count;

    // Stage-3 output position = count + 8 (mod 64)
    assign phase_count = sample_count + PHASE_OFFSET;

    // Group index is bit-reversed after the first 3 stages
    assign group_r = {phase_count[3], phase_count[4], phase_count[5]};
    assign index_n = phase_count[2:0];

    // k = r*n (max 49, no modulo needed)
    assign twiddle_k = group_r * index_n;

    // Bypass when r=0 or n=0
    assign multiplier_enable = (group_r != 3'd0) && (index_n != 3'd0);

endmodule