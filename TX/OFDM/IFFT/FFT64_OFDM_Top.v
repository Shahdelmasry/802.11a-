// Integrated 64-point transform + ping-pong frame buffer + 16-sample CP.

//   1  Streaming CP reader
//   2  Packet-end flush: flush_req (1-clock pulse, issued when the 64th bin
//         of the packet's last symbol is accepted) pushes exactly 63 zero
//         samples through the IFFT so that the last symbol leaves the SDF
//         pipeline. in_ready = 0 during the flush.
//   3  tx_done: 1-clock pulse after the 80th sample of the packet's last
//         symbol has been accepted downstream.

module FFT64_OFDM_Top #(
    parameter DATA_WIDTH = 16
)(
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire in_valid,
    output wire in_ready,
    input  wire ifft_mode,
    input  wire signed [DATA_WIDTH-1:0] I_in,
    input  wire signed [DATA_WIDTH-1:0] Q_in,

    // Packet-end control
    input  wire flush_req,
    output reg  tx_done,

    output wire out_valid,
    input  wire out_ready,
    output wire out_last,
    output wire [6:0] out_index,
    output wire signed [DATA_WIDTH-1:0] I_out,
    output wire signed [DATA_WIDTH-1:0] Q_out
);

    wire core_valid;
    wire core_last;
    wire [5:0] core_index;
    wire signed [DATA_WIDTH-1:0] core_i, core_q;

    wire buffer_wr_ready;
    wire frame_done;
    wire done_bank;
    wire [2*DATA_WIDTH-1:0] buffer_rd_data;

    reg [1:0] pending;
    reg read_bank;

    reg [6:0] cp_count;
    reg output_valid;

    wire [6:0] rd_index;
    wire [5:0] buffer_rd_addr;
    wire buffer_rd_bank;
    wire rd_release;
    wire out_fire;

    // =====================================================
    // PACKET-END FLUSH (2)
    // =====================================================
    reg flushing;
    reg [5:0] flush_count;
    wire flush_en;

    
    assign flush_en = flushing && buffer_wr_ready && !start;

    // Stop accepting input when the current write bank is occupied,
        assign in_ready = buffer_wr_ready && rst && !start && !flushing;

    wire core_sample_en;
    wire signed [DATA_WIDTH-1:0] core_I_in;
    wire signed [DATA_WIDTH-1:0] core_Q_in;

    assign core_sample_en = (in_valid && in_ready) || flush_en;
    assign core_I_in = flushing ? {DATA_WIDTH{1'b0}} : I_in;
    assign core_Q_in = flushing ? {DATA_WIDTH{1'b0}} : Q_in;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            flushing <= 1'b0;
            flush_count <= 6'd0;
        end else if (start) begin
            flushing <= 1'b0;
            flush_count <= 6'd0;
        end else if (flush_req && !flushing) begin
            flushing <= 1'b1;
            flush_count <= 6'd0;
        end else if (flush_en) begin
            // 63 samples: flush_count 0..62
            if (flush_count == 6'd62) begin
                flushing <= 1'b0;
                flush_count <= 6'd0;
            end else begin
                flush_count <= flush_count + 6'd1;
            end
        end
    end

    FFT64_Top #(.DATA_WIDTH(DATA_WIDTH)) U_FFT64_CORE (
        .clk(clk),
        .rst(rst),
        .start(start),
        .sample_en(core_sample_en),
        .ifft_mode(ifft_mode),
        .I_in(core_I_in),
        .Q_in(core_Q_in),
        .out_valid(core_valid),
        .out_last(core_last),
        .out_index(core_index),
        .I_out(core_i),
        .Q_out(core_q)
    );

    FFT_Output_Buffer_PingPong #(.DATA_WIDTH(DATA_WIDTH)) U_OUTPUT_BUFFER (
        .clk(clk),
        .rst(rst),
        .wr_en(core_valid),
        .wr_last(core_last),
        .wr_addr(core_index),
        .wr_data({core_i, core_q}),
        .wr_ready(buffer_wr_ready),
        .frame_done(frame_done),
        .done_bank(done_bank),
        .rd_bank(buffer_rd_bank),
        .rd_addr(buffer_rd_addr),
        .rd_data(buffer_rd_data),
        .rd_release(rd_release),
        .rd_release_bank(read_bank)
    );

    
    // A bank is pending once its final transform sample has been stored.
    // The reader drains banks in the same alternating order as the writer.
    
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            pending <= 2'b00;
            read_bank <= 1'b0;
        end else begin
            if (frame_done)
                pending[done_bank] <= 1'b1;

            if (rd_release) begin
                pending[read_bank] <= 1'b0;
                read_bank <= ~read_bank;
            end
        end
    end

    
    // STREAMING CP READER (1)
    // output_valid = buffer_rd_data holds sample cp_count of read_bank.
    // Read order per symbol: 48..63 (cyclic prefix), then 0..63.
    
    assign out_fire   = output_valid && out_ready;
    assign rd_release = out_fire && (cp_count == 7'd79);

    // Index whose data must appear on buffer_rd_data at the next clock:
    //   idle            -> 0 (prime the first sample of a pending bank)
    //   stalled         -> hold cp_count
    //   accepted, < 79  -> cp_count + 1
    //   accepted, = 79  -> 0 of the other bank
    assign rd_index = !output_valid ? 7'd0 :
                      !out_ready    ? cp_count :
                      (cp_count == 7'd79) ? 7'd0 :
                                            (cp_count + 7'd1);

    assign buffer_rd_bank = rd_release ? ~read_bank : read_bank;

    assign buffer_rd_addr = (rd_index < 7'd16)
                          ? (6'd48 + rd_index[5:0])
                          : (rd_index - 7'd16);

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            output_valid <= 1'b0;
            cp_count <= 7'd0;
        end else begin
            if (!output_valid) begin
                // Prime: address 48 of a pending bank is being read now.
                if (pending[read_bank]) begin
                    output_valid <= 1'b1;
                    cp_count <= 7'd0;
                end
            end else if (out_fire) begin
                if (cp_count == 7'd79) begin
                    // Continue with the next bank without a bubble if it is
                    // already complete; otherwise return to idle.
                    output_valid <= pending[~read_bank];
                    cp_count <= 7'd0;
                end else begin
                    cp_count <= cp_count + 7'd1;
                end
            end
        end
    end

    
    // END-OF-PACKET TRACKING (3)
    // The frame that completes after flush_req is the packet's last symbol.
    
    reg last_expected;
    reg last_ready;
    reg last_bank;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            last_expected <= 1'b0;
            last_ready <= 1'b0;
            last_bank <= 1'b0;
            tx_done <= 1'b0;
        end else if (start) begin
            last_expected <= 1'b0;
            last_ready <= 1'b0;
            tx_done <= 1'b0;
        end else begin
            tx_done <= 1'b0;

            if (flush_req)
                last_expected <= 1'b1;

            if (frame_done && last_expected) begin
                last_expected <= 1'b0;
                last_ready <= 1'b1;
                last_bank <= done_bank;
            end

            if (rd_release && last_ready && (read_bank == last_bank)) begin
                last_ready <= 1'b0;
                tx_done <= 1'b1;
            end
        end
    end

    assign out_valid = output_valid;
    assign out_last = output_valid && (cp_count == 7'd79);
    assign out_index = cp_count;
    assign I_out = $signed(buffer_rd_data[2*DATA_WIDTH-1:DATA_WIDTH]);
    assign Q_out = $signed(buffer_rd_data[DATA_WIDTH-1:0]);

endmodule
