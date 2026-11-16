module seed_to_index #(
    parameter DATA_LENGTH = 6
) (
    input  wire                        clk,        // postive edge clk 
    input  wire                        rst,        // negtive edge rst
    input  wire                        enable,     // from fsm: 1 = a data word is valid in this cycle, 0 = pause
    input  wire                        packet_end, // from fsm: 1 together with the LAST word of the packet (or alone = abort)
    input  wire    [6:0]               seed,       // from fsm or seed_gen
    output reg                         pkt_start,  // 1 when a new packet starts (used by seed_gen)
    output reg                         mem_en, 
    output reg                         scr_en, 
    output reg   [6:0]                 index       // from 1 to 126 there is a place for 0 but we will never use it. 
    );

//////////////////LOOK UP TABLE 
    reg [6:0] lut_mem [0:127];
    initial $readmemb("seed_to_index.mem", lut_mem); // converts any seed to its start index in the 127-bit sequence

/////////////////fsm
localparam [1:0]  IDLE       = 2'b00,  // no packet is running
                  lut        = 2'b01,  // converting seed to index (ONLY at the start of a packet)
                  scrambling = 2'b11;  // packet is running (enable=0 inside this state = pause, nothing is lost)

reg [1:0]  next_state;
reg [1:0]  current_state;
reg [6:0]  index_q;

/////////////////state transtion 
always @(posedge clk or negedge rst) 
    begin
        if (!rst)
            begin
                current_state <= IDLE;
                index_q       <= 0;
            end
        else
            begin
                current_state <= next_state;
                if (mem_en) index_q <= index;      // index_q keeps its value while paused
            end
    end

////////////////////next state logic & output logic 
always @(*) 
    begin
        next_state = current_state;
        pkt_start  = 1'b0;
        mem_en     = 1'b0;
        scr_en     = 1'b0; 
        index      = 7'b0;
        case (current_state)
            IDLE:
            begin
                if (enable) 
                begin
                    pkt_start  = 1'b1;
                    next_state = lut;
                end 
            end 
            lut:
            begin
                next_state = scrambling;
                index      = lut_mem[seed];
                mem_en     = 1;
            end
            scrambling:
            begin
                if (enable) 
                begin
                    index  = (index_q + DATA_LENGTH) % 127;
                    mem_en = 1;
                    scr_en = 1;
                end 
                // enable = 0 : pause. mem_en = scr_en = 0, so Memory and index_q hold their values
                // and the packet continues from the same place when enable comes back.
                if (packet_end) next_state = IDLE;   // the only way to finish (or abort) a packet
            end
            default:
                next_state = IDLE; 
        endcase
    end

endmodule
