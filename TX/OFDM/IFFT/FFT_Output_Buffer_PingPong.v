module FFT_Output_Buffer_PingPong #(
    parameter DATA_WIDTH = 16
)(
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         wr_en,
    input  wire                         wr_last,
    input  wire [5:0]                   wr_addr,
    input  wire [2*DATA_WIDTH-1:0]      wr_data,
    output wire                         wr_ready,
    output reg                          frame_done,
    output reg                          done_bank,
    input  wire                         rd_bank,
    input  wire [5:0]                   rd_addr,
    output reg  [2*DATA_WIDTH-1:0]      rd_data,
    input  wire                         rd_release,
    input  wire                         rd_release_bank
);
    (* ram_style = "distributed" *) reg [2*DATA_WIDTH-1:0] mem [0:127];
    reg wr_bank;
    reg [1:0] bank_full;

    assign wr_ready = ~bank_full[wr_bank];

    always @(posedge clk) begin
        if (wr_en && wr_ready)
            mem[{wr_bank, wr_addr}] <= wr_data;
    end

    always @(posedge clk)
        rd_data <= mem[{rd_bank, rd_addr}];

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            wr_bank <= 1'b0;
            bank_full <= 2'b00;
            frame_done <= 1'b0;
            done_bank <= 1'b0;
        end else begin
            frame_done <= 1'b0;
            if (rd_release)
                bank_full[rd_release_bank] <= 1'b0;
            if (wr_en && wr_ready && wr_last) begin
                bank_full[wr_bank] <= 1'b1;
                frame_done <= 1'b1;
                done_bank <= wr_bank;
                wr_bank <= ~wr_bank;
            end
        end
    end
endmodule
