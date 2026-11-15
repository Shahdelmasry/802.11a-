// Integrated 64-point transform + ping-pong frame buffer + 16-sample CP.

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

    reg [1:0] cp_state;
    localparam ST_IDLE    = 2'd0;
    localparam ST_ISSUE   = 2'd1;
    localparam ST_CAPTURE = 2'd2;
    localparam ST_HOLD    = 2'd3;

    reg [6:0] cp_count;
    reg [2*DATA_WIDTH-1:0] output_data;
    reg output_valid;

    wire [5:0] buffer_rd_addr;
    wire rd_release;

    // Stop accepting input when the current write bank is occupied.
    // This stalls every SDF stage coherently through sample_en.
    assign in_ready = buffer_wr_ready && !rst && !start;

    FFT64_Top #(.DATA_WIDTH(DATA_WIDTH)) U_FFT64_CORE (
        .clk(clk),
        .rst(rst),
        .start(start),
        .sample_en(in_valid && in_ready),
        .ifft_mode(ifft_mode),
        .I_in(I_in),
        .Q_in(Q_in),
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
        .rd_bank(read_bank),
        .rd_addr(buffer_rd_addr),
        .rd_data(buffer_rd_data),
        .rd_release(rd_release),
        .rd_release_bank(read_bank)
    );

    // Read address sequence: 48..63, then 0..63.
    assign buffer_rd_addr = (cp_count < 7'd16)
                          ? (6'd48 + cp_count[5:0])
                          : (cp_count - 7'd16);

    // A bank is pending once its final transform sample has been stored.
    // The reader drains banks in the same alternating order as the writer.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
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

    // Synchronous RAM read is captured into a holding register. The simple
  
    assign rd_release = (cp_state == ST_HOLD) && output_valid && out_ready &&
                        (cp_count == 7'd79);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cp_state <= ST_IDLE;
            cp_count <= 7'd0;
            output_data <= {2*DATA_WIDTH{1'b0}};
            output_valid <= 1'b0;
        end else begin
            case (cp_state)
                ST_IDLE: begin
                    output_valid <= 1'b0;
                    cp_count <= 7'd0;
                    if (pending[read_bank])
                        cp_state <= ST_ISSUE;
                end

                ST_ISSUE: begin
                    // The buffer samples this cycle's address at this edge.
                    cp_state <= ST_CAPTURE;
                end

                ST_CAPTURE: begin
                    output_data <= buffer_rd_data;
                    output_valid <= 1'b1;
                    cp_state <= ST_HOLD;
                end

                ST_HOLD: begin
                    if (output_valid && out_ready) begin
                        output_valid <= 1'b0;
                        if (cp_count == 7'd79) begin
                            cp_count <= 7'd0;
                            cp_state <= ST_IDLE;
                        end else begin
                            cp_count <= cp_count + 7'd1;
                            cp_state <= ST_ISSUE;
                        end
                    end
                end

                default: begin
                    cp_state <= ST_IDLE;
                    output_valid <= 1'b0;
                    cp_count <= 7'd0;
                end
            endcase
        end
    end

    assign out_valid = output_valid;
    assign out_last = output_valid && (cp_count == 7'd79);
    assign out_index = cp_count;
    assign I_out = $signed(output_data[2*DATA_WIDTH-1:DATA_WIDTH]);
    assign Q_out = $signed(output_data[DATA_WIDTH-1:0]);

endmodule
