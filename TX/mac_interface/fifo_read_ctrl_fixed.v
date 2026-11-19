module fifo_read_ctrl #(
    parameter PW = 7
)(
    input  wire          clk,
    input  wire          rst,                 // active-low asynchronous reset
    input  wire          empty,
    input  wire [PW-1:0] gray_wr_pointer,
    output wire          ren,
    input  wire [7:0]    fifo_data_out,

    output reg  [3:0]    rate,
    output reg  [11:0]   length,
    output reg           rate_length_valid,
    output reg           vec_err,

    output wire [5:0]    data,
    output wire          data_valid,
    output wire          data_last,
    input  wire          data_ready,

    input  wire          abort,
    output wire          flushing,

    input  wire          phy_tx_done,
    output reg           txend_pulse,
    output reg           busy
);

localparam [3:0]
    IDLE          = 4'd0,
    READ_HEADER_1 = 4'd1,
    READ_HEADER_2 = 4'd2,
    READ_HEADER_3 = 4'd3,
    STREAM        = 4'd4,
    WAIT_TX_DONE  = 4'd5,
    DONE          = 4'd6,
    DROP          = 4'd7,
    FLUSH         = 4'd8;

reg [3:0] state, next_state;
reg [2:0] txpwr;
reg [11:0] byte_count;
reg [PW-1:0] rd_cnt;
reg [15:0] pos, sym_end, acc;
reg [4:0] nbits;
reg [1:0] empty_cnt;
reg fl_done, need_pulse;

reg [PW-1:0] wr_bin;
integer gi;
always @(*) begin
    wr_bin[PW-1] = gray_wr_pointer[PW-1];
    for (gi = PW-2; gi >= 0; gi = gi - 1)
        wr_bin[gi] = wr_bin[gi+1] ^ gray_wr_pointer[gi];
end

wire [PW-1:0] avail = wr_bin - rd_cnt;

reg [7:0] ndbps;
reg rate_wrong;
always @(*) begin
    rate_wrong = 1'b0;
    case (rate)
        4'b1011: ndbps = 8'd24;
        4'b1111: ndbps = 8'd36;
        4'b1010: ndbps = 8'd48;
        4'b1110: ndbps = 8'd72;
        4'b1001: ndbps = 8'd96;
        4'b1101: ndbps = 8'd144;
        4'b1000: ndbps = 8'd192;
        4'b1100: ndbps = 8'd216;
        default: begin
            ndbps = 8'd24;
            rate_wrong = 1'b1;
        end
    endcase
end

