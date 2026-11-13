module signal_field_generation (
    input clk,
    input rst,
    input [34:0] TXVECTOR,
	output reg [3:0] rate,
	output reg [11:0] Length,
    output reg [2:0] powerlevel,
	output reg [8:0] ndbps,
    output reg [23:0] Signal
);
    reg mode; // coding rate  mode : 0 --> r = 1/2, 1 --> r = 3/4, 2 --> r = 2/3
    wire Parity;
	assign Parity = ^{Rate, 1'b0, Length};
        always@(posedge clk or posedge reset) begin
        if (reset)
           Signal<=0;
        else begin
				Length <= TXVECTOR[34:23];
				rate <= TXVECTOR[22:19];
				case(TXVECTOR[22:19])
					4'b1011: begin rate = 6;  mode <= 0; ndbps = 9'd24;  end
					4'b1111: begin rate = 9;  mode <= 1; ndbps = 9'd36;  end
					4'b1010: begin rate = 12; mode <= 0; ndbps = 9'd48;  end
					4'b1110: begin rate = 18; mode <= 1; ndbps = 9'd72;  end
					4'b1001: begin rate = 24; mode <= 0; ndbps = 9'd96;  end
					4'b1101: begin rate = 36; mode <= 1; ndbps = 9'd144; end
					4'b1000: begin rate = 48; mode <= 2; ndbps = 9'd192; end
					4'b1100: begin rate = 54; mode <= 1; ndbps = 9'd216; end
					default: begin rate = 6;  mode <= 0; ndbps = 9'd24;  end
				endcase
				Service <= TXVECTOR[18:3];
				PowerLevel <= TXVECTOR[2:0];
            Signal <= {6'd0, Parity, Length, 1'b0, rate};
            end
        end
endmodule
