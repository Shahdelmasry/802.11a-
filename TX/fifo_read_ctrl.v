
module fifo_read_ctrl (
    input  wire       clk,
    input  wire       rst,

    // FIFO interface
    input  wire       empty,
    input  wire [8:0] ndbps,
    input  wire [5:0] gray_wr_pointer,
    output wire       ren,
    input  wire [7:0] fifo_data_out,

    // PHY configuration outputs
    output reg [24:0] header,
    output reg        header_valid,

    // PHY payload interface
    output reg  [7:0] data,
    output wire       data_valid,
    input  wire       data_ready,

    // Transmission completion
    input  wire       phy_tx_done,
    output reg        txend_pulse,
    output reg        busy
);

// FSM STATES
localparam [3:0]
    IDLE          = 4'd0,

    READ_HEADER_1 = 4'd1,
    READ_HEADER_2 = 4'd2,
    READ_HEADER_3 = 4'd3,
    SEND_HEADER   = 4'd4,

    WAIT_DATA     = 4'd5,
    READ_DATA     = 4'd6,
    CAP_DATA      = 4'd7,
    SEND_DATA     = 4'd8,

    WAIT_TX_DONE  = 4'd9,
    DONE          = 4'd10;

// INTERNAL REGISTERS
reg [3:0] current_state;
reg [3:0] next_state;
reg [11:0] byte_count;
reg start;
// FIFO READ CONTROL
// Assert read enable only in FIFO read states.
// Never read when FIFO is empty.

assign ren = ((current_state == READ_HEADER_1) ||
              (current_state == READ_HEADER_2) ||
              (current_state == READ_HEADER_3) ||
              (current_state == READ_DATA))
              && !empty;

// PHY VALID CONTROL
assign data_valid = (current_state == SEND_DATA);

//Start reading
wire [5:0] wr_pointer;
assign wr_pointer = gray_wr_pointer ^ (gray_wr_pointer >> 1); // Convert Gray code to binary
start = (wr_pointer == ndbps+24) && (current_state == IDLE);

// FSM STATE REGISTER
always @(posedge clk or negedge rst) begin
    if (!rst)
        current_state <= IDLE;
    else
        current_state <= next_state;
end
// NEXT STATE LOGIC
always @(*) begin
    next_state = current_state;
    case (current_state)
        IDLE: begin
            if (start)
                next_state = READ_HEADER_1;
        end
        READ_HEADER_1: begin
                next_state = READ_HEADER_2;
        end
        READ_HEADER_2: begin
                next_state = READ_HEADER_3;
        end
        READ_HEADER_3: begin
                next_state = SEND_HEADER;
        end
        SEND_HEADER: begin
            next_state = WAIT_DATA;
        end
        WAIT_DATA: begin
            if (byte_count == length)
                next_state = WAIT_TX_DONE;
            else
                next_state = READ_DATA;
        end
        READ_DATA: begin
                next_state = CAP_DATA;
        end
        CAP_DATA: begin
            next_state = SEND_DATA;
        end
        // Hold data until PHY accepts it
        SEND_DATA: begin
            if (data_ready) begin
                if (byte_count == length - 1'b1)
                    next_state = WAIT_TX_DONE;
                else
                    next_state = WAIT_DATA;
            end
        end
        WAIT_TX_DONE: begin
            if (phy_tx_done)
                next_state = DONE;
        end
        DONE: begin
            next_state = IDLE;
        end
        default: begin
            next_state = IDLE;
        end
    endcase
end
// DATA AND HEADER REGISTERS
always @(posedge clk or negedge rst) begin
    if (!rst) begin
        data         <= 0;
        byte_count   <= 0;
        header_valid <= 0;
        txend_pulse  <= 0;
        busy         <= 0;
    end
    else begin
        header_valid <= 0;
        txend_pulse  <= 0;
        case (current_state)
            IDLE: begin
                if (start) begin
                    byte_count <= 0;
                    busy       <= 1;
                end
            end
            READ_HEADER_1: begin
                header[24:17] <= fifo_data_out;
            end
            READ_HEADER_2: begin
                header[23:16] <= fifo_data_out;
            end
            READ_HEADER_3: begin
                header[15:0]  <= fifo_data_out;
                header_valid <= 1;
            end
            CAP_DATA: begin
                data <= fifo_data_out;
            end
            SEND_DATA: begin
                if (data_ready)
                    byte_count <= byte_count + 1'b1;
            end
            DONE: begin
                txend_pulse <= 1;
                busy        <= 0;
            end
        endcase
    end
end
endmodule
