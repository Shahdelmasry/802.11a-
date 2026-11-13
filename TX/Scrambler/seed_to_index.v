module seed_to_index #(
    parameter DATA_LENGTH = 6
) (
    input  wire                        clk,// postive edge clk 
    input  wire                        rst,// negtive edge rst
    input  wire                        enable,// that come from fsm 
    input  wire    [6:0]               seed,  // from fsm  
    output reg                         mem_en, 
    output reg                         scr_en, 
    output reg   [6:0]                 index //from 1 to 126 there is a place for 0 but we will never use it. 
    );
               
//////////////////LOOK UP TABLE 
    reg [6:0] lut_mem [0:127];
    initial $readmemb("seed_to_index.mem", lut_mem); // 2D mem to hold lut converting any seed to index 
/////////////////fsm
//////////////////states encoding (gray coded )
localparam [2:0]      IDLE =2'b00, //no action enable =0
                      lut=2'b01,// converting seed to index in memory 
                      scrambling =2'b11;// scrambling data 

//////////////////internal signals 
reg [2:0]              next_state;
reg [2:0]              current_state;


/////////////////state transtion 
always @(posedge clk or negedge rst ) 
    begin
        if(!rst)
            begin
                current_state<=IDLE;
            end
        else
            begin
                current_state<=next_state;
            end
    
    end


////////////////////next state logic & output logic 
always @(*) 
    begin
        next_state=IDLE;
        mem_en=1'b0;
        scr_en=1'b0; 
        index=7'b0;
        case (current_state)
            IDLE:
            begin
                if (enable) 
                begin
                    next_state=lut;

                end 
                else 
                begin
                    next_state=IDLE;  
                end
            end 
            lut:
            begin
                next_state=scrambling;
                index=lut_mem[seed];
                mem_en=1;
            end
            scrambling:
            begin
                if (enable) 
                begin
                    index = (index + DATA_LENGTH) % 127;
                    next_state=scrambling;
                    mem_en=1;
                    scr_en=1;
                end 
                else if (!enable)
                begin
                    next_state=IDLE;
                end
                
            end
            default:
                next_state=IDLE; 
        endcase
    end

                      
endmodule