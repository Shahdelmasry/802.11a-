
module Pilot_Insertion (
    input              clk,
    input              rst,
    input              start,  // new packet: abandon buffered symbols, restart at bank 0

    // Mapper interface: one complex symbol per accepted transfer
    input      [31:0]  in_data,
    input              in_valid,
    output             in_ready,
    input              in_last,

    // Pilot Generator interface
    input signed [1:0] pilot_in,
    output             sym_advance,

    // Streaming interface to the 64-point IFFT
    output reg [31:0]  out_data,
    output             out_valid,
    input              out_ready

);
    // Symbol n+1 is captured into one bank while symbol n is streamed from
    // the other, so the mapper is no longer blocked for the 64 send clocks.
    // Per-symbol budget: max(48 capture, 64 send) instead of 48 + 64.

    parameter signed [15:0] P_P = 16'h4000; // +1 in Q2.14
    parameter signed [15:0] P_N = 16'hC000; // -1 in Q2.14

    reg [5:0] data_count;   // capture index 0..47 in the write bank
    reg [5:0] bin_count;    // send index 0..63 from the read bank

    reg       wr_bank;      // bank being captured
    reg       rd_bank;      // bank being streamed
    reg [1:0] bank_full;    // bank holds a complete 48-sample symbol

    // Two banks of 48 complex data symbols: bank 0 = 0..47, bank 1 = 48..95
    reg [31:0] data_buf [0:95];

    integer idx;

    wire [6:0] wr_addr;
    wire [6:0] rd_addr;

    // No transfer is accepted on either side while start is asserted.
    assign in_ready  = !bank_full[wr_bank] && !start;
    assign out_valid =  bank_full[rd_bank] && !start;

    // Advance once, when bin 63 of the current symbol is accepted.
    assign sym_advance =
        out_valid &&
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

    assign wr_addr = wr_bank ? (7'd48 + data_count) : {1'b0, data_count};

    // Packing: {I[15:0], Q[15:0]}.
    // Pilot polarity: pilot_in is used while the symbol is streamed. Pilot_Gen
    // only advances on sym_advance (bin 63 of this symbol, a null bin), so
    // pilot_in is constant for all 64 bins of the symbol being sent.

    always @ (*) begin
        out_data = 32'd0;
        idx = data_index_for_bin(bin_count);

        if (bank_full[rd_bank]) begin
            case (bin_count)
              6'd7, 6'd43, 6'd57: begin
                if (pilot_in == -2'sd1)
                    out_data = {P_N, 16'h0000};
                else
                    out_data = {P_P, 16'h0000};
                end

              6'd21: begin
                if (pilot_in == -2'sd1)
                    out_data = {P_P, 16'h0000};
                else
                     out_data = {P_N, 16'h0000};
                end

                default: begin
                  if (idx >= 0)
                      out_data = rd_bank ? data_buf[48 + idx] : data_buf[idx];
                  else
                      out_data = 32'd0;
              end
            endcase
        end
    end

    // Capture side: fill the write bank, then hand it to the send side.
    // Send side: stream 64 bins from the read bank, then release it.
    // A bank is only written while empty and only read while full, so the
    // two sides never touch the same bank.
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            data_count <= 6'd0;
            bin_count  <= 6'd0;
            wr_bank    <= 1'b0;
            rd_bank    <= 1'b0;
            bank_full  <= 2'b00;
        end else if (start) begin
            data_count <= 6'd0;
            bin_count  <= 6'd0;
            wr_bank    <= 1'b0;
            rd_bank    <= 1'b0;
            bank_full  <= 2'b00;
        end else begin

            // ---------------- capture ----------------
            if (in_valid && in_ready) begin

                // Store the accepted complex sample.
                data_buf[wr_addr] <= in_data;

                // The final sample must be sample 48 (index 47).
                if (in_last && (data_count == 6'd47)) begin
                    data_count          <= 6'd0;
                    bank_full[wr_bank]  <= 1'b1;
                    wr_bank             <= ~wr_bank;
                end
                else if (!in_last && (data_count < 6'd47)) begin
                    data_count <= data_count + 1'b1;
                end
            end

            // ---------------- send ----------------
            if (out_valid && out_ready) begin
                if (bin_count == 6'd63) begin
                    bin_count           <= 6'd0;
                    bank_full[rd_bank]  <= 1'b0;
                    rd_bank             <= ~rd_bank;
                end else begin
                    bin_count <= bin_count + 1'b1;
                end
            end
        end
    end

endmodule
