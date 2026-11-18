module PE_Sequencer (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire sample_en,

    output wire [5:0] sample_count,

    // PE1 - Delay 32
    output wire pe1_s0_32,
    output wire pe1_s1_32,
    output wire pe1_s2_32,

    // PE2 - Delay 16
    output wire pe2_s0_16,
    output wire pe2_s1_16,

    // PE3 - Delay 8
    output wire pe3_s0_8,

    // PE1 - Delay 4
    output wire pe1_s0_4,
    output wire pe1_s1_4,
    output wire pe1_s2_4,

    // PE2 - Delay 2
    output wire pe2_s0_2,
    output wire pe2_s1_2,

    // PE3 - Delay 1
    output wire pe3_s0_1
);

    reg [5:0] count;

    // start must not be asserted in the same cycle as sample_en
    always @(posedge clk or negedge rst) begin
        if (!rst)
            count <= 6'd0;
        else if (start)
            count <= 6'd0;
        else if (sample_en)
            count <= count + 1'b1;
    end

    assign sample_count = count;

    // PE1 - Delay 32: W8^j on diff, j = count[4:3]
    assign pe1_s0_32 = count[5];
    assign pe1_s1_32 = count[5] && count[3];
    assign pe1_s2_32 = count[5] && count[4];

    // PE2 - Delay 16: -j when count[3] = 1
    assign pe2_s0_16 = count[4];
    assign pe2_s1_16 = count[4] && count[3];

    // PE3 - Delay 8
    assign pe3_s0_8  = count[3];

    // PE1 - Delay 4 
    assign pe1_s0_4  = count[2];
    assign pe1_s1_4  = count[2] && count[0];
    assign pe1_s2_4  = count[2] && count[1];

    // PE2 - Delay 2
    assign pe2_s0_2  = count[1];
    assign pe2_s1_2  = count[1] && count[0];

    // PE3 - Delay 1
    assign pe3_s0_1  = count[0];

endmodule