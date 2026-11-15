
module Twiddle_Mapper (
    input  wire [5:0] k,

    output reg  [2:0] operation_type,
    output reg  [2:0] coeff_sel,
    output reg        swap,

    output reg  [4:0] reduced_m,
    output reg  [2:0] special_sel,

    output reg        multiplier_enable,
    output reg        valid
);

    always @(*) begin
        operation_type    = 3'd0;
        coeff_sel         = 3'd0;
        swap              = 1'b0;
        reduced_m         = 5'd0;
        special_sel       = 3'd0;
        multiplier_enable = 1'b0;
        valid             = 1'b0;

        case (k)
            6'd0: begin
                special_sel = 3'd1; // Unity
                valid = 1'b1;
            end

             6'd16: begin
                operation_type = 3'd6; // -j, done by RCM with s3 = 0
                valid = 1'b1;
            end

            6'd32: begin
                special_sel = 3'd3; // -1
                valid = 1'b1;
            end

            6'd48: begin
                special_sel = 3'd4; // +j
                valid = 1'b1;
            end

            default: begin
                if ((k >= 1) && (k <= 15)) begin
                    operation_type = 3'd4;
                    reduced_m = 16 - k;
                    valid = 1'b1;
                end
                else if ((k >= 17) && (k <= 24)) begin
                    operation_type = 3'd1;
                    reduced_m = k - 16;
                    valid = 1'b1;
                end
                else if ((k >= 25) && (k <= 31)) begin
                    operation_type = 3'd5;
                    reduced_m = 32 - k;
                    valid = 1'b1;
                end
                else if ((k >= 33) && (k <= 47)) begin
                    operation_type = 3'd2;
                    reduced_m = k - 32;
                    valid = 1'b1;
                end
                else if ((k >= 49) && (k <= 63)) begin
                    operation_type = 3'd3;
                    reduced_m = k - 48;
                    valid = 1'b1;
                end
            end
        endcase

        // Coefficient mapping:
        // Circuit_Switch: coeff_sel 0 -> coefficient 8
        //                coeff_sel 7 -> coefficient 1
               if (valid && (operation_type != 3'd0)) begin
            multiplier_enable = 1'b1;

            if (operation_type != 3'd6) begin
                if (reduced_m <= 8) begin
                    coeff_sel = reduced_m - 1'b1;
                    swap = 1'b0;
                end
                else begin
                    coeff_sel = 5'd15 - reduced_m;
                    swap = 1'b1;
                end
            end
        end
    end

endmodule
