module FFT_Output_Buffer #(
    parameter DATA_WIDTH = 16
)(
    input  wire clk,
    input  wire rst,

    // Write side (from FFT64_Top)
    input  wire                         wr_en,     // out_valid
    input  wire                         wr_last,   // out_last
    input  wire [5:0]                   wr_addr,   // out_index
    input  wire [2*DATA_WIDTH-1:0]      wr_data,   // {I_out, Q_out}

    // Frame status
    output reg                          frame_done, // 1-cycle pulse
    output reg                          done_bank,  // bank that holds the finished frame

    // Read side (synchronous read, data valid one clock after address)
    input  wire                         rd_bank,
    input  wire [5:0]                   rd_addr,
    output reg  [2*DATA_WIDTH-1:0]      rd_data
);

    (* ram_style = "distributed" *)
    reg [2*DATA_WIDTH-1:0] mem [0:127];

    reg wr_bank;

    always @(posedge clk) begin
        if (wr_en)
            mem[{wr_bank, wr_addr}] <= wr_data;
    end

    always @(posedge clk) begin
        rd_data <= mem[{rd_bank, rd_addr}];
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_bank    <= 1'b0;
            frame_done <= 1'b0;
            done_bank  <= 1'b0;
        end
        else begin
            frame_done <= 1'b0;

            if (wr_en && wr_last) begin
                frame_done <= 1'b1;
                done_bank  <= wr_bank;
                wr_bank    <= ~wr_bank;
            end
        end
    end

endmodule