
module Circuit_Switch (
    input  wire [2:0] coeff_sel,
    input  wire       swap,

    output reg signed [15:0] coeff_i,
    output reg signed [15:0] coeff_q
);

    reg signed [15:0] selected_i;
    reg signed [15:0] selected_q;

    always @(*) begin
        selected_i = 16'sd0;
        selected_q = 16'sd0;

        case (coeff_sel)
            3'd0: begin
                selected_i = 16'h7F62; // i8
                selected_q = 16'h0C8C; // q8
            end

            3'd1: begin
                selected_i = 16'h7D8A; // i7
                selected_q = 16'h18F9; // q7
            end

            3'd2: begin
                selected_i = 16'h7A7D; // i6
                selected_q = 16'h2528; // q6
            end

            3'd3: begin
                selected_i = 16'h7642; // i5
                selected_q = 16'h30FC; // q5
            end

            3'd4: begin
                selected_i = 16'h70E3; // i4
                selected_q = 16'h3C57; // q4
            end

            3'd5: begin
                selected_i = 16'h6A6E; // i3
                selected_q = 16'h471D; // q3
            end

            3'd6: begin
                selected_i = 16'h62F2; // i2
                selected_q = 16'h5134; // q2
            end

            3'd7: begin
                selected_i = 16'h5A82; // i1
                selected_q = 16'h5A82; // q1
            end

            default: begin
                selected_i = 16'sd0;
                selected_q = 16'sd0;
            end
        endcase

        if (swap) begin
            coeff_i = selected_q;
            coeff_q = selected_i;
        end
        else begin
            coeff_i = selected_i;
            coeff_q = selected_q;
        end
    end

endmodule
