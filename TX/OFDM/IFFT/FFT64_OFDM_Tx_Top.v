
// Complete OFDM transmitter front end:
// 48 mapper symbols -> pilot insertion -> 64-point IFFT
// -> ping-pong buffer -> cyclic prefix -> 80 output samples.
// pkt_last flag is queued per captured symbol (2 entries).

module FFT64_OFDM_Tx_Top #(
    parameter DATA_WIDTH = 16
)(
    input wire clk,
    input wire rst,
    input wire start,
    input wire ifft_mode,

    // External subcarrier mapper interface
    input wire [31:0] mapper_data,
    input wire mapper_valid,
    input wire mapper_last,
    input wire pkt_last,
    output wire mapper_capture_ready,
   

    // OFDM output interface
    output wire tx_done, // fsm signals that the last sample of the packet has been accepted downstream.
    output wire out_valid,
    input wire out_ready,
    output wire out_last,
    output wire [6:0] out_index,
    output wire signed [DATA_WIDTH-1:0] I_out,
    output wire signed [DATA_WIDTH-1:0] Q_out
);

    // Pilot generator
    wire signed [1:0] pilot_value;
    wire sym_advance;

    Pilot_Gen U_PILOT_GEN (
        .clk(clk),
        .rst(rst),
        .start(start),
        .sym_advance(sym_advance),
        .pilot_out(pilot_value)
    );

    // Pilot insertion output
    wire [31:0] ifft_input_data;
    wire ifft_input_valid;
    wire ifft_input_ready;
    wire mapper_in_ready;
    assign mapper_capture_ready = mapper_in_ready;

   
    reg [1:0] sym_last_q;     // [0] = oldest symbol inside Pilot_Insertion
    reg [1:0] sym_q_count;    // 0..2 symbols queued
    wire sym_push;
    wire flush_req;

    assign sym_push = mapper_valid && mapper_in_ready && mapper_last;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            sym_last_q  <= 2'b00;
            sym_q_count <= 2'd0;
        end else if (start) begin
            sym_last_q  <= 2'b00;
            sym_q_count <= 2'd0;
        end else begin
            if (sym_push && sym_advance) begin
                // A push needs a free bank, so one symbol is queued here:
                // it leaves and the new one becomes the oldest.
                sym_last_q[0] <= pkt_last;
                sym_last_q[1] <= 1'b0;
            end else if (sym_push) begin
                if (sym_q_count == 2'd0)
                    sym_last_q[0] <= pkt_last;
                else
                    sym_last_q[1] <= pkt_last;
                sym_q_count <= sym_q_count + 2'd1;
            end else if (sym_advance) begin
                sym_last_q  <= {1'b0, sym_last_q[1]};
                sym_q_count <= sym_q_count - 2'd1;
            end
        end
    end

    assign flush_req = sym_advance && sym_last_q[0];
    
    

    Pilot_Insertion U_PILOT_INSERTION (
        .clk(clk),
        .rst(rst),
        .start(start),

        .in_data(mapper_data),
        .in_valid(mapper_valid),
        .in_last(mapper_last),
        .in_ready(mapper_in_ready),

        .pilot_in(pilot_value),
        .sym_advance(sym_advance),

        .out_data(ifft_input_data),
        .out_valid(ifft_input_valid),
        .out_ready(ifft_input_ready)
    );

    // Extract signed I and Q components.
    wire signed [15:0] ifft_input_I;
    wire signed [15:0] ifft_input_Q;


    assign ifft_input_I = $signed(ifft_input_data[31:16]);
    assign ifft_input_Q = $signed(ifft_input_data[15:0]);

    // Integrated IFFT, ping-pong buffer and CP controller.
    FFT64_OFDM_Top #(
        .DATA_WIDTH(DATA_WIDTH)
    ) U_OFDM_CORE (
        .clk(clk),
        .rst(rst),
        .start(start),

        .in_valid(ifft_input_valid),
        .in_ready(ifft_input_ready),

        .ifft_mode(ifft_mode),

        .I_in(ifft_input_I),
        .Q_in(ifft_input_Q),

        .flush_req(flush_req),
        .tx_done(tx_done),

        .out_valid(out_valid),
        .out_ready(out_ready),
        .out_last(out_last),
        .out_index(out_index),

        .I_out(I_out),
        .Q_out(Q_out)
    );

endmodule
