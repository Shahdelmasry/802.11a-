module convolution_encoder #(
    parameter DATA_WIDTH = 6
)(
    input  wire                          clk, // postive edge clk 
    input  wire                          rst, // negtive edge rst (Async)
    input  wire                          enable, // from fsm it should be 1 till tha whole packet end not with each word 
    input  wire [DATA_WIDTH-1:0]         data_in, // from scrambler 
    input  wire [1:0]                    rate, // fsm : 0:1/2 1:2/3 2:3/4 there is no 3

    output reg  [(DATA_WIDTH*2)-1:0]     data_out, //fsm : we should take output when 1/2 from here   
    output reg  [(DATA_WIDTH*3/2)-1:0]   data_out_23,//fsm : we should take output when 2/3 from here   
    output reg  [(DATA_WIDTH*4/3)-1:0]   data_out_34,//fsm : we should take output when 3/4 from here   

    output reg                     out_valid //fsm : when data is ready it wil be 1 as long as enable is 1 
);
/////////////////////////////////////// internal signals 
    reg [5:0] window;       
    reg [5:0] next_window;
    reg [DATA_WIDTH-1:0] a, b;

    integer i;
/////////////////////////////////////// convolution encoder logic 
    always @(*) begin
        next_window = window;
        a = {DATA_WIDTH{1'b0}};
        b = {DATA_WIDTH{1'b0}};

        for (i = 0; i < DATA_WIDTH; i = i + 1) begin
            // 133 octal = 1011011
            a[i] = data_in[i] ^ next_window[1] ^ next_window[2]
                                ^ next_window[4] ^ next_window[5];
            // 171 octal = 1111001
            b[i] = data_in[i] ^ next_window[0] ^ next_window[1]
                                ^ next_window[2] ^ next_window[5];

            next_window = {next_window[4:0], data_in[i]};
        end
    end
    
        
        
   
    always @(posedge clk or negedge rst) begin
        if (!rst) 
        begin
            window    <= 6'b0;
            data_out    <= 0;
            data_out_23<=0;
            data_out_34<=0;
            out_valid <= 1'b0;
        end 
        else 
        begin
            out_valid <= enable;
            if (enable) 
            begin
                //puncture 
                case (rate)
                    2'd0:
                        begin
                            data_out <= {b[5],a[5],b[4],a[4],b[3],a[3],b[2],a[2],b[1],a[1],b[0],a[0]};
                             window <= next_window;
                        end
                    2'd1:
                        begin
                            data_out_23 <= {a[5],b[4],a[4],a[3],b[2],a[2],a[1],b[0],a[0]};
                             window <= next_window;
                        end
                    2'd2:
                        begin
                            data_out_34 <= {b[5],a[4],b[3],a[3],b[2],a[1],b[0],a[0]}; 
                             window <= next_window;       
                        end
                    default: 
                        begin
                            data_out <= 0;
                            data_out_23 <= 0;
                            data_out_34 <= 0;
                        end
                 endcase
        
                
            end
        end
    end

endmodule