module FFT64_Top #(
    parameter DATA_WIDTH = 16
)(
    input  wire clk,
    input  wire rst,
    input  wire start,        // sync clear of the counter, not together with sample_en
    input  wire sample_en,
    input  wire ifft_mode,

    input  wire signed [DATA_WIDTH-1:0] I_in,
    input  wire signed [DATA_WIDTH-1:0] Q_in,

    output wire        out_valid,
    output wire        out_last,    // last output sample of a frame
    output wire [5:0]  out_index,   // natural-order index of the current output

    output wire signed [DATA_WIDTH-1:0] I_out,
    output wire signed [DATA_WIDTH-1:0] Q_out
);

    
    // =====================================================
    // INPUT CONJUGATION (IFFT mode)
    // =====================================================
    wire [2*DATA_WIDTH-1:0] conj_input;

    Complex_Conjugate #(.DATA_WIDTH(DATA_WIDTH)) U_INPUT_CONJ (
        .data_in  ({I_in, Q_in}),
        .data_out (conj_input)
    );

    wire signed [DATA_WIDTH-1:0] fft_input_I;
    wire signed [DATA_WIDTH-1:0] fft_input_Q;

    assign fft_input_I = I_in;
    assign fft_input_Q = ifft_mode ? $signed(conj_input[DATA_WIDTH-1:0]) : Q_in;

    // R0: input register
    reg signed [DATA_WIDTH-1:0] r0_I, r0_Q;

    always @(posedge clk) begin
        if (sample_en) begin
            r0_I <= fft_input_I;
            r0_Q <= fft_input_Q;
        end
    end

    // =====================================================
    // Scaling: divide by 2 in every butterfly (both modes).
    // FFT output = DFT/64, IFFT output = IDFT (includes 1/64).
    // =====================================================
    wire scale_en;
    assign scale_en = 1'b1;

    // =====================================================
    // CONTROL
    // =====================================================
    wire [5:0] sample_count;

    wire c_pe1_s0_32, c_pe1_s1_32, c_pe1_s2_32;
    wire c_pe2_s0_16, c_pe2_s1_16;
    wire c_pe3_s0_8;
    wire c_pe1_s0_4,  c_pe1_s1_4,  c_pe1_s2_4;
    wire c_pe2_s0_2,  c_pe2_s1_2;
    wire c_pe3_s0_1;

    PE_Sequencer U_PE_Sequencer (
        .clk          (clk),
        .rst          (rst),
        .start        (start),
        .sample_en    (sample_en),
        .sample_count (sample_count),

        .pe1_s0_32    (c_pe1_s0_32),
        .pe1_s1_32    (c_pe1_s1_32),
        .pe1_s2_32    (c_pe1_s2_32),
        .pe2_s0_16    (c_pe2_s0_16),
        .pe2_s1_16    (c_pe2_s1_16),
        .pe3_s0_8     (c_pe3_s0_8),
        .pe1_s0_4     (c_pe1_s0_4),
        .pe1_s1_4     (c_pe1_s1_4),
        .pe1_s2_4     (c_pe1_s2_4),
        .pe2_s0_2     (c_pe2_s0_2),
        .pe2_s1_2     (c_pe2_s1_2),
        .pe3_s0_1     (c_pe3_s0_1)
    );

    // =====================================================
    // TWIDDLE CONTROL
    // =====================================================
    wire [5:0] twiddle_k;
    wire       sequencer_multiplier_enable;

    wire [2:0] operation_type;
    wire [2:0] coeff_sel;
    wire       swap;
    wire [4:0] reduced_m;
    wire [2:0] special_sel;
    wire       mapper_valid;
    wire       mapper_multiplier_enable;

    Twiddle_Sequencer #(.PHASE_OFFSET(8)) U_Twiddle_Sequencer (
        .sample_count      (sample_count),
        .twiddle_k         (twiddle_k),
        .multiplier_enable (sequencer_multiplier_enable),
        .group_r           (),
        .index_n           ()
    );

    Twiddle_Mapper U_Twiddle_Mapper (
        .k                 (twiddle_k),
        .operation_type    (operation_type),
        .coeff_sel         (coeff_sel),
        .swap              (swap),
        .reduced_m         (reduced_m),
        .special_sel       (special_sel),
        .multiplier_enable (mapper_multiplier_enable),
        .valid             (mapper_valid)
    );

    wire cm_s1, cm_s2, cm_s3, cm_s4, cm_s5;
    wire valid_operation;

    Reconfigurable_Multiplier_Controller U_CM_Controller (
        .operation_type  (operation_type),
        .s1(cm_s1), .s2(cm_s2), .s3(cm_s3), .s4(cm_s4), .s5(cm_s5),
        .valid_operation (valid_operation)
    );

    wire cm_enable;
    assign cm_enable = sequencer_multiplier_enable &&
                       mapper_multiplier_enable    &&
                       valid_operation;

    // =====================================================
    // CONTROL ALIGNMENT (sample_en delay lines)
    // ctl_xxx_d[n] = control value of n samples ago
    // =====================================================
    localparam CORE_PIPE = 5;

    wire [5:0] ctl_s123;        // stages 1-3          : delay 1
    wire [5:0] ctl_cm_in;       // RCM before R2       : delay 2
    wire [3:0] ctl_cm_out;      // RCM after R2 + MUX  : delay 3
    wire [4:0] ctl_s45;         // stages 4-5          : delay 4
    wire       ctl_s6;          // stage 6             : delay 5

    assign ctl_s123   = {c_pe1_s0_32, c_pe1_s1_32, c_pe1_s2_32,
                         c_pe2_s0_16, c_pe2_s1_16, c_pe3_s0_8};
    assign ctl_cm_in  = {cm_s1, cm_s2, coeff_sel, swap};
    assign ctl_cm_out = {cm_s3, cm_s4, cm_s5, cm_enable};
    assign ctl_s45    = {c_pe1_s0_4, c_pe1_s1_4, c_pe1_s2_4,
                         c_pe2_s0_2, c_pe2_s1_2};
    assign ctl_s6     = c_pe3_s0_1;

    reg [5:0] ctl_s123_d1;
    reg [5:0] ctl_cm_in_d   [1:2];
    reg [3:0] ctl_cm_out_d  [1:3];
    reg [4:0] ctl_s45_d     [1:4];
    reg       ctl_s6_d      [1:5];

    integer d;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            ctl_s123_d1 <= 6'd0;
            for (d = 1; d <= 2; d = d + 1) ctl_cm_in_d[d]  <= 6'd0;
            for (d = 1; d <= 3; d = d + 1) ctl_cm_out_d[d] <= 4'd0;
            for (d = 1; d <= 4; d = d + 1) ctl_s45_d[d]    <= 5'd0;
            for (d = 1; d <= 5; d = d + 1) ctl_s6_d[d]     <= 1'b0;
        end
        else if (sample_en) begin
            ctl_s123_d1     <= ctl_s123;
            ctl_cm_in_d[1]  <= ctl_cm_in;
            ctl_cm_out_d[1] <= ctl_cm_out;
            ctl_s45_d[1]    <= ctl_s45;
            ctl_s6_d[1]     <= ctl_s6;
            for (d = 2; d <= 2; d = d + 1) ctl_cm_in_d[d]  <= ctl_cm_in_d[d-1];
            for (d = 2; d <= 3; d = d + 1) ctl_cm_out_d[d] <= ctl_cm_out_d[d-1];
            for (d = 2; d <= 4; d = d + 1) ctl_s45_d[d]    <= ctl_s45_d[d-1];
            for (d = 2; d <= 5; d = d + 1) ctl_s6_d[d]     <= ctl_s6_d[d-1];
        end
    end

    // Aligned controls
    wire a_pe1_s0_32, a_pe1_s1_32, a_pe1_s2_32;
    wire a_pe2_s0_16, a_pe2_s1_16;
    wire a_pe3_s0_8;
    wire a_cm_s1, a_cm_s2;
    wire [2:0] a_coeff_sel;
    wire a_swap;
    wire a_cm_s3, a_cm_s4, a_cm_s5, a_cm_enable;
    wire a_pe1_s0_4, a_pe1_s1_4, a_pe1_s2_4;
    wire a_pe2_s0_2, a_pe2_s1_2;
    wire a_pe3_s0_1;

    assign {a_pe1_s0_32, a_pe1_s1_32, a_pe1_s2_32,
            a_pe2_s0_16, a_pe2_s1_16, a_pe3_s0_8}  = ctl_s123_d1;
    assign {a_cm_s1, a_cm_s2, a_coeff_sel, a_swap}  = ctl_cm_in_d[2];
    assign {a_cm_s3, a_cm_s4, a_cm_s5, a_cm_enable} = ctl_cm_out_d[3];
    assign {a_pe1_s0_4, a_pe1_s1_4, a_pe1_s2_4,
            a_pe2_s0_2, a_pe2_s1_2}                 = ctl_s45_d[4];
    assign a_pe3_s0_1                               = ctl_s6_d[5];

    // =====================================================
    // STAGES 1-3
    // =====================================================
    wire signed [DATA_WIDTH-1:0] stage1_I, stage1_Q;
    wire signed [DATA_WIDTH-1:0] stage2_I, stage2_Q;
    wire signed [DATA_WIDTH-1:0] stage3_I, stage3_Q;

    SDF_Stage_PE1 #(.DATA_WIDTH(DATA_WIDTH), .DELAY(32)) U_PE1_32 (
        .clk(clk), .rst(rst), .sample_en(sample_en), .ifft_mode(scale_en),
        .Iin(r0_I), .Qin(r0_Q),
        .s0(a_pe1_s0_32), .s1(a_pe1_s1_32), .s2(a_pe1_s2_32),
        .Iout(stage1_I), .Qout(stage1_Q)
    );

    SDF_Stage_PE2 #(.DATA_WIDTH(DATA_WIDTH), .DELAY(16)) U_PE2_16 (
        .clk(clk), .rst(rst), .sample_en(sample_en), .ifft_mode(scale_en),
        .Iin(stage1_I), .Qin(stage1_Q),
        .s0(a_pe2_s0_16), .s1(a_pe2_s1_16),
        .Iout(stage2_I), .Qout(stage2_Q)
    );

    SDF_Stage_PE3 #(.DATA_WIDTH(DATA_WIDTH), .DELAY(8)) U_PE3_8 (
        .clk(clk), .rst(rst), .sample_en(sample_en), .ifft_mode(scale_en),
        .Iin(stage2_I), .Qin(stage2_Q),
        .s0(a_pe3_s0_8),
        .Iout(stage3_I), .Qout(stage3_Q)
    );

    // R1: register before the multiplier
    reg signed [DATA_WIDTH-1:0] r1_I, r1_Q;

    always @(posedge clk) begin
        if (sample_en) begin
            r1_I <= stage3_I;
            r1_Q <= stage3_Q;
        end
    end

    // =====================================================
    // COEFFICIENT SWITCH + RECONFIGURABLE MULTIPLIER + BYPASS
    // =====================================================
    wire signed [15:0] coeff_i;
    wire signed [15:0] coeff_q;

    Circuit_Switch U_Coefficient_Switch (
        .coeff_sel (a_coeff_sel),
        .swap      (a_swap),
        .coeff_i   (coeff_i),
        .coeff_q   (coeff_q)
    );

    wire signed [DATA_WIDTH-1:0] cm_I, cm_Q;
    wire signed [DATA_WIDTH-1:0] stage4_I, stage4_Q;

    Reconfigurable_Complex_Multiplier U_RCM (
        .clk(clk), .en(sample_en),
        .I_in(r1_I), .Q_in(r1_Q),
        .s1(a_cm_s1), .s2(a_cm_s2), .s3(a_cm_s3), .s4(a_cm_s4), .s5(a_cm_s5),
        .coeff_i(coeff_i), .coeff_q(coeff_q),
        .I_out(cm_I), .Q_out(cm_Q)
    );

    // R2 bypass: stage-3 value registered at the same point as the products
    reg signed [DATA_WIDTH-1:0] r2_I, r2_Q;

    always @(posedge clk) begin
        if (sample_en) begin
            r2_I <= r1_I;
            r2_Q <= r1_Q;
        end
    end

    assign stage4_I = a_cm_enable ? cm_I : r2_I;
    assign stage4_Q = a_cm_enable ? cm_Q : r2_Q;

    // R3: register after the bypass MUX
    reg signed [DATA_WIDTH-1:0] r3_I, r3_Q;

    always @(posedge clk) begin
        if (sample_en) begin
            r3_I <= stage4_I;
            r3_Q <= stage4_Q;
        end
    end

    // =====================================================
    // STAGES 4-6
    // =====================================================
    wire signed [DATA_WIDTH-1:0] stage5_I, stage5_Q;
    wire signed [DATA_WIDTH-1:0] stage6_I, stage6_Q;
    wire signed [DATA_WIDTH-1:0] core_Iout, core_Qout;

    SDF_Stage_PE1 #(.DATA_WIDTH(DATA_WIDTH), .DELAY(4)) U_PE1_4 (
        .clk(clk), .rst(rst), .sample_en(sample_en), .ifft_mode(scale_en),
        .Iin(r3_I), .Qin(r3_Q),
        .s0(a_pe1_s0_4), .s1(a_pe1_s1_4), .s2(a_pe1_s2_4),
        .Iout(stage5_I), .Qout(stage5_Q)
    );

    SDF_Stage_PE2 #(.DATA_WIDTH(DATA_WIDTH), .DELAY(2)) U_PE2_2 (
        .clk(clk), .rst(rst), .sample_en(sample_en), .ifft_mode(scale_en),
        .Iin(stage5_I), .Qin(stage5_Q),
        .s0(a_pe2_s0_2), .s1(a_pe2_s1_2),
        .Iout(stage6_I), .Qout(stage6_Q)
    );

    // R4: register before the last stage
    reg signed [DATA_WIDTH-1:0] r4_I, r4_Q;

    always @(posedge clk) begin
        if (sample_en) begin
            r4_I <= stage6_I;
            r4_Q <= stage6_Q;
        end
    end

    SDF_Stage_PE3 #(.DATA_WIDTH(DATA_WIDTH), .DELAY(1)) U_PE3_1 (
        .clk(clk), .rst(rst), .sample_en(sample_en), .ifft_mode(scale_en),
        .Iin(r4_I), .Qin(r4_Q),
        .s0(a_pe3_s0_1),
        .Iout(core_Iout), .Qout(core_Qout)
    );

    // =====================================================
    // OUTPUT CONJUGATION (IFFT mode)
    // =====================================================
    wire [2*DATA_WIDTH-1:0] conj_output;

    Complex_Conjugate #(.DATA_WIDTH(DATA_WIDTH)) U_OUTPUT_CONJ (
        .data_in  ({core_Iout, core_Qout}),
        .data_out (conj_output)
    );

    assign I_out = core_Iout;
    assign Q_out = ifft_mode ? $signed(conj_output[DATA_WIDTH-1:0]) : core_Qout;

    // =====================================================
    // OUTPUT VALID / INDEX
    // Without the pipeline registers the first valid output is at
    // sample_count = 63, output position = count + 1, natural index =
    // bit-reversal, last output at count = 62 (latency 63 samples).
    // These flags are computed as before and then delayed by CORE_PIPE
    // samples, so they stay aligned with the data (latency 68 samples).
    // =====================================================

    reg primed;

    always @(posedge clk or negedge rst) begin
        if (!rst)
            primed <= 1'b0;
        else if (start)
            primed <= 1'b0;
        else if (sample_en && (sample_count == 6'd62))
            primed <= 1'b1;
    end

    wire [5:0] out_position;

    assign out_position = sample_count + 6'd1;

    wire [7:0] out_info;     // {valid, last, natural index}

    assign out_info = {
        primed,
        primed && (sample_count == 6'd62),
        out_position[0],
        out_position[1],
        out_position[2],
        out_position[3],
        out_position[4],
        out_position[5]
    };

    reg [7:0] out_info_d [1:CORE_PIPE];

    integer e;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            for (e = 1; e <= CORE_PIPE; e = e + 1) out_info_d[e] <= 8'd0;
        end
        else if (start) begin
            for (e = 1; e <= CORE_PIPE; e = e + 1) out_info_d[e] <= 8'd0;
        end
        else if (sample_en) begin
            out_info_d[1] <= out_info;
            for (e = 2; e <= CORE_PIPE; e = e + 1) out_info_d[e] <= out_info_d[e-1];
        end
    end

    assign out_index = out_info_d[CORE_PIPE][5:0];

    assign out_valid = sample_en && out_info_d[CORE_PIPE][7];

    assign out_last = out_valid && out_info_d[CORE_PIPE][6];

endmodule
