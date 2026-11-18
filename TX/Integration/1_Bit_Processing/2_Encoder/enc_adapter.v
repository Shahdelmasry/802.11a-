// enc_adapter.v - rate-select adapter between the Encoder and the Write Controller
// Chooses the one Encoder bus that carries data for the selected coding rate, zero-extends it to
// 16 bits and tells the Write Controller how many of those bits are valid (in_cnt = 12 / 9 / 8).
// rate_sel must be the Encoder `rate` value DELAYED BY ONE CYCLE, because the Encoder outputs are registered.
//------------------------------------------------------------------------------
module enc_adapter (                                           // begin module declaration
    input  wire [1:0]  rate_sel,                               // 0: 1/2, 1: 2/3, 2: 3/4 (aligned with the Encoder outputs)
    input  wire [11:0] data_out,                               // Encoder bus for rate 1/2 (12 bits per word)
    input  wire [8:0]  data_out_23,                            // Encoder bus for rate 2/3 (9 bits per word)
    input  wire [7:0]  data_out_34,                            // Encoder bus for rate 3/4 (8 bits per word)
    output reg  [15:0] wc_data,                                // data_in of the Write Controller (bit 0 = earliest coded bit)
    output reg  [4:0]  wc_cnt                                  // in_cnt of the Write Controller (number of valid bits)
);                                                             // end of port list
    always @(*) begin                                          // combinational multiplexer
        case (rate_sel)                                        // coding rate
            2'd0:    begin wc_data = {4'd0, data_out};      wc_cnt = 5'd12; end // 1/2: 12 valid bits
            2'd1:    begin wc_data = {7'd0, data_out_23};   wc_cnt = 5'd9;  end // 2/3: 9 valid bits
            2'd2:    begin wc_data = {8'd0, data_out_34};   wc_cnt = 5'd8;  end // 3/4: 8 valid bits
            default: begin wc_data = 16'd0;                 wc_cnt = 5'd0;  end // code 3 does not exist: nothing valid
        endcase                                                // end of case
    end                                                        // end of multiplexer
endmodule                                                      // end of enc_adapter
