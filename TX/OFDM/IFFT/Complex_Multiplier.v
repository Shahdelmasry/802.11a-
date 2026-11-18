
// - Pipeline register R2 on the three products P1, P2, P3, loaded when en = 1
module Complex_Multiplier
(
    input  wire               clk,
    input  wire               en,

    input  wire signed [15:0] I_in,
    input  wire signed [15:0] Q_in,

    input  wire signed [15:0] coeff_i,
    input  wire signed [15:0] coeff_q,

    output wire signed [15:0] I_out,
    output wire signed [15:0] Q_out
);

//------------------------------------------------
// Input Adders
//------------------------------------------------

wire signed [16:0] I_plus_Q;
wire signed [16:0] I_minus_Q;

assign I_plus_Q =
    {I_in[15], I_in} + {Q_in[15], Q_in};

assign I_minus_Q =
    {I_in[15], I_in} - {Q_in[15], Q_in};

//------------------------------------------------
// Coefficient Adder
//------------------------------------------------

wire signed [16:0] coeff_diff;

assign coeff_diff =
    {coeff_i[15], coeff_i} -
    {coeff_q[15], coeff_q};

//------------------------------------------------
// Three Real Multipliers
//------------------------------------------------

wire signed [32:0] P1_comb;
wire signed [32:0] P2_comb;
wire signed [32:0] P3_comb;

assign P1_comb = I_plus_Q  * coeff_i;
assign P2_comb = Q_in      * coeff_diff;
assign P3_comb = I_minus_Q * coeff_q;

//------------------------------------------------
// Product Registers (R2)
//------------------------------------------------

reg signed [32:0] P1;
reg signed [32:0] P2;
reg signed [32:0] P3;

always @(posedge clk) begin
    if (en) begin
        P1 <= P1_comb;
        P2 <= P2_comb;
        P3 <= P3_comb;
    end
end

//------------------------------------------------
// Output Adders
//------------------------------------------------

wire signed [33:0] I_sum;
wire signed [33:0] Q_diff;

assign I_sum =
    {P1[32], P1} - {P2[32], P2};

assign Q_diff =
    {P2[32], P2} - {P3[32], P3};

//------------------------------------------------
// Rounding: Q1.15
// Product fractional width = 30
// Output fractional width  = 15
// Shift right by 15
// Round to nearest, ties away from zero
//------------------------------------------------

wire signed [33:0] I_rounded;
wire signed [33:0] Q_rounded;

assign I_rounded =
    I_sum + (I_sum >= 0 ? 34'sd16384 : 34'sd16383);

assign Q_rounded =
    Q_diff + (Q_diff >= 0 ? 34'sd16384 : 34'sd16383);

//------------------------------------------------
// Fixed-point Scaling
//------------------------------------------------

wire signed [33:0] I_scaled;
wire signed [33:0] Q_scaled;

assign I_scaled = I_rounded >>> 15;
assign Q_scaled = Q_rounded >>> 15;

//------------------------------------------------
// Saturation to signed 16-bit
//------------------------------------------------

assign I_out =
    (I_scaled > 34'sd32767)  ? 16'sh7FFF :
    (I_scaled < -34'sd32768) ? 16'sh8000 :
                               I_scaled[15:0];

assign Q_out =
    (Q_scaled > 34'sd32767)  ? 16'sh7FFF :
    (Q_scaled < -34'sd32768) ? 16'sh8000 :
                               Q_scaled[15:0];

endmodule