wire [15:0] total   = {1'b0, length, 3'b000};
wire [15:0] sym_sum = sym_end + {8'b0, ndbps};
wire [15:0] next_end = (sym_sum > total) ? total : sym_sum;
wire all_read = (byte_count == length);

wire [3:0] nw = (nbits >= 5'd6) ? 4'd6 : nbits[3:0];
wire [15:0] pos_n = pos + {12'b0, nw};
wire [15:0] need = (pos_n > sym_end) ? next_end : sym_end;
wire [15:0] avail16 = {{(16-PW){1'b0}}, avail};
wire [15:0] avail_b = pos + {11'b0, nbits} + (avail16 << 3);
wire gate_ok = (avail_b >= need);

wire have_word = (nbits >= 5'd6) || (all_read && nbits != 5'd0);
assign data_valid = (state == STREAM) && have_word && gate_ok;
assign data = acc[5:0];
assign data_last = data_valid && all_read && (nbits <= 5'd6);

wire take = data_valid && data_ready;
wire fin = take && data_last;
wire [4:0] n1 = take ? ((nbits >= 5'd6) ? nbits - 5'd6 : 5'd0) : nbits;
wire [15:0] a1 = take ? (acc >> 6) : acc;

wire [11:0] len_next = {length[11:8], fifo_data_out};
wire [15:0] total_next = {1'b0, len_next, 3'b000};
wire [15:0] first_nd = {8'b0, ndbps} - 16'd16;
wire [15:0] first_end = (total_next < first_nd) ? total_next : first_nd;

wire rd_data = (state == STREAM) && gate_ok && !empty &&
               !all_read && (n1 <= 5'd8);

assign ren = (((state == READ_HEADER_1) ||
               (state == READ_HEADER_2) ||
               (state == READ_HEADER_3) ||
               (state == DROP) ||
               (state == FLUSH)) && !empty) || rd_data;

assign flushing = (state == FLUSH);
wire abort_go = abort && (state != FLUSH) && (state != DONE);

always @(posedge clk or negedge rst) begin
    if (!rst) state <= IDLE;
    else state <= next_state;
end

always @(*) begin
    next_state = state;
    if (abort_go) next_state = FLUSH;
    else begin
        case (state)
            IDLE:          if (!empty) next_state = READ_HEADER_1;
            READ_HEADER_1: if (!empty) next_state = READ_HEADER_2;
            READ_HEADER_2: if (!empty) next_state = READ_HEADER_3;
            READ_HEADER_3: if (!empty) begin
                if (len_next == 0) next_state = DONE;
                else if (rate_wrong) next_state = DROP;
                else next_state = STREAM;
            end
            STREAM:        if (fin) next_state = WAIT_TX_DONE;
            DROP:          if (!empty && (byte_count + 12'd1 == length))
                               next_state = DONE;
            WAIT_TX_DONE:  if (phy_tx_done) next_state = DONE;
            DONE:          next_state = IDLE;
            FLUSH:         if (!abort && fl_done) next_state = IDLE;
            default:       next_state = IDLE;
        endcase
    end
end

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        rate <= 0;
        length <= 0;
        txpwr <= 0;
        byte_count <= 0;
        rd_cnt <= 0;
        pos <= 0;
        sym_end <= 0;
        acc <= 0;
        nbits <= 0;
        empty_cnt <= 0;
        fl_done <= 0;
        need_pulse <= 0;
        rate_length_valid <= 0;
        vec_err <= 0;
        txend_pulse <= 0;
        busy <= 0;
    end else begin
        rate_length_valid <= 1'b0;
        vec_err <= 1'b0;
        txend_pulse <= 1'b0;

        if (ren) rd_cnt <= rd_cnt + 1'b1;

        if (abort_go) begin
            need_pulse <= (state != IDLE) || !empty;
            empty_cnt <= 0;
            fl_done <= 0;
        end

        case (state)
            IDLE: begin
                byte_count <= 0;
                if (!empty) busy <= 1'b1;
            end

            READ_HEADER_1: if (!empty)
                rate <= fifo_data_out[3:0];

            READ_HEADER_2: if (!empty) begin
                txpwr <= fifo_data_out[6:4];
                length[11:8] <= fifo_data_out[3:0];
            end

            READ_HEADER_3: if (!empty) begin
                length[7:0] <= fifo_data_out;
                sym_end <= first_end;
                pos <= 0;
                acc <= 0;
                nbits <= 0;
                if ((len_next == 0) || rate_wrong)
                    vec_err <= 1'b1;
                else
                    rate_length_valid <= 1'b1;
            end

            STREAM: begin
                acc <= rd_data ? (a1 | ({8'b0, fifo_data_out} << n1)) : a1;
                nbits <= rd_data ? (n1 + 5'd8) : n1;
                if (rd_data) byte_count <= byte_count + 1'b1;
                if (take) begin
                    pos <= pos_n;
                    if ((pos_n >= sym_end) && (sym_end < total))
                        sym_end <= next_end;
                end
            end

            DROP: if (!empty)
                byte_count <= byte_count + 1'b1;

            DONE: begin
                txend_pulse <= 1'b1;
                busy <= 1'b0;
            end

            FLUSH: begin
                if (!empty) empty_cnt <= 0;
                else if (empty_cnt != 2'd3) empty_cnt <= empty_cnt + 1'b1;

                if ((empty_cnt == 2'd3) && !fl_done) begin
                    fl_done <= 1'b1;
                    busy <= 1'b0;
                    if (need_pulse && abort) txend_pulse <= 1'b1;
                end
                if (!abort && fl_done) begin
                    fl_done <= 1'b0;
                    empty_cnt <= 0;
                end
            end
            default: ;
        endcase
    end
end

endmodule
