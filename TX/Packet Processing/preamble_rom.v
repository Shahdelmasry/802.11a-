module preamble_rom #(
    parameter ADDR_WIDTH      = 9,
    parameter INTEGER_BITS    = 2,
    parameter FRACTIONAL_BITS = 14,
    parameter ROM_FILE        = "preamble_rom_data.mem",
    parameter ROM_DEPTH       = 320,
    parameter LAST_ADDR       = ROM_DEPTH - 1
)(
    input  wire                                           clk,
    input  wire                                           rst_n,

    // ROM read request
    input  wire                                           rd_en,
    input  wire                          [ADDR_WIDTH-1:0] addr,
    output wire                                           rd_ready,

    // ROM output stream
    output reg  signed [INTEGER_BITS+FRACTIONAL_BITS-1:0] i_out,
    output reg  signed [INTEGER_BITS+FRACTIONAL_BITS-1:0] q_out,
    output reg                                            valid,
    output reg                                            last,

    // Downstream backpressure
    input  wire                                           out_ready
);

    localparam CHANNEL_WIDTH = INTEGER_BITS + FRACTIONAL_BITS;
    localparam DATA_WIDTH    = 2 * CHANNEL_WIDTH;

    // ROM storage
    reg [DATA_WIDTH-1:0] rom_array [0:ROM_DEPTH-1];

    // A read is accepted when the output register is empty
    // or the current output sample is being consumed.
    assign rd_ready = (!valid) || out_ready;

    // Initialize ROM
    initial begin
        $readmemh(ROM_FILE, rom_array);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i_out <= 0;
            q_out <= 0;
            valid <= 1'b0;
            last  <= 1'b0;
        end
        else begin

            // Accept a new ROM read request
            if (rd_en && rd_ready) begin

                if (addr < ROM_DEPTH) begin

                    i_out <= $signed(
                        rom_array[addr][DATA_WIDTH-1:CHANNEL_WIDTH]
                    );

                    q_out <= $signed(
                        rom_array[addr][CHANNEL_WIDTH-1:0]
                    );

                    valid <= 1'b1;
                    last  <= (addr == LAST_ADDR);

                end
                else begin
                    // Invalid address: do not produce a valid sample
                    i_out <= 0;
                    q_out <= 0;
                    valid <= 1'b0;
                    last  <= 1'b0;
                end

            end

            // Current sample consumed, no replacement requested
            else if (valid && out_ready) begin
                i_out <= 0;
                q_out <= 0;
                valid <= 1'b0;
                last  <= 1'b0;
            end

        end
    end

endmodule
