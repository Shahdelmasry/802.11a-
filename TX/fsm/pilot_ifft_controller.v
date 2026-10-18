module pilot_ifft_controller #(
    parameter DATA_WIDTH   = 12,          // I/Q sample bit width
    parameter SYMBOL_WIDTH = 2*DATA_WIDTH, // Complex symbol width (I + Q)
    parameter FFT_POINTS   = 64          // IFFT size
)(
    input  wire                          clk,              // 80 MHz master clock
    input  wire                          rst_n,            // Active-low reset
    input  wire                          enable,           // Controller enable (from top-level FSM)
    input  wire                          data_en,          // Asserted in DATA state
    // Interface from Bit Processing Controller
    input  wire                          symbol_valid,     // 48 symbols ready
    output wire                          ready_for_data,   // Ready to accept new symbols
    // IFFT core interface
    output reg                           ifft_start,       // Trigger IFFT
    input  wire                          ifft_done,        // IFFT completion flag
    // Output interface (to upsampling/DAC)
    output reg                           output_valid     // 80 samples ready   
);
	localparam Wait_for_data = 3'b000 ;
	localparam Fill_subcarriers = 3'b001 ;
	localparam Insert_pilots =3'b011 ;	
	localparam Run_IFFT = 3'b010 ;
	localparam Add_GI = 3'b110 ;

	
	reg [2:0] current_state, next_state;
	always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        current_state <= Wait_for_data;
    else if (!enable)
        current_state <= Wait_for_data;
    else
        current_state <= next_state;
end

	always @(*) begin
    next_state = state;  // Default: hold state
// Next state logic 
    case (current_state)
        Wait_for_data: begin
            if (symbol_valid && data_en)
                next_state = Fill_subcarriers;
        end

        Fill_subcarriers: begin
            // One cycle to fill 48 data subcarriers
            next_state = Insert_pilots;
        end

        Insert_pilots: begin
            // One cycle to insert 4 pilots
            next_state = Run_IFFT;
        end

        Run_IFFT: begin
            if (ifft_done)
                next_state = Add_GI;
            else 
                next_state = Run_ifft;
            
        end

        Add_GI: begin
            // One cycle to prepare guard interval
            next_state = Wait_for_data;
        end

        default: next_state = Wait_for_data;
    endcase
end
// Handshake
assign ready_for_data = (current_state == Wait_for_data) && enable;

// IFFT trigger
reg ifft_start_reg;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        ifft_start_reg <= 1'b0;
    else
        ifft_start_reg <= (current_state == Run_IFFT);
end
always @(*) begin
    ifft_start = (current_state == Run_IFFT) && !ifft_start_reg;
end

// Output valid
always @(*) begin
    output_valid = (current_state == Add_GI);
end
endmodule
