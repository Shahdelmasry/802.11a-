module input_buffer(
    parameter TAIL_BITS   = 6
)(       
    input clk,
    input rst,
    input wr_en,
    input [7:0] wr_byte,
    input read_en,
    input start_of_data, // first byte of data 
    input end_of_data,  // last byte of data 
    input [7:0] npad,
    output reg [5:0] data_out
);

// 8-to-6 gearbox
reg [23:0] shift_reg;    // holds up to 3 bytes
reg [4:0]  bit_count;   // bits currently in shift_reg

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        shift_reg <= 24'd0;
        bit_count <= 5'd0;
    end
    else if (start_of_data) begin
        // add service (16 bits)
        shift_reg <= {wr_byte,16'd0};
        bit_count <= 16;
    end
    else if (end_of_data) begin
        // add tail and padding bits
        if (npad < 11)
        begin
        shift_reg <= {npad{1'b0}, TAIL_BITS{1'b0}, wr_byte};
        bit_count <= bit_count + TAIL_BITS + npad;
        end
        else begin
            for ()
        end
    end
    else begin
        // Load new byte when available and space permits
        if (wr_en && bit_count <= 16) begin
            shift_reg <= {shift_reg[15:0], wr_byte};
            bit_count <= bit_count + 8;
        end
        // Output 6 bits when read_en
        if (read_en && bit_count >= 6) begin
            shift_reg <= shift_reg >> 6;
            bit_count <= bit_count - 6;
            data_out  <= shift_reg[5:0];
        end
    end
    
// pading calculations 
    wire [15:0] total_bits_before_pad;
    wire [8:0]  nsym;
    wire [15:0] total_bits_after_pad;

    assign total_bits_before_pad = SERVICE_BITS + (length << 3) + TAIL_BITS;
    assign nsym = (total_bits_before_pad + ndbps - 1) / ndbps;
    assign total_bits_after_pad = nsym * ndbps;
    assign npad = total_bits_after_pad - total_bits_before_pad;

end
endmodule