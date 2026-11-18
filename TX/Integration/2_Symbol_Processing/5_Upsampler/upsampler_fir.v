

module upsampler_fir #(
    parameter DATA_WIDTH  = 16,
    parameter COEFF_WIDTH = 16,
    parameter NUM_TAPS    = 43,
    parameter FRAC_BITS   = 14
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // Upstream (from Zero-Insertion Upsampler)
    input  wire signed [DATA_WIDTH-1:0] in_i,
    input  wire signed [DATA_WIDTH-1:0] in_q,
    input  wire                         in_valid,
    input  wire                         in_last,
    output wire                         in_ready,

    // Downstream (to DAC)
    output reg  signed [DATA_WIDTH-1:0] out_i,
    output reg  signed [DATA_WIDTH-1:0] out_q,
    output reg                          out_valid,
    output reg                          out_last,
    input  wire                         out_ready
);



    localparam HALF      = (NUM_TAPS + 1) / 2;          // unique coefficients
    localparam PROD_W    = DATA_WIDTH + 1 + COEFF_WIDTH; // pre-added sample x coefficient
    localparam ACC_WIDTH = PROD_W + $clog2(HALF);

    localparam G1 = (HALF + 3) / 4;                      // 4-input groups (level 1-2)
    localparam G2 = (G1 + 2) / 3;                        // 3-input groups (level 3-4)

    // A new input is accepted only when the pipeline can advance.
    assign in_ready = out_ready;

    // Q2.14 interpolation-filter coefficients.
    wire signed [COEFF_WIDTH-1:0] coeff [0:NUM_TAPS-1];

    assign coeff[0] =  16'sd363;
    assign coeff[1] =  16'sd564;
    assign coeff[2] =  16'sd715;
    assign coeff[3] =  16'sd614;
    assign coeff[4] =  16'sd207;
    assign coeff[5] = -16'sd388;
    assign coeff[6] = -16'sd894;
    assign coeff[7] = -16'sd996;
    assign coeff[8] = -16'sd530;
    assign coeff[9] =  16'sd372;
    assign coeff[10] =  16'sd1272;
    assign coeff[11] =  16'sd1600;
    assign coeff[12] =  16'sd970;
    assign coeff[13] = -16'sd542;
    assign coeff[14] = -16'sd2289;
    assign coeff[15] = -16'sd3251;
    assign coeff[16] = -16'sd2465;
    assign coeff[17] =  16'sd483;
    assign coeff[18] =  16'sd5149;
    assign coeff[19] =  16'sd10287;
    assign coeff[20] =  16'sd14282;
    assign coeff[21] =  16'sd15788;
    assign coeff[22] =  16'sd14282;
    assign coeff[23] =  16'sd10287;
    assign coeff[24] =  16'sd5149;
    assign coeff[25] =  16'sd483;
    assign coeff[26] = -16'sd2465;
    assign coeff[27] = -16'sd3251;
    assign coeff[28] = -16'sd2289;
    assign coeff[29] = -16'sd542;
    assign coeff[30] =  16'sd970;
    assign coeff[31] =  16'sd1600;
    assign coeff[32] =  16'sd1272;
    assign coeff[33] =  16'sd372;
    assign coeff[34] = -16'sd530;
    assign coeff[35] = -16'sd996;
    assign coeff[36] = -16'sd894;
    assign coeff[37] = -16'sd388;
    assign coeff[38] =  16'sd207;
    assign coeff[39] =  16'sd614;
    assign coeff[40] =  16'sd715;
    assign coeff[41] =  16'sd564;
    assign coeff[42] =  16'sd363;

    // ---------------------------------------------------------
    // Stage 1: sample shift register (x[0] = newest)
    // ---------------------------------------------------------
    reg signed [DATA_WIDTH-1:0] delay_i [0:NUM_TAPS-1];
    reg signed [DATA_WIDTH-1:0] delay_q [0:NUM_TAPS-1];
    reg [7:0] tail_count;          // outputs still affected by the last valid input
    reg       s1_valid;
    reg       s1_last;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_TAPS; i = i + 1) begin
                delay_i[i] <= {DATA_WIDTH{1'b0}};
                delay_q[i] <= {DATA_WIDTH{1'b0}};
            end
            tail_count <= 8'd0;
            s1_valid   <= 1'b0;
            s1_last    <= 1'b0;
        end
        else if (out_ready) begin
            for (i = NUM_TAPS-1; i > 0; i = i - 1) begin
                delay_i[i] <= delay_i[i-1];
                delay_q[i] <= delay_q[i-1];
            end

            // No valid input: shift in a zero (flushes the tail).
            delay_i[0] <= in_valid ? in_i : {DATA_WIDTH{1'b0}};
            delay_q[0] <= in_valid ? in_q : {DATA_WIDTH{1'b0}};

            if (in_valid)
                tail_count <= NUM_TAPS - 1;
            else if (tail_count != 8'd0)
                tail_count <= tail_count - 8'd1;

            s1_valid <= in_valid || (tail_count != 8'd0);
            s1_last  <= in_valid && in_last;
        end
    end

    // ---------------------------------------------------------
    // Stage 2: symmetric pre-add and multiply (registered products)
    // ---------------------------------------------------------
    reg signed [PROD_W-1:0] prod_i [0:HALF-1];
    reg signed [PROD_W-1:0] prod_q [0:HALF-1];
    reg s2_valid;
    reg s2_last;

    integer k;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < HALF; k = k + 1) begin
                prod_i[k] <= {PROD_W{1'b0}};
                prod_q[k] <= {PROD_W{1'b0}};
            end
            s2_valid <= 1'b0;
            s2_last  <= 1'b0;
        end
        else if (out_ready) begin
            for (k = 0; k < HALF; k = k + 1) begin
                if (k == NUM_TAPS-1-k) begin
                    // centre tap (odd NUM_TAPS)
                    prod_i[k] <= $signed(delay_i[k]) * $signed(coeff[k]);
                    prod_q[k] <= $signed(delay_q[k]) * $signed(coeff[k]);
                end
                else begin
                    prod_i[k] <= ($signed(delay_i[k]) + $signed(delay_i[NUM_TAPS-1-k])) * $signed(coeff[k]);
                    prod_q[k] <= ($signed(delay_q[k]) + $signed(delay_q[NUM_TAPS-1-k])) * $signed(coeff[k]);
                end
            end
            s2_valid <= s1_valid;
            s2_last  <= s1_last;
        end
    end

    // ---------------------------------------------------------
    // Stage 3: adder tree levels 1-2 (registered group sums)
    // grp1[j] = (p[4j] + p[4j+1]) + (p[4j+2] + p[4j+3]), missing terms = 0
    // ---------------------------------------------------------
    reg signed [ACC_WIDTH-1:0] pad_i [0:4*G1-1];
    reg signed [ACC_WIDTH-1:0] pad_q [0:4*G1-1];
    integer m;

    always @(*) begin
        for (m = 0; m < 4*G1; m = m + 1) begin
            if (m < HALF) begin
                pad_i[m] = prod_i[m];
                pad_q[m] = prod_q[m];
            end
            else begin
                pad_i[m] = {ACC_WIDTH{1'b0}};
                pad_q[m] = {ACC_WIDTH{1'b0}};
            end
        end
    end

    reg signed [ACC_WIDTH-1:0] grp1_i [0:3*G2-1];
    reg signed [ACC_WIDTH-1:0] grp1_q [0:3*G2-1];
    reg s3_valid;
    reg s3_last;

    integer g;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (g = 0; g < 3*G2; g = g + 1) begin
                grp1_i[g] <= {ACC_WIDTH{1'b0}};
                grp1_q[g] <= {ACC_WIDTH{1'b0}};
            end
            s3_valid <= 1'b0;
            s3_last  <= 1'b0;
        end
        else if (out_ready) begin
            for (g = 0; g < 3*G2; g = g + 1) begin
                if (g < G1) begin
                    grp1_i[g] <= (pad_i[4*g]   + pad_i[4*g+1]) +
                                 (pad_i[4*g+2] + pad_i[4*g+3]);
                    grp1_q[g] <= (pad_q[4*g]   + pad_q[4*g+1]) +
                                 (pad_q[4*g+2] + pad_q[4*g+3]);
                end
                else begin
                    grp1_i[g] <= {ACC_WIDTH{1'b0}};
                    grp1_q[g] <= {ACC_WIDTH{1'b0}};
                end
            end
            s3_valid <= s2_valid;
            s3_last  <= s2_last;
        end
    end

    // ---------------------------------------------------------
    // Stage 4: adder tree levels 3-4 (registered group sums)
    // grp2[j] = (grp1[3j] + grp1[3j+1]) + grp1[3j+2]
    // ---------------------------------------------------------
    reg signed [ACC_WIDTH-1:0] grp2_i [0:G2-1];
    reg signed [ACC_WIDTH-1:0] grp2_q [0:G2-1];
    reg s4_valid;
    reg s4_last;

    integer h;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (h = 0; h < G2; h = h + 1) begin
                grp2_i[h] <= {ACC_WIDTH{1'b0}};
                grp2_q[h] <= {ACC_WIDTH{1'b0}};
            end
            s4_valid <= 1'b0;
            s4_last  <= 1'b0;
        end
        else if (out_ready) begin
            for (h = 0; h < G2; h = h + 1) begin
                grp2_i[h] <= (grp1_i[3*h] + grp1_i[3*h+1]) + grp1_i[3*h+2];
                grp2_q[h] <= (grp1_q[3*h] + grp1_q[3*h+1]) + grp1_q[3*h+2];
            end
            s4_valid <= s3_valid;
            s4_last  <= s3_last;
        end
    end

    // ---------------------------------------------------------
    // Stage 5: final add, scale, saturate (output register)
    // ---------------------------------------------------------
    reg signed [ACC_WIDTH-1:0] sum_i;
    reg signed [ACC_WIDTH-1:0] sum_q;
    integer n;

    always @(*) begin
        sum_i = {ACC_WIDTH{1'b0}};
        sum_q = {ACC_WIDTH{1'b0}};
        for (n = 0; n < G2; n = n + 1) begin
            sum_i = sum_i + grp2_i[n];
            sum_q = sum_q + grp2_q[n];
        end
    end

    wire signed [ACC_WIDTH-1:0] scaled_i = sum_i >>> FRAC_BITS;
    wire signed [ACC_WIDTH-1:0] scaled_q = sum_q >>> FRAC_BITS;

    localparam signed [DATA_WIDTH-1:0] MAX_OUT =
        {1'b0, {(DATA_WIDTH-1){1'b1}}};
    localparam signed [DATA_WIDTH-1:0] MIN_OUT =
        {1'b1, {(DATA_WIDTH-1){1'b0}}};

    localparam signed [ACC_WIDTH-1:0] MAX_ACC =
        {{(ACC_WIDTH-DATA_WIDTH){1'b0}}, MAX_OUT};
    localparam signed [ACC_WIDTH-1:0] MIN_ACC =
        {{(ACC_WIDTH-DATA_WIDTH){1'b1}}, MIN_OUT};

    // Output register holds its contents during downstream backpressure.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_i     <= {DATA_WIDTH{1'b0}};
            out_q     <= {DATA_WIDTH{1'b0}};
            out_valid <= 1'b0;
            out_last  <= 1'b0;
        end
        else if (out_ready) begin
            out_valid <= s4_valid;
            out_last  <= s4_last;

            if (scaled_i > MAX_ACC)
                out_i <= MAX_OUT;
            else if (scaled_i < MIN_ACC)
                out_i <= MIN_OUT;
            else
                out_i <= scaled_i[DATA_WIDTH-1:0];

            if (scaled_q > MAX_ACC)
                out_q <= MAX_OUT;
            else if (scaled_q < MIN_ACC)
                out_q <= MIN_OUT;
            else
                out_q <= scaled_q[DATA_WIDTH-1:0];
        end
    end

endmodule
