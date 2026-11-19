module signal_field_generation (
    input clk,
    input rst,
	input [3:0] rate,
	input [11:0] Length,
    input [2:0] powerlevel,
	output reg [8:0] ndbps,
	output reg [1:0] coding_rate, // coding rate  codig_rate : 0 --> r = 1/2, 1 --> r = 2/3, 2 --> r = 3/4
	output reg [1:0] modulation, //   00 BPSK    01 QPSK    10 16-QAM   11 64-QAM
    output reg [5:0] Signal1,
	output reg [5:0] Signal2,
	output reg [5:0] Signal3,
	output reg [5:0] Signal4
);
    wire Parity;
	reg [23:0] Signal,
	assign Parity = ^{Rate, 1'b0, Length};
        always@(posedge clk or negedge reset) begin
        if (!rst)
           Signal<=0;
        else begin
				Length <= TXVECTOR[34:23];
				rate <= TXVECTOR[22:19];
				case(TXVECTOR[22:19])
					4'b1011: begin rate = 6;  codig_rate <= 0; ndbps = 9'd24;  modulation = 2'b00; end
					4'b1111: begin rate = 9;  codig_rate <= 2; ndbps = 9'd36;  modulation = 2'b00; end
					4'b1010: begin rate = 12; codig_rate <= 0; ndbps = 9'd48;  modulation = 2'b01; end
					4'b1110: begin rate = 18; codig_rate <= 2; ndbps = 9'd72;  modulation = 2'b01; end
					4'b1001: begin rate = 24; codig_rate <= 0; ndbps = 9'd96;  modulation = 2'b10; end
					4'b1101: begin rate = 36; codig_rate <= 2; ndbps = 9'd144; modulation = 2'b10; end
					4'b1000: begin rate = 48; codig_rate <= 1; ndbps = 9'd192; modulation = 2'b11; end
					4'b1100: begin rate = 54; codig_rate <= 2; ndbps = 9'd216; modulation = 2'b11; end
					default: begin rate = 6;  codig_rate <= 0; ndbps = 9'd24;  modulation = 2'b00; end
				endcase
				Service <= TXVECTOR[18:3];
				PowerLevel <= TXVECTOR[2:0];
            Signal <= {6'd0, Parity, Length, 1'b0, rate};
            end
        end
		assign Signal1 = Signal[5:0],
		assign Signal2 = Signal[11:6],
		assign Signal3 = Signal[17:12],
		assign Signal4 = Signal[23:18]

endmodule
