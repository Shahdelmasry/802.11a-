`timescale 1ns / 1ps


module upsampler_zero_stuffing #(
    parameter DATA_WIDTH = 16,
    parameter L = 2 // Upsampling Factor (e.g., 2x)
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // Upstream (from MUX)
    input  wire signed [DATA_WIDTH-1:0] in_i,
    input  wire signed [DATA_WIDTH-1:0] in_q,
    input  wire                         in_valid,
    input  wire                         in_last,
    output wire                         in_ready,

    // Downstream (to Interpolation FIR Filter / DAC)
    output wire signed [DATA_WIDTH-1:0] out_i,
    output wire signed [DATA_WIDTH-1:0] out_q,
    output wire                         out_valid,
    output wire                         out_last,
    input  wire                         out_ready
);

    // Calculate counter width based on the upsampling factor L
    localparam CNT_WIDTH = (L > 1) ? $clog2(L) : 1;
    reg [CNT_WIDTH-1:0] cnt;
    
    // Registers to hold the incoming sample data
    reg signed [DATA_WIDTH-1:0] saved_i;
    reg signed [DATA_WIDTH-1:0] saved_q;
    reg                         saved_last;
    reg                         has_data;

    // =========================================================
    // 1. Ready Logic (Upstream Control)
    // =========================================================
    // The module can accept new data in two cases:
    // - If it is completely empty (!has_data)
    // - If it is currently sending the last zero of the current sample, and the downstream block is ready to accept it
    assign in_ready = (!has_data) || (has_data && (cnt == L - 1) && out_ready);

    // =========================================================
    // 2. Sequential Logic (State & Counter)
    // =========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            has_data   <= 1'b0;
            saved_i    <= {DATA_WIDTH{1'b0}};
            saved_q    <= {DATA_WIDTH{1'b0}};
            saved_last <= 1'b0;
            cnt        <= 0;
        end 
        else begin
            // State 1: Module holds data and downstream is ready to receive
            if (has_data && out_ready) begin
                if (cnt == L - 1) begin
                    // Finished transmitting current sample along with all its inserted zeros
                    // Is there a new sample waiting at the input?
                    if (in_valid && in_ready) begin
                        has_data   <= 1'b1;
                        saved_i    <= in_i;
                        saved_q    <= in_q;
                        saved_last <= in_last;
                        cnt        <= 0; // Reset counter for the new sample
                    end 
                    else begin
                        // No new data available, clear the buffer
                        has_data   <= 1'b0;
                        cnt        <= 0;
                    end
                end 
                else begin
                    // Still counting and outputting zeros for the current sample
                    cnt <= cnt + 1;
                end
            end 
            // State 2: Module is completely empty and a new valid sample arrives
            else if (!has_data && in_valid && in_ready) begin
                has_data   <= 1'b1;
                saved_i    <= in_i;
                saved_q    <= in_q;
                saved_last <= in_last;
                cnt        <= 0;
            end
        end
    end

    // =========================================================
    // 3. Output Logic (Combinational)
    // =========================================================
    assign out_valid = has_data;
    
    // Output the original sample data on the first clock cycle (when cnt = 0), then output zeros
    assign out_i = (has_data && cnt == 0) ? saved_i : {DATA_WIDTH{1'b0}};
    assign out_q = (has_data && cnt == 0) ? saved_q : {DATA_WIDTH{1'b0}};
    
    // Assert out_last on the "very last clock" of zero-insertion for the last sample
    // to ensure the downstream filter consumes all zeros before finishing
    assign out_last = (has_data && cnt == L - 1) ? saved_last : 1'b0;

endmodule