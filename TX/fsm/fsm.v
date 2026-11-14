module fsm (
    input clk,
    input reset,
    input PHY_TXSTART_req,
	input PHY_DATA_req,	
	input start_of_data,
	input end_of_data,
	output reg counter_en,
    output reg PHY_TXSTART_conf,
	output reg PHY_DATA_conf,
	output reg preamb_mux_en,
	output reg signal_mux_en,
	output reg input_wr_en,
	output reg input_rd_en
);


localparam IDLE = 3'b000;
localparam PREAMBLE = 3'b001;
localparam SIGNAL = 3'b011;
localparam DATA = 3'b111;

reg [11:0] data_count;
reg [2:0] current_state, next_state;

always @(posedge clk or posedge reset) begin
	if (reset)
		current_state <= IDLE;
	else
		current_state <= next_state;
end
// Next state logic
always @(*) begin
	preamb_mux_en = 1'b0;
	signal_mux_en = 1'b0;
	counter_en = 1'b0;
	case (current_state)
		IDLE: begin
			if (PHY_TXSTART_req)
			    PHY_TXSTART_conf <= 1;
				next_state = PREAMBLE;
			else
				next_state = IDLE;		
		end

		PREAMBLE: begin
			preamb_mux_en = 1'b1; // Enable multiplexer to send preamble
			next_state = SIGNAL;
		end

		SIGNAL: begin
			signal_mux_en = 1'b1; // Enable multiplexer to send signal field
			next_state = DATA;
		end

		DATA: begin
		if (PHY_DATA_req) begin
			signal_mux_en = 1'b0; // 
			counter_en = 1'b1; // Enable data counter
			input_wr_en = 1'b1; // Enable input buffer write
			PHY_DATA_conf = 1'b1; // Confirm data request
			next_state = DATA;
		end 
		else if (end_of_data)
			next_state = IDLE;
		else begin
			next_state = DATA;
			counter_en = 1'b0;
			input_wr_en = 1'b0;
		end
		end
		//bit processing enable 

		

		default: next_state = IDLE;
	endcase
end
endmodule
