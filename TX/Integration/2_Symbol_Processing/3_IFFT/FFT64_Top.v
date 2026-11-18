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

    // IMPORTANT: multiplier modules use fixed 16-bit ports (DATA_WIDTH = 16).

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
    // STAGES 1-3
    // =====================================================
    wire signed [DATA_WIDTH-1:0] stage1_I, stage1_Q;
    wire signed [DATA_WIDTH-1:0] stage2_I, stage2_Q;
    wire signed [DATA_WIDTH-1:0] stage3_I, stage3_Q;

    SDF_Stage_PE1 #(.DATA_WIDTH(DATA_WIDTH), .DELAY(32)) U_PE1_32 (
        .clk(clk), .rst(rst), .sample_en(sample_en), .ifft_mode(scale_en),
        .Iin(fft_input_I), .Qin(fft_input_Q),
        .s0(c_pe1_s0_32), .s1(c_pe1_s1_32), .s2(c_pe1_s2_32),
        .Iout(stage1_I), .Qout(stage1_Q)
    );

    SDF_Stage_PE2 #(.DATA_WIDTH(DATA_WIDTH), .DELAY(16)) U_PE2_16 (
        .clk(clk), .rst(rst), .sample_en(sample_en), .ifft_mode(scale_en),
        .Iin(stage1_I), .Qin(stage1_Q),
        .s0(c_pe2_s0_16), .s1(c_pe2_s1_16),
        .Iout(stage2_I), .Qout(stage2_Q)
    );

    SDF_Stage_PE3 #(.DATA_WIDTH(DATA_WIDTH), .DELAY(8)) U_PE3_8 (
        .clk(clk), .rst(rst), .sample_en(sample_en), .ifft_mode(scale_en),
        .Iin(stage2_I), .Qin(stage2_Q),
        .s0(c_pe3_s0_8),
        .Iout(stage3_I), .Qout(stage3_Q)
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
    // COEFFICIENT SWITCH + RECONFIGURABLE MULTIPLIER + BYPASS
    // =====================================================
    wire signed [15:0] coeff_i;
    wire signed [15:0] coeff_q;

    Circuit_Switch U_Coefficient_Switch (
        .coeff_sel (coeff_sel),
        .swap      (swap),
        .coeff_i   (coeff_i),
        .coeff_q   (coeff_q)
    );

    wire signed [DATA_WIDTH-1:0] cm_I, cm_Q;
    wire signed [DATA_WIDTH-1:0] stage4_I, stage4_Q;

    Reconfigurable_Complex_Multiplier U_RCM (
        .I_in(stage3_I), .Q_in(stage3_Q),
        .s1(cm_s1), .s2(cm_s2), .s3(cm_s3), .s4(cm_s4), .s5(cm_s5),
        .coeff_i(coeff_i), .coeff_q(coeff_q),
        .I_out(cm_I), .Q_out(cm_Q)
    );

    assign stage4_I = cm_enable ? cm_I : stage3_I;
    assign stage4_Q = cm_enable ? cm_Q : stage3_Q;

    // =====================================================
    // STAGES 4-6
    // =====================================================
    wire signed [DATA_WIDTH-1:0] stage5_I, stage5_Q;
    wire signed [DATA_WIDTH-1:0] stage6_I, stage6_Q;
    wire signed [DATA_WIDTH-1:0] core_Iout, core_Qout;

    SDF_Stage_PE1 #(.DATA_WIDTH(DATA_WIDTH), .DELAY(4)) U_PE1_4 (
        .clk(clk), .rst(rst), .sample_en(sample_en), .ifft_mode(scale_en),
        .Iin(stage4_I), .Qin(stage4_Q),
        .s0(c_pe1_s0_4), .s1(c_pe1_s1_4), .s2(c_pe1_s2_4),
        .Iout(stage5_I), .Qout(stage5_Q)
    );

    SDF_Stage_PE2 #(.DATA_WIDTH(DATA_WIDTH), .DELAY(2)) U_PE2_2 (
        .clk(clk), .rst(rst), .sample_en(sample_en), .ifft_mode(scale_en),
        .Iin(stage5_I), .Qin(stage5_Q),
        .s0(c_pe2_s0_2), .s1(c_pe2_s1_2),
        .Iout(stage6_I), .Qout(stage6_Q)
    );

    SDF_Stage_PE3 #(.DATA_WIDTH(DATA_WIDTH), .DELAY(1)) U_PE3_1 (
        .clk(clk), .rst(rst), .sample_en(sample_en), .ifft_mode(scale_en),
        .Iin(stage6_I), .Qin(stage6_Q),
        .s0(c_pe3_s0_1),
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
    // First valid output is at sample_count = 63 (latency 63 samples).
    // Output stream position = count + 1; natural index = bit-reversal.
    // =====================================================
       // =====================================================
    // OUTPUT VALID / INDEX
    // First valid output after 64 accepted input samples.
    // Output position follows the SDF bit-reversed order.
    // =====================================================

       // =====================================================
    // OUTPUT VALID / INDEX
    // First valid output is at sample_count = 63.
    // Output stream position = count + 1.
    // Natural index = bit-reversal.
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

    assign out_index = {
        out_position[0],
        out_position[1],
        out_position[2],
        out_position[3],
        out_position[4],
        out_position[5]
    };

    assign out_valid = sample_en && primed;

    assign out_last = out_valid && (sample_count == 6'd62);

endmodule