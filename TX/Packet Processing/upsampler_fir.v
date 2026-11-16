`timescale 1ns / 1ps


module upsampler_fir #(
    parameter DATA_WIDTH  = 16,
    parameter COEFF_WIDTH = 16,
    parameter NUM_TAPS    = 7,  // Number of Filter Taps (Odd number is standard for symmetry)
    parameter FRAC_BITS   = 14  // Q2.14 Format (To shift the MAC result back to 16-bit)
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // Upstream (from Zero-Insertion Upsampler)
    input  wire signed [DATA_WIDTH-1:0] in_i,
    input  wire signed [DATA_WIDTH-1:0] in_q,
    input  wire                         in_valid,
    input  wire                         in_last,
    output wire                         in_ready,

    // Downstream (to DAC)
    output reg  signed [DATA_WIDTH-1:0] out_i,
    output reg  signed [DATA_WIDTH-1:0] out_q,
    output reg                          out_valid,
    output reg                          out_last,
    input  wire                         out_ready
);

    // =========================================================
    // 1. Handshake Logic
    // =========================================================
    // The FIR filter accepts data whenever the downstream (DAC) is ready to take data.
    // If downstream stalls (out_ready = 0), the whole pipeline stalls.
    assign in_ready = out_ready;

    // =========================================================
    // 2. FIR Coefficients (Fixed Low-Pass Filter Example)
    // =========================================================
    wire signed [COEFF_WIDTH-1:0] coeff [0:NUM_TAPS-1];
    
    // Example symmetric coefficients for a simple Low-Pass Filter in Q2.14 format
    assign coeff[0] = -16'sd512;   // Tap 0
    assign coeff[1] =  16'sd1024;  // Tap 1
    assign coeff[2] =  16'sd4096;  // Tap 2
    assign coeff[3] =  16'sd8192;  // Tap 3 (Center Tap - Peak)
    assign coeff[4] =  16'sd4096;  // Tap 4
    assign coeff[5] =  16'sd1024;  // Tap 5
    assign coeff[6] = -16'sd512;   // Tap 6

    // =========================================================
    // 3. Delay Line (Shift Registers)
    // =========================================================
    reg signed [DATA_WIDTH-1:0] shift_i [0:NUM_TAPS-1];
    reg signed [DATA_WIDTH-1:0] shift_q [0:NUM_TAPS-1];
    
    // To properly propagate the 'last' flag through the filter delay
    reg shift_last [0:NUM_TAPS-1]; 
    
    integer i;
    
    // Shift operation when new valid data arrives and pipeline is not stalled
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_TAPS; i = i + 1) begin
                shift_i[i]    <= {DATA_WIDTH{1'b0}};
                shift_q[i]    <= {DATA_WIDTH{1'b0}};
                shift_last[i] <= 1'b0;
            end
        end 
        else if (in_valid && in_ready) begin
            // Insert newest sample at index 0
            shift_i[0]    <= in_i;
            shift_q[0]    <= in_q;
            shift_last[0] <= in_last;
            
            // Shift older samples down the line
            for (i = 0; i < NUM_TAPS-1; i = i + 1) begin
                shift_i[i+1]    <= shift_i[i];
                shift_q[i+1]    <= shift_q[i];
                shift_last[i+1] <= shift_last[i];
            end
        end
    end

    // =========================================================
    // 4. MAC Operation (Combinational Convolution Sum)
    // =========================================================
    reg signed [DATA_WIDTH+COEFF_WIDTH-1:0] sum_i;
    reg signed [DATA_WIDTH+COEFF_WIDTH-1:0] sum_q;
    
    integer k;
    
    always @(*) begin
        // Initialize sums to 0
        sum_i = 0;
        sum_q = 0;
        
        // Multiply and Accumulate
        for (k = 0; k < NUM_TAPS; k = k + 1) begin
            sum_i = sum_i + (shift_i[k] * coeff[k]);
            sum_q = sum_q + (shift_q[k] * coeff[k]);
        end
    end

    // =========================================================
    // 5. Output Stage (Normalization and Registration)
    // =========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_i     <= {DATA_WIDTH{1'b0}};
            out_q     <= {DATA_WIDTH{1'b0}};
            out_valid <= 1'b0;
            out_last  <= 1'b0;
        end 
        else if (out_ready) begin
            // If we just accepted valid data, output the filtered result
            if (in_valid) begin
                out_valid <= 1'b1;
                
                // Normalization: Shift right by FRAC_BITS to return to Q2.14 format
                out_i <= sum_i >>> FRAC_BITS;
                out_q <= sum_q >>> FRAC_BITS;
                
                // The 'last' flag exits the filter aligned with the center tap
                // so the downstream gets the full filtered packet shape
                out_last <= shift_last[NUM_TAPS/2]; 
            end 
            else begin
                // Pipeline empty bubble
                out_valid <= 1'b0;
                out_last  <= 1'b0;
                out_i     <= {DATA_WIDTH{1'b0}};
                out_q     <= {DATA_WIDTH{1'b0}};
            end
        end
    end

endmodule