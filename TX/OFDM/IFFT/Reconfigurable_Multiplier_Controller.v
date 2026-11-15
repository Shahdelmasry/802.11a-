
module Reconfigurable_Multiplier_Controller (
    input  wire [2:0] operation_type,

    output reg  s1,
    output reg  s2,
    output reg  s3,
    output reg  s4,
    output reg  s5,

    output reg  valid_operation
);

    always @(*) begin
        // Safe defaults
        s1 = 1'b0;
        s2 = 1'b0;
        s3 = 1'b0;
        s4 = 1'b0;
        s5 = 1'b0;
        valid_operation = 1'b1;

        case (operation_type)

            // Type 1: P = W^m (b - ja)
            3'd1: begin
                s1 = 1'b1;
                s2 = 1'b1;
                s3 = 1'b1;
                s4 = 1'b0;
                s5 = 1'b0;
            end

            // Type 2: -P = -W^m (a + jb)
            3'd2: begin
                s1 = 1'b0;
                s2 = 1'b0;
                s3 = 1'b1;
                s4 = 1'b1;
                s5 = 1'b1;
            end

            // Type 3: -P = -W^m (b - ja)
            3'd3: begin
                s1 = 1'b1;
                s2 = 1'b1;
                s3 = 1'b1;
                s4 = 1'b1;
                s5 = 1'b1;
            end

            // Type 4: P* = [W^m (b + ja)]*
            3'd4: begin
                s1 = 1'b1;
                s2 = 1'b0;
                s3 = 1'b1;
                s4 = 1'b0;
                s5 = 1'b1;
            end

            // Type 5: -P* = -X + jY
            3'd5: begin
                s1 = 1'b0;
                s2 = 1'b1;
                s3 = 1'b1;
                s4 = 1'b1;
                s5 = 1'b0;
            end
                        // Type 6: -j * (a + jb) = b - ja, no multiplication
            3'd6: begin
                s1 = 1'b1;
                s2 = 1'b1;
                s3 = 1'b0;
                s4 = 1'b0;
                s5 = 1'b0;
            end

            default: begin
                s1 = 1'b0;
                s2 = 1'b0;
                s3 = 1'b0;
                s4 = 1'b0;
                s5 = 1'b0;
                valid_operation = 1'b0;
            end

        endcase
    end

endmodule
