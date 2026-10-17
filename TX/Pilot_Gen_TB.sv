`timescale 1ns/1ps

module Pilot_Gen_TB;

   
    localparam [6:0] TEST_SEED = 7'h7F;

    localparam integer SEQ_LEN       = 127;
    localparam integer MAIN_SAMPLES  = 2 * SEQ_LEN;
    localparam integer RESET_STEPS   = 13;
    localparam integer RESTART_CHECK = 16;
    localparam integer EXPECTED_ADVANCES = MAIN_SAMPLES + RESET_STEPS + RESTART_CHECK;

    reg clk;
    reg rst;
    reg sym_advance;
    wire signed [1:0] pilot_out;

    // Reference polarity bits: 0 -> +1, 1 -> -1.
    // IEEE 802.11a pilot polarity p[0:126], with p0 first.
    reg [126:0] golden_bits;

    integer errors;
    integer fd;
    integer i;
    integer observed_value;
    integer advance_count;
    reg [1:0] held_output;

    // 20 MHz clock: 50 ns period.
    initial clk = 1'b0;
    always #25 clk = ~clk;

    Pilot_Gen dut (
        .clk         (clk),
        .rst         (rst),
        .sym_advance (sym_advance),
        .pilot_out   (pilot_out)
    );

    // Compare the current signed RTL output against a reference sequence index.
    // phase: 0 = normal sequence sample, 1 = immediately after advance, 2 = reset test.
    task check_sequence;
        input integer sequence_index;
        input integer phase;
        integer expected_value;
        integer actual_value;
        begin
            if (golden_bits[126 - (sequence_index % SEQ_LEN)] == 1'b1)
                expected_value = -1;
            else
                expected_value = 1;

            actual_value = $signed(pilot_out);

            if (actual_value !== expected_value) begin
                if ((pilot_out !== 2'sd1) && (pilot_out !== -2'sd1)) begin
                    $display("[FAIL] Illegal pilot code: raw=%b, signed=%0d", pilot_out, actual_value);
                end

                case (phase)
                    0: $display("[FAIL] Sequence sample %0d: expected %0d, got %0d",
                                sequence_index, expected_value, actual_value);
                    1: $display("[FAIL] After sym_advance at sequence index %0d: expected %0d, got %0d",
                                sequence_index, expected_value, actual_value);
                    2: $display("[FAIL] Reset/restart at sequence index %0d: expected %0d, got %0d",
                                sequence_index, expected_value, actual_value);
                    default: $display("[FAIL] Sequence index %0d: expected %0d, got %0d",
                                     sequence_index, expected_value, actual_value);
                endcase
                errors = errors + 1;
            end
        end
    endtask

    // Drive a single-cycle enable: it is high for exactly one rising clock edge.
    // current_index is the sample visible before this advance.
    task pulse_advance;
        input integer current_index;
        begin
            @(negedge clk);
            sym_advance = 1'b1;

            @(posedge clk);
            #1;
            advance_count = advance_count + 1;
            check_sequence(current_index + 1, 1);

            @(negedge clk);
            sym_advance = 1'b0;
        end
    endtask

    // Prevent a broken test from running forever.
    initial begin
        #1000000;
        $fatal(1, "[FAIL] Testbench timeout.");
    end

    initial begin
        clk           = 1'b0;
        rst           = 1'b1;
        sym_advance   = 1'b0;
        errors        = 0;
        advance_count = 0;

        // Full 127-element IEEE 802.11a polarity sequence.
        // The literal is 127 bits: bit[126] represents p0, bit[0] represents p126.
        golden_bits = 127'b00001110111100101100100100000010_00100110001011101011011000001100_11010100111001111011010000101010_1111101001010001101110001111111;

        if (TEST_SEED == 7'b0)
            $fatal(1, "[FAIL] TEST_SEED must be nonzero; an all-zero LFSR seed is invalid.");

        fd = $fopen("rtl_pilot_polarity.txt", "w");
        if (fd == 0)
            $fatal(1, "[FAIL] Cannot open rtl_pilot_polarity.txt for writing.");

        // ------------------------------------------------------------------
        // TEST 1: reset establishes the expected first polarity, p0 = +1.
        // Release reset on a falling edge to avoid a testbench/DUT race.
        // ------------------------------------------------------------------
        repeat (2) @(negedge clk);
        @(posedge clk);
        #1;
        check_sequence(0, 2);

        @(negedge clk);
        rst = 1'b0;
        #1;
        check_sequence(0, 2);

        // Releasing reset alone must not advance the sequence.
        @(posedge clk);
        #1;
        check_sequence(0, 2);

        // ------------------------------------------------------------------
        // TEST 2: exact reference match over two full 127-sample periods.
        // Also checks output hold for two clocks before every advance pulse.
        // Only the first period is written to the output file.
        // ------------------------------------------------------------------
        for (i = 0; i < MAIN_SAMPLES; i = i + 1) begin
            #1;
            check_sequence(i, 0);

            observed_value = $signed(pilot_out);
            if (i < SEQ_LEN)
                $fwrite(fd, "%0d\n", observed_value);

            // Missing/idle advance test: output must not change while enable is low.
            held_output = pilot_out;
            repeat (2) begin
                @(posedge clk);
                #1;
                if (pilot_out !== held_output) begin
                    $display("[FAIL] Output changed while sym_advance=0 at sample %0d: before=%b after=%b",
                             i, held_output, pilot_out);
                    errors = errors + 1;
                end
            end

            // This pulse must advance exactly one element, including the wrap p126 -> p0.
            pulse_advance(i);
        end

        // ------------------------------------------------------------------
        // TEST 3: reset from a non-initial point in the sequence.
        // Move to p13, reset, and verify the sequence restarts at p0.
        // ------------------------------------------------------------------
        for (i = 0; i < RESET_STEPS; i = i + 1)
            pulse_advance(i);

        @(negedge clk);
        sym_advance = 1'b0;
        rst = 1'b1;

        @(posedge clk);
        #1;
        check_sequence(0, 2);

        @(negedge clk);
        rst = 1'b0;
        #1;
        check_sequence(0, 2);

        // Reset release with no advance pulse must leave p0 visible.
        @(posedge clk);
        #1;
        check_sequence(0, 2);

        // Confirm the beginning of the sequence after reset, element by element.
        for (i = 0; i < RESTART_CHECK; i = i + 1) begin
            #1;
            check_sequence(i, 0);
            pulse_advance(i);
        end

        $fclose(fd);

        if (advance_count !== EXPECTED_ADVANCES) begin
            $display("[FAIL] Advance pulse count: expected %0d, got %0d",
                     EXPECTED_ADVANCES, advance_count);
            errors = errors + 1;
        end

        if (errors == 0) begin
            
            $display("PASS: Pilot_Gen passed all implemented testbench checks.");
            $display("  - IEEE 802.11a reference sequence: two full periods");
            $display("  - Polarity encoding and signed output values");
            $display("  - Output holds when sym_advance is low");
            $display("  - One sequence step per one-cycle advance pulse");
            $display("  - Periodic wraparound and mid-sequence reset/restart");
            $display("  - First 127 polarity values saved to rtl_pilot_polarity.txt");
           
            $finish;
        end
        else begin
            $fatal(1, "FAIL: Pilot_Gen testbench found %0d error(s).", errors);
        end
    end

endmodule
