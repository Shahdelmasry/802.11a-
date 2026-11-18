


module Reconfigurable_Complex_Multiplier
(
    input wire clk,
    input wire en,

    input wire signed [15:0] I_in,
    input wire signed [15:0] Q_in,

    input wire s1,              // before R2
    input wire s2,              // before R2
    input wire s3,              // after R2
    input wire s4,              // after R2
    input wire s5,              // after R2

    input wire signed [15:0] coeff_i,
    input wire signed [15:0] coeff_q,

    output wire signed [15:0] I_out,
    output wire signed [15:0] Q_out
);

    // ----------------------------------------
    // Input MUXes - s1
    // ----------------------------------------

    wire signed [15:0] I_mux;
    wire signed [15:0] Q_mux;

    assign I_mux = s1 ? Q_in : I_in;
    assign Q_mux = s1 ? I_in : Q_in;


    // ----------------------------------------
    // Input Negation - s2
    // ----------------------------------------

    wire signed [15:0] I_prime;
    wire signed [15:0] Q_prime;

    assign I_prime = I_mux;
    assign Q_prime = s2 ? -Q_mux : Q_mux;


    // ----------------------------------------
    // Fig. 9 Complex Multiplier
    // ----------------------------------------

    wire signed [15:0] I_cm;
    wire signed [15:0] Q_cm;

    Complex_Multiplier U_CM
    (
        .clk      (clk),
        .en       (en),
        .I_in     (I_prime),
        .Q_in     (Q_prime),
        .coeff_i  (coeff_i),
        .coeff_q  (coeff_q),
        .I_out    (I_cm),
        .Q_out    (Q_cm)
    );


    // ----------------------------------------
    // Bypass Register (R2, aligned with the products)
    // ----------------------------------------

    reg signed [15:0] I_prime_r;
    reg signed [15:0] Q_prime_r;

    always @(posedge clk) begin
        if (en) begin
            I_prime_r <= I_prime;
            Q_prime_r <= Q_prime;
        end
    end


    // ----------------------------------------
    // Output MUXes - s3
    // ----------------------------------------

    wire signed [15:0] I_mux_out;
    wire signed [15:0] Q_mux_out;

    assign I_mux_out = s3 ? I_cm : I_prime_r;
    assign Q_mux_out = s3 ? Q_cm : Q_prime_r;


    // ----------------------------------------
    // Output Negation - s4 and s5
    // ----------------------------------------

    assign I_out = s4 ? -I_mux_out : I_mux_out;
    assign Q_out = s5 ? -Q_mux_out : Q_mux_out;

endmodule
