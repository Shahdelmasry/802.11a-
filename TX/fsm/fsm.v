module fsm (
    input clk,
    input reset,
    input PHY_TXSTART_req,
	input PHY_DATA_req,	
    output reg PHY_TXSTART_conf,
	output reg PHY_DATA_conf,
	output reg mux_en,
	output reg start_of_data,
	output reg end_of_data,
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
	start_of_data = 1'b0;
	end_of_data = 1'b0;
	case (current_state)
		IDLE: begin
			if (PHY_TXSTART_req)
				next_state = PREAMBLE;
			else
				next_state = IDLE;		
		end

		PREAMBLE: begin
			mux_en = 1'b1; // Enable multiplexer to send preamble
			next_state = SIGNAL;
		end

		SIGNAL: begin
			// One cycle to send signal field

			next_state = DATA;
		end

		DATA: begin
		// Stay in DATA state until all data is sent based on the length field
		if (data_count == Length - 1) begin
			end_of_data = 1'b1;
			next_state = IDLE;
		end else begin
			start_of_data = (data_count == 0) ? 1'b1 : 1'b0;
			next_state = DATA;
		end
		//bit processing enable 

		end

		default: next_state = IDLE;
	endcase
end
// octet counter for data field
always @(posedge clk or posedge reset) begin
	input_wr_en<=0;
	if (!reset)
		data_count <= 12'd0;
	else if (current_state == DATA) begin
		if (PHY_DATA_req) begin
			data_count <= data_count + 1;
			PHY_DATA_conf <= 1'b1; // Acknowledge data request
			input_wr_en <= 1'b1; // Enable writing to input buffer
			end
		end 
			
	end 
	




endmodule