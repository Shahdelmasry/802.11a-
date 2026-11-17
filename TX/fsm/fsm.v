module fsm (
    input clk,
    input reset,
    input PHY_TXSTART_req,
	input start_of_data,
	input end_of_data,
	input fifo_data_valid,
	input fifo_header_valid,
	output reg bit_controller_en,
	output reg ifft_start,
	output reg counter_en,
	output reg preamb_mux_en,
	output reg signal_mux_en,
	output reg input_wr_en,
	output reg input_rd_en
);

localparam IDLE = 3'b000;
localparam PREAMBLE = 3'b001;
localparam SIGNAL = 3'b011;
localparam DATA = 3'b111;
localparam IFFT = 3'b110 ;

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
				next_state = PREAMBLE;
			else
				next_state = IDLE;		
		end

		PREAMBLE: begin
			preamb_mux_en = 1'b1; // Enable multiplexer to send preamble
			next_state = SIGNAL;
			if (fifo_header_valid)
				next_state = SIGNAL;
			else
				next_state = PREAMBLE;
		end

		SIGNAL: begin
			signal_mux_en = 1'b1; // Enable multiplexer to send signal field
			if (fifo_data_valid)
				next_state = DATA;
			else
				next_state = SIGNAL;
		end

		DATA: begin
		signal_mux_en = 1'b0; // 
		counter_en = 1'b1; // Enable data counter
		input_wr_en = 1'b1; // Enable input buffer write
		next_state = DATA;
		bit_controller_en = 1'b1; // Enable bit processing controller
		ifft_start <= 1'b1;
		if (end_of_data)
			next_state = IDLE;
		else begin
			next_state = DATA;
		end
		end
		default: next_state = IDLE;
	endcase
end
endmodule
