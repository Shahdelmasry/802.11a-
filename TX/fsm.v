module fsm (
    input clk,
    input reset,
    input PHY_TXSTART_req,
    input inputData,
    input [34:0] TXVECTOR,
    output reg PHY_TXSTART_conf,
);
    reg [3:0] 	 Rate;
	reg [11:0] 	 Length;
	reg [23:0] 	 Signal;
	reg [15:0] 	 Service;
	reg [2:0] 	 PowerLevel;
	reg [29:0] 	 Preamble; 
    reg mode; // coding rate  mode : 0 --> r = 1/2, 1 --> r = 3/4, 2 --> r = 2/3
    wire Parity;
	assign Parity = ^{Rate, 1'b0, Length};

    always@(posedge clk or posedge reset) begin
        if (reset) begin
            PHY_TXSTART_conf <= 0;
        end else begin
            if(PHY_TXSTART_req)	// PHY_TXSTART_req become unasserted after PHY_TXSTART_conf
			begin
				Length <= TXVECTOR[34:23];
				Rate <= TXVECTOR[22:19];
				
				case(TXVECTOR[22:19])
					4'b1011: begin rate = 6; mode <= 0; end
					4'b1111: begin rate = 9; mode <= 1; end
					4'b1010: begin rate = 12; mode <= 0; end
					4'b1110: begin rate = 18; mode <= 1; end
					4'b1001: begin rate = 24; mode <= 0; end
					4'b1101: begin rate = 36; mode <= 1; end
					4'b1000: begin rate = 48; mode <= 2; end
					4'b1100: begin rate = 54; mode <= 1; end
					default: begin rate = 6; mode <= 0; end
				endcase
				
				Service <= TXVECTOR[18:3];
				PowerLevel <= TXVECTOR[2:0];
                Signal <= {6'd0, Parity, Length, 1'b0, Rate}; 
                PHY_TXSTART_conf <= 1;
            end
        end
    end
endmodule
