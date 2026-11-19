module fifo_ctrl_top #(
    parameter ADDR_WIDTH = 6,
    parameter P_SIZE = ADDR_WIDTH + 1
)(
    input wire w_clk,
    input wire w_rstn,
    input wire [34:0] TXVECTOR,
    input wire [7:0] data_request,
    input wire PHY_TXEND_req,
    output wire PHY_TXSTART_conf,
    output wire data_confirm,
    output wire PHY_TXEND_CONF,

    input wire r_clk,
    input wire r_rstn,

    output wire [3:0] rate,
    output wire [11:0] length,
    output wire rate_length_valid,
    output wire vec_err,
    output wire [5:0] data,
    output wire data_valid,
    output wire data_last,
    output wire abort,
    output wire flushing,
    output wire txend_pulse,
    output wire busy,

    input wire data_ready,
    input wire phy_tx_done
);

wire wen, full, ren, empty;
wire [7:0] fifo_wdata, fifo_rdata;
wire [P_SIZE-1:0] sync_wr_ptr;
wire abort_req, txend_pulse_w;

write_ctrl U_WRITE_CTRL (
    .clk(w_clk), .rst(w_rstn), .TXVECTOR(TXVECTOR),
    .data_request(data_request), .PHY_TXEND_req(PHY_TXEND_req),
    .PHY_TXSTART_conf(PHY_TXSTART_conf), .data_confirm(data_confirm),
    .PHY_TXEND_CONF(PHY_TXEND_CONF), .full(full), .wen(wen),
    .fifo_wdata(fifo_wdata), .txend_pulse(txend_pulse_w),
    .abort_req(abort_req)
);

fifo_top #(.DATA_WIDTH(8), .ADDR_WIDTH(ADDR_WIDTH), .P_SIZE(P_SIZE)) U_FIFO (
    .w_clk(w_clk), .r_clk(r_clk), .w_rstn(w_rstn), .r_rstn(r_rstn),
    .wen(wen), .ren(ren), .data_in(fifo_wdata), .data_out(fifo_rdata),
    .full(full), .empty(empty), .sync_wr_ptr_out(sync_wr_ptr)
);

sync #(.DATA_SIZE(1)) U_SYNC_ABORT (
    .clk(r_clk), .rst(r_rstn), .unsync_ip(abort_req), .sync_op(abort)
);

fifo_read_ctrl #(.PW(P_SIZE)) U_READ_CTRL (
    .clk(r_clk), .rst(r_rstn), .empty(empty),
    .gray_wr_pointer(sync_wr_ptr), .ren(ren), .fifo_data_out(fifo_rdata),
    .rate(rate), .length(length), .rate_length_valid(rate_length_valid),
    .vec_err(vec_err), .data(data), .data_valid(data_valid),
    .data_last(data_last), .data_ready(data_ready), .abort(abort),
    .flushing(flushing), .phy_tx_done(phy_tx_done),
    .txend_pulse(txend_pulse), .busy(busy)
);

reg txend_tgl;
always @(posedge r_clk or negedge r_rstn) begin
    if (!r_rstn) txend_tgl <= 1'b0;
    else if (txend_pulse) txend_tgl <= ~txend_tgl;
end

wire txend_tgl_w;
sync #(.DATA_SIZE(1)) U_SYNC_TXEND (
    .clk(w_clk), .rst(w_rstn), .unsync_ip(txend_tgl), .sync_op(txend_tgl_w)
);

reg txend_tgl_w_d;
always @(posedge w_clk or negedge w_rstn) begin
    if (!w_rstn) txend_tgl_w_d <= 1'b0;
    else txend_tgl_w_d <= txend_tgl_w;
end
assign txend_pulse_w = txend_tgl_w ^ txend_tgl_w_d;

endmodule
