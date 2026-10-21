
module Pilot_Insertion (
    input              clk,
    input              rst,

    // Mapper interface: one complex symbol per accepted transfer
    input      [31:0]  in_data,
    input              in_valid,
    output             in_ready,

    // Pilot Generator interface
    input signed [1:0] pilot_in,
    output             sym_advance,

    // Streaming interface to the 64-point IFFT
    output reg [31:0]  out_data,
    output             out_valid,
    input              out_ready
    
);
    parameter [15:0] P_P = 16'h7FFF; // +1 in Q1.15
    parameter [15:0] P_N = 16'h8000; // -1 in Q1.15

    localparam [1:0] CAPTURE   = 2'd0; // Capture 48 complex symbols from the Mapper
    localparam [1:0] SEND_BINS = 2'd1; // Stream 64 complex bins to the IFFT

    reg [1:0] state;
    reg [5:0] data_count;
    reg [5:0] bin_count;

    // 48 complex data symbols from the Mapper
    reg [31:0] data_buf [0:47];

    // Polarity held constant for the current OFDM symbol
    reg signed [1:0] pilot_latched;

    integer idx;

    assign in_ready = (state == CAPTURE);
    assign out_valid = (state == SEND_BINS);

    // Advance once, when bin 63 of the current symbol is accepted.
    assign sym_advance =
        (state == SEND_BINS) &&
        out_ready &&
        (bin_count == 6'd63);

    // Map an IFFT bin to the Mapper data index.
    // -26..-22, -20..-8, -6..-1, +1..+6, +8..+20, +22..+26.
    function integer data_index_for_bin;
        input integer k;
        begin
            if (k >= 38 && k <= 42)
                data_index_for_bin = k - 38;       // -26..-22
            else if (k >= 44 && k <= 56)
                data_index_for_bin = 5 + k - 44;    // -20..-8
            else if (k >= 58 && k <= 63)
                data_index_for_bin = 18 + k - 58;   // -6..-1
            else if (k >= 1 && k <= 6)
                data_index_for_bin = 24 + k - 1;    // +1..+6
            else if (k >= 8 && k <= 20)
                data_index_for_bin = 30 + k - 8;    // +8..+20
            else if (k >= 22 && k <= 26)
                data_index_for_bin = 43 + k - 22;   // +22..+26
            else
                data_index_for_bin = -1;
        end
    endfunction

    // Packing: {I[15:0], Q[15:0]}.
    always @ (*) begin
        out_data = 32'd0;
        idx = data_index_for_bin(bin_count);

        if (state == SEND_BINS) begin
            case (bin_count)
              6'd7, 6'd43, 6'd57: begin
                if (pilot_latched == -2'sd1)
                    out_data = {P_N, 16'h0000};
                else
                    out_data = {P_P, 16'h0000};
                end

              6'd21: begin
                if (pilot_latched == -2'sd1)
                    out_data = {P_P, 16'h0000};
                else
                     out_data = {P_N, 16'h0000};
                end

                default: begin
                  if (idx >= 0)
                      out_data = data_buf[idx];
                  else
                      out_data = 32'd0;
              end
            endcase
        end
    end

    // Capture one OFDM symbol, then stream its 64 bins.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state         <= CAPTURE;
            data_count    <= 6'd0;
            bin_count     <= 6'd0;
            pilot_latched <= 2'sd1;
        end else begin
            case (state)
                CAPTURE: begin
                    if (in_valid && in_ready) begin
                        data_buf[data_count] <= in_data;

                        // Latch the current polarity only once per symbol.
                        if (data_count == 6'd0)
                            pilot_latched <= pilot_in;

                        if (data_count == 6'd47) begin
                            data_count <= 6'd0;
                            bin_count  <= 6'd0;
                            state      <= SEND_BINS;
                        end else begin
                            data_count <= data_count + 1'b1;
                        end
                    end
                end

                SEND_BINS: begin
                    if (out_valid && out_ready) begin
                        if (bin_count == 6'd63) begin
                            bin_count <= 6'd0;
                            state     <= CAPTURE;
                        end else begin
                            bin_count <= bin_count + 1'b1;
                        end
                    end
                end

                default: begin
                    state      <= CAPTURE;
                    data_count <= 6'd0;
                    bin_count  <= 6'd0;
                end
            endcase
        end
    end

endmodule
