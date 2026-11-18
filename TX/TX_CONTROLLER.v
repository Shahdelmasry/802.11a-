// ============================================================================
// TX_CONTROLLER
// Main FSM controlling the 802.11a transmit chain. It sequences:
//   IDLE -> PREAMBLE -> SIGNAL -> DATA -> TXEnd -> IDLE
// and generates enables/muxes for the FIFO, scrambler, encoder, interleaver,
// mapper, and IFFT blocks.
//
// Structure (one driver per signal):
//   1) State register          (sequential, async active-low reset)
//   2) Next-state + Moore outs (combinational, blocking assignments only)
//   3) Registered handshake    (sequential, with reset): il_start, ifft_start,
//                              ifft_mode
// ============================================================================
module TX_CONTROLLER (
    input clk,
    input rst_n,                 // Active-low asynchronous reset

    input preamble_valid,        // Preamble transmission finished, releases preamble mux

    input fifo_busy,             // FIFO has a frame pending -> start transmission
    input fifo_data_valid,       // FIFO data payload is valid (SIGNAL -> DATA)
    input fifo_header_valid,     // FIFO header (SIGNAL field info) is valid (PREAMBLE -> SIGNAL)
    input abort,                 // mac send txend
	input vector_err,

    input mapper_capture_ready,  // Mapper ready to capture (currently unused)

    input tx_done,               // End-of-transmission flag (was undeclared, now a port)
    input in_ready,              // Interleaver ready signal
    input il_busy,               // Interleaver busy signal
    output reg il_start,         // Interleaver start signal
    output reg tx_clear,         // to clear encoder

    output reg seed_sel,         // Scrambler seed
    output reg scr_en,           // Scrambler enable (was undeclared, now a port)
    output reg data_ready,       // ready to accept data from fifo

    output reg ifft_mode,        // IFFT mode select (1 = inverse FFT for TX)
    output reg ifft_start,       // Start IFFT processing

    output reg rom_read_en,      // Enable preamble ROM read
    output reg counter_en,       // Enable data symbol/bit counter

    output reg [1:0] preamb_mux_en, // Preamble mux select: 00 = off, 01 = preamble, 10 = data path
    output reg signal_mux_en,    // Select SIGNAL field into the encoder path

    output reg input_wr_en,      // Input buffer write enable
    output reg input_rd_en       // Input buffer read enable
);

// State encodings
localparam IDLE     = 3'b000;  // Waiting for a frame
localparam PREAMBLE = 3'b001;  // Sending the preamble from ROM
localparam SIGNAL   = 3'b011;  // Sending the SIGNAL field
localparam DATA     = 3'b111;  // Sending the DATA field
localparam TXEnd    = 3'b110;  // Transmission end / cleanup

reg [2:0] current_state, next_state; // FSM state registers

// ----------------------------------------------------------------------------
// 1) State register: async active-low reset, otherwise advance to next state
// ----------------------------------------------------------------------------
always @(posedge clk or negedge reset) begin
    if (!reset)
        current_state <= IDLE;
    else
        current_state <= next_state;
end

// ----------------------------------------------------------------------------
// 2) Next-state logic and state-dependent (Moore) outputs.
// ----------------------------------------------------------------------------
always @(*) begin
    // Default output values (overridden per state below)
    preamb_mux_en     = 2'b00;
    signal_mux_en     = 1'b0;
    counter_en        = 1'b0;
    rom_read_en       = 1'b0;
    data_ready        = 1'b0;
    tx_clear          = 1'b0;
    input_rd_en       = 1'b0;
    input_wr_en       = 1'b0;
    seed_sel          = 1'b0;   // Use the default scrambler seed
    scr_en            = 1'b0;
    next_state        = current_state;  // Default: hold state

    case (current_state)
        // Wait until the FIFO signals a frame is ready
        IDLE: begin
            if (fifo_busy && !vector_err)
                next_state = PREAMBLE;
			else if (vector_err)
				next_state = TXEnd;
			else
				next_state = IDLE;
        end

        // Send preamble; move on once the header is available
        PREAMBLE: begin
            // Mux sends preamble until preamble_valid releases it
            preamb_mux_en = preamble_valid ? 2'b00 : 2'b01;
            rom_read_en   = 1'b1;   // Read preamble samples from ROM
            if (fifo_header_valid)
                next_state = SIGNAL;
        end

        // Send SIGNAL field; move on once payload data is available
        SIGNAL: begin
            tx_clear      = 1'b1;   // Clear encoder before sending signal field
            signal_mux_en = 1'b1;   // Enable multiplexer to send signal field
            if (fifo_data_valid)
                next_state = DATA;
        end

        // Send payload; finish on completion or MAC abort
        DATA: begin
            data_ready    = 1'b1;   // Accept data from the FIFO
            signal_mux_en = 1'b0;   // Send data (not SIGNAL) to encoder
            counter_en    = 1'b1;   // Enable data counter
            input_rd_en   = 1'b1;   // Enable input buffer read
            input_wr_en   = 1'b1;   // Enable input buffer write
            scr_en        = 1'b1;   // Enable scrambler
            preamb_mux_en = 2'b10;  // Route the data path through the mux
            if (tx_done || abort)
                next_state = TXEnd;
        end

        // Stop accepting data and return to idle (outputs stay at defaults)
        TXEnd: begin
            next_state = IDLE;
        end

        default: next_state = IDLE;  // Recover from illegal states
    endcase
end

// ----------------------------------------------------------------------------
// 3) Registered handshake / symbol-processing control
// ----------------------------------------------------------------------------
always @(posedge clk or negedge reset) begin
    if (!reset) begin
        il_start   <= 1'b0;
        ifft_start <= 1'b0;
        ifft_mode  <= 1'b0;
    end
    else if (current_state == DATA) begin
        // Interleaver handshake: start when idle, deassert once it accepts input
        if (!il_busy) begin
            il_start <= 1'b1;
            if (in_ready)
                il_start <= 1'b0;
        end

        // Symbol processing
        ifft_start <= 1'b1;   // start IFFT
        ifft_mode  <= 1'b1;   // Always IFFT mode (for TX)
    end
    else begin
        il_start   <= 1'b0;
        ifft_start <= 1'b0;
        ifft_mode  <= 1'b0;
    end
end

endmodule

// tx done from ifft to fifo 
// packet end => end of data
