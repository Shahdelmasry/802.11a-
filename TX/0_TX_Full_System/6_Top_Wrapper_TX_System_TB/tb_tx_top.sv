`timescale 1ns/1ps

module tb_tx_top;

    localparam real TCLK    = 12.5;          
    localparam int  MAXMAP  = 70000;
    localparam int  MAXBB   = 120000;
    localparam int  GAP_CLK = 1280;
    localparam int  DAC_LAT = 6;            

    // ------------------------------------------------------------------ clocks / resets
    int  WCLK_PS = 17300;                    
    logic r_clk = 1'b0, w_clk = 1'b0;
    logic r_rstn = 1'b1, w_rstn = 1'b1;
    always #(TCLK/2.0) r_clk = ~r_clk;
    initial begin
        void'($value$plusargs("WCLK_PS=%d", WCLK_PS));
        #3.1;
        forever #(WCLK_PS/2000.0) w_clk = ~w_clk;
    end
    longint cyc = 0;
    always @(posedge r_clk) cyc <= cyc + 1;

    logic [34:0] TXVECTOR = '0;
    logic [7:0]  PHY_DATA_req;
    logic        PHY_TXEND_req = 1'b0;
    wire         PHY_TXSTART_conf, PHY_DATA_conf, PHY_TXEND_CONF;
    wire [15:0]  dac_data_i, dac_data_q;

    TX_TOP #(.DATA_WIDTH(16), .GAP_CLK(GAP_CLK)) dut (
        .w_clk(w_clk), .w_rstn(w_rstn), 
        .TXVECTOR(TXVECTOR), 
        .PHY_DATA_req(PHY_DATA_req),
        .PHY_TXEND_req(PHY_TXEND_req), 
        .PHY_TXSTART_conf(PHY_TXSTART_conf),
        .PHY_DATA_conf(PHY_DATA_conf), 
        .PHY_TXEND_CONF(PHY_TXEND_CONF),
        .r_clk(r_clk), .r_rstn(r_rstn), 
        .DAC_DATA_I(dac_data_i), .DAC_DATA_Q(dac_data_q)
    );

    wire [31:0]        m_data  = dut.tx_datapath_inst.w_complex_symbol;
    wire               m_valid = dut.mapper_valid;
    wire               m_last  = dut.mapper_last;
    wire               m_ready = dut.mapper_capture_ready;
    wire               tx_done = dut.tx_done;
    wire signed [15:0] mx_i    = dut.tx_datapath_inst.u_ofdm_tx_sys.u_post_processing.mux_to_up_i;
    wire signed [15:0] mx_q    = dut.tx_datapath_inst.u_ofdm_tx_sys.u_post_processing.mux_to_up_q;
    wire               mx_v    = dut.tx_datapath_inst.u_ofdm_tx_sys.u_post_processing.mux_to_up_valid;
    wire               mx_l    = dut.tx_datapath_inst.u_ofdm_tx_sys.u_post_processing.mux_to_up_last;
    wire               mx_r    = dut.tx_datapath_inst.u_ofdm_tx_sys.u_post_processing.up_to_mux_ready;
    wire signed [15:0] fi_i    = dut.tx_datapath_inst.u_ofdm_tx_sys.u_post_processing.up_to_fir_i;
    wire signed [15:0] fi_q    = dut.tx_datapath_inst.u_ofdm_tx_sys.u_post_processing.up_to_fir_q;
    wire               fi_v    = dut.tx_datapath_inst.u_ofdm_tx_sys.u_post_processing.up_to_fir_valid;

    // ------------------------------------------------------------------ state
    int    errors = 0;
    string vec_dir = "vectors", out_dir = "rtl_out";
    int    TOL = 32;
    real   SNR_MIN = 50.0;

    logic [7:0]  psdu   [0:4095];
    logic [31:0] exp_map[0:MAXMAP-1];
    logic [31:0] exp_bb [0:MAXBB-1];
    int  cur_rate, cur_len, cur_seed, cur_nsym, cur_mode, cur_param, cur_pkt = -1;

    bit  chk_en = 0;
    int  map_idx, map_drop, bb_idx, bb_gap, txdone_cnt, pe_cnt, txstart_cnt, seed_cnt;
    int  map_sym_err [0:4200];
    int  bb_sym_err  [0:4200];               // samples above TOL per symbol (index 0 = SIGNAL)
    int  bb_sym_max  [0:4200];
    int  pre_err;
    longint bb_last_cyc, txdone_cyc, prev_txdone_cyc = -1, first_bb_cyc;
    real bb_sig_e, bb_err_e;
    int  min_gap = 1 << 30;

    function automatic logic signed [15:0] hi16(input logic [31:0] w); return w[31:16]; endfunction
    function automatic logic signed [15:0] lo16(input logic [31:0] w); return w[15:0];  endfunction

    task automatic fail(input string msg);
        errors++;
        if (errors <= 60) $display("[%0t] ERROR pkt %0d: %s", $time, cur_pkt, msg);
        if (errors == 60) $display("... further errors suppressed");
    endtask

    function automatic logic [3:0] rate_code(input int mbps);    // {R4,R3,R2,R1}
        case (mbps) 6: return 4'b1011; 9: return 4'b1111; 12: return 4'b1010; 18: return 4'b1110;
                    24: return 4'b1001; 36: return 4'b1101; 48: return 4'b1000; default: return 4'b1100; endcase
    endfunction

    // ------------------------------------------------------------------ MAC model (w_clk)
    int  mac_idx = 0, dconf_cnt = 0, tstart_cnt = 0, tend_cnt = 0;
    assign PHY_DATA_req = psdu[mac_idx];
    always @(posedge w_clk) begin
        if (PHY_DATA_conf && w_rstn) begin mac_idx <= mac_idx + 1; dconf_cnt <= dconf_cnt + 1; end
        if (PHY_TXSTART_conf && w_rstn) tstart_cnt <= tstart_cnt + 1;
        if (PHY_TXEND_CONF && w_rstn)   tend_cnt   <= tend_cnt + 1;
    end

    // ------------------------------------------------------------------ seed + tx_start monitor
    always @(negedge r_clk) if (r_rstn && dut.tx_start) begin
        logic [6:0] s, m;
        s = dut.input_buffer_inst.rnd;                  // value loaded into the scrambler LFSR
        for (int k = 0; k < 7; k++) m[k] = s[6-k];      // MATLAB convention: bit 6 = x7 .. bit 0 = x1
        $display("SEED %0d %0d", cur_pkt, m);
        txstart_cnt++;
        if (chk_en && cur_mode == 0 && m != cur_seed[6:0]) seed_cnt++;
    end

    // ------------------------------------------------------------------ abort timing
    // abort_late = the abort reached TX_CONTROLLER after the packet's last symbol was
    // already committed (nsym_valid = 1, symbol FSM idle): nothing is left to truncate,
    // so the complete packet must go out, bit-exact (S11 then checks every symbol)
    bit abort_seen = 0, abort_late = 0;
    always @(negedge r_clk) if (r_rstn && chk_en && dut.pkt_abort && !abort_seen) begin
        abort_seen = 1;
        abort_late = dut.tx_controller_inst.nsym_valid && (dut.tx_controller_inst.sym_state == 3'd0);
    end

    // ------------------------------------------------------------------ S1/S2 mapper
    always @(negedge r_clk) begin #2; if (r_rstn && chk_en && m_valid) begin
        if (!m_ready) begin
            map_drop++;
            fail($sformatf("S2 mapper value %0d presented while capture_ready=0", map_idx));
        end else begin
            if (map_idx >= 48*(cur_nsym+1))
                fail($sformatf("S1 extra mapper value %0d", map_idx));
            else if (m_data !== exp_map[map_idx]) begin
                map_sym_err[map_idx/48]++;
                if (cur_mode == 0 && map_sym_err[map_idx/48] <= 2)
                    fail($sformatf("S1 mapper sym %0d val %0d: got (%0d,%0d) exp (%0d,%0d)", map_idx/48, map_idx%48,
                         $signed(hi16(m_data)), $signed(lo16(m_data)), $signed(hi16(exp_map[map_idx])), $signed(lo16(exp_map[map_idx]))));
            end
            if (m_last !== ((map_idx % 48) == 47)) fail($sformatf("S2 mapper_last=%0b at value %0d", m_last, map_idx%48));
            map_idx++;
        end
    end end

    // ------------------------------------------------------------------ S3/S4 baseband
    integer fbb = 0, fdac = 0;
    always @(negedge r_clk) begin : bb_mon
        int ei, eq, di, dq, ad, sy;
        bit exp_last;
        #2;
        if (r_rstn && chk_en && mx_v && mx_r) begin
            if (fbb != 0) $fdisplay(fbb, "%0d %0d", mx_i, mx_q);
            if (bb_idx == 0) begin
                first_bb_cyc = cyc;
                if (prev_txdone_cyc >= 0) begin
                    if (cyc - prev_txdone_cyc < min_gap) min_gap = cyc - prev_txdone_cyc;
                    if (cyc - prev_txdone_cyc < GAP_CLK)
                        fail($sformatf("S7 packet started %0d clocks after previous tx_done (< %0d)", cyc - prev_txdone_cyc, GAP_CLK));
                end
            end
            if (bb_idx >= 320 + 80*(cur_nsym+1)) fail($sformatf("S3 extra baseband sample %0d", bb_idx));
            else begin
                ei = $signed(hi16(exp_bb[bb_idx])); eq = $signed(lo16(exp_bb[bb_idx]));
                di = mx_i - ei; dq = mx_q - eq;
                ad = (di < 0 ? -di : di) > (dq < 0 ? -dq : dq) ? (di < 0 ? -di : di) : (dq < 0 ? -dq : dq);
                if (bb_idx < 320) begin
                    if (ad != 0) begin
                        pre_err++;
                        if (pre_err <= 3) fail($sformatf("S3 preamble sample %0d: got (%0d,%0d) exp (%0d,%0d)", bb_idx, mx_i, mx_q, ei, eq));
                    end
                end else begin
                    sy = (bb_idx - 320) / 80;
                    if (ad > bb_sym_max[sy]) bb_sym_max[sy] = ad;
                    if (ad > TOL) bb_sym_err[sy]++;
                    if (cur_mode == 0) begin
                        bb_sig_e += $itor(ei)*$itor(ei) + $itor(eq)*$itor(eq);
                        bb_err_e += $itor(di)*$itor(di) + $itor(dq)*$itor(dq);
                    end
                end
                exp_last = (bb_idx == 319) || (bb_idx >= 320 && ((bb_idx - 320) % 80) == 79);
                if (mx_l !== exp_last) fail($sformatf("S4 tx_mux last=%0b at sample %0d", mx_l, bb_idx));
                if (bb_idx > 0 && (cyc - bb_last_cyc) != 4) begin
                    bb_gap++;
                    if (bb_gap <= 5) fail($sformatf("S4 sample %0d came %0d clocks after the previous one", bb_idx, cyc - bb_last_cyc));
                end
            end
            bb_last_cyc = cyc;
            bb_idx++;
        end
    end

    // ------------------------------------------------------------------ debug trace (+TRACE_PKT=n)
    int trace_pkt = -1;
    initial void'($value$plusargs("TRACE_PKT=%d", trace_pkt));
    logic [2:0] tr_ps = 0, tr_ss = 0;
    always @(negedge r_clk) if (cur_pkt == trace_pkt && r_rstn &&
                                (dut.tx_controller_inst.current_state != tr_ps || dut.tx_controller_inst.sym_state != tr_ss
                                 || dut.abort || dut.tx_done)) begin
        tr_ps = dut.tx_controller_inst.current_state; tr_ss = dut.tx_controller_inst.sym_state;
        $display("TRACE cyc %0d pkt_st %0d sym_st %0d sym_idx %0d sym_count %0d nsym %0d/%0b abort %0b pkt_abort %0b cap_rdy %0b in_ready %0b fill_done %0b map %0d bb %0d tx_done %0b",
                 cyc, tr_ps, tr_ss, dut.tx_controller_inst.sym_idx, dut.sym_count, dut.nsym, dut.nsym_valid,
                 dut.abort, dut.pkt_abort, dut.mapper_capture_ready, dut.in_ready, dut.fill_done, map_idx, bb_idx, dut.tx_done);
    end

    // ------------------------------------------------------------------ S13 framer: PSDU bit order
    // every PSDU bit stored by input_buffer must be the next bit of the MAC's bytes (bit 0 first)
    int fr_bit = 0, fr_err = 0;
    always @(negedge r_clk) begin #2;
        if (r_rstn && dut.tx_start) fr_bit = 0;
        else if (r_rstn && chk_en && cur_mode == 0 && dut.input_buffer_inst.psdu_take) begin
            if (dut.input_buffer_inst.fill_bit !== psdu[fr_bit/8][fr_bit%8]) begin
                fr_err++;
                if (fr_err <= 3) fail($sformatf("S13 PSDU bit %0d stored as %0b, MAC byte %0d = %02h (fifo word %02h valid %0b)",
                     fr_bit, dut.input_buffer_inst.fill_bit, fr_bit/8, psdu[fr_bit/8], dut.data, dut.data_valid));
            end
            fr_bit++;
        end
    end

    // ------------------------------------------------------------------ S5 / S9
    always @(negedge r_clk) begin #2;
        if (r_rstn && chk_en) begin
            if (tx_done) begin
                txdone_cnt++; txdone_cyc = cyc;
            end
            if (dut.cfg_err) fail("S9 cfg_err = 1");
            if (dut.packet_end && dut.data_req) pe_cnt++;
        end
    end

    // ------------------------------------------------------------------ S8 DAC model
    int coef [0:42];
    initial begin : coef_init
        int c22 [0:21];
        c22[0]=363;   c22[1]=564;   c22[2]=715;   c22[3]=614;   c22[4]=207;   c22[5]=-388;
        c22[6]=-894;  c22[7]=-996;  c22[8]=-530;  c22[9]=372;   c22[10]=1272; c22[11]=1600;
        c22[12]=970;  c22[13]=-542; c22[14]=-2289;c22[15]=-3251;c22[16]=-2465;c22[17]=483;
        c22[18]=5149; c22[19]=10287;c22[20]=14282;c22[21]=15788;
        for (int k = 0; k < 43; k++) coef[k] = (k <= 21) ? c22[k] : c22[42-k];
    end
    int xh_i [0:42], xh_q [0:42], yp_i [0:7], yp_q [0:7];
    int dac_ok = 0, dac_err = 0, rst_hold = 0;
    function automatic int sat16(input longint v);
        if (v > 32767) return 32767; if (v < -32768) return -32768; return v;
    endfunction
    always @(negedge r_clk) begin : dac_mon
        longint ai, aq, ck;
        #2;
        if (!r_rstn) begin
            for (int k = 0; k < 43; k++) begin xh_i[k] = 0; xh_q[k] = 0; end
            for (int k = 0; k < 8; k++) begin yp_i[k] = 0; yp_q[k] = 0; end
            rst_hold = 0;
        end else begin
            if (rst_hold >= DAC_LAT + 1) begin
                if ($isunknown({dac_data_i, dac_data_q})) begin dac_err++; if (dac_err <= 5) fail("S8 X on DAC pins"); end
                else if ($signed(dac_data_i) != yp_i[DAC_LAT-1] || $signed(dac_data_q) != yp_q[DAC_LAT-1]) begin
                    dac_err++; if (dac_err <= 5) fail($sformatf("S8 DAC got (%0d,%0d) model (%0d,%0d)",
                        $signed(dac_data_i), $signed(dac_data_q), yp_i[DAC_LAT-1], yp_q[DAC_LAT-1]));
                end else dac_ok++;
            end else rst_hold++;
            if (fdac != 0) $fdisplay(fdac, "%0d %0d", $signed(dac_data_i), $signed(dac_data_q));
            for (int k = 7; k > 0; k--) begin yp_i[k] = yp_i[k-1]; yp_q[k] = yp_q[k-1]; end
            for (int k = 42; k > 0; k--) begin xh_i[k] = xh_i[k-1]; xh_q[k] = xh_q[k-1]; end
            xh_i[0] = fi_v ? fi_i : 0; xh_q[0] = fi_v ? fi_q : 0;
            ai = 0; aq = 0;
            for (int k = 0; k < 43; k++) begin ck = coef[k]; ai += ck * xh_i[k]; aq += ck * xh_q[k]; end
            yp_i[0] = sat16(ai >>> 14); yp_q[0] = sat16(aq >>> 14);
        end
    end

    // ------------------------------------------------------------------ helpers
    reg [8*512-1:0] fname;

    task automatic load_packet(input int fd);
        int r;
        r = $fscanf(fd, "%d %d %d %d %d %d", cur_rate, cur_len, cur_seed, cur_nsym, cur_mode, cur_param);
        if (r != 6) $fatal(1, "pkt_list format");
        $sformat(fname, "%0s/pkt%03d_psdu.hex", vec_dir, cur_pkt); $readmemh(fname, psdu, 0, cur_len-1);
        $sformat(fname, "%0s/pkt%03d_map.hex",  vec_dir, cur_pkt); $readmemh(fname, exp_map, 0, 48*(cur_nsym+1)-1);
        $sformat(fname, "%0s/pkt%03d_bb.hex",   vec_dir, cur_pkt); $readmemh(fname, exp_bb, 0, 320+80*(cur_nsym+1)-1);
        if ($isunknown(exp_map[0]) || $isunknown(exp_bb[0]) || $isunknown(psdu[0]))
            $fatal(1, "pkt %0d: reference files not loaded from %0s (check +VEC path)", cur_pkt, vec_dir);
    endtask

    task automatic reset_counters();
        map_idx = 0; map_drop = 0; bb_idx = 0; bb_gap = 0; txdone_cnt = 0; pe_cnt = 0; pre_err = 0;
        txstart_cnt = 0; seed_cnt = 0; bb_sig_e = 0; bb_err_e = 0; abort_seen = 0; abort_late = 0;
        for (int k = 0; k <= 4200; k++) begin map_sym_err[k] = 0; bb_sym_err[k] = 0; bb_sym_max[k] = 0; end
        @(negedge w_clk);
        mac_idx = 0; dconf_cnt = 0; tstart_cnt = 0; tend_cnt = 0;
    endtask

    // MAC: PHY-TXSTART.request with TXVECTOR; LENGTH back to 0 after the confirm
    // (write_ctrl starts a packet on LENGTH going from 0 to non-zero)
    task automatic mac_start(input logic [3:0] rc);
        @(negedge w_clk);
        TXVECTOR = {cur_len[11:0], rc, 16'h0000, 3'b001};
        do @(negedge w_clk); while (tstart_cnt == 0);
        TXVECTOR = '0;
    endtask

    task automatic wait_txend_conf(input longint limit);
        longint t0 = cyc;
        while (tend_cnt == 0 && (cyc - t0) < limit) @(negedge r_clk);
        if (tend_cnt == 0) fail("S6 TIMEOUT waiting for PHY-TXEND.confirm");
    endtask

    task automatic run_entry(input int fd);
        longint t0, limit;
        int e0, nrx, bad_sym, max_err; real snr;
        string tag;
        e0 = errors;
        load_packet(fd);
        reset_counters();
        $sformat(fname, "%0s/rtl_bb_pkt%03d.txt",  out_dir, cur_pkt); fbb  = $fopen(fname, "w");
        $sformat(fname, "%0s/rtl_dac_pkt%03d.txt", out_dir, cur_pkt); fdac = $fopen(fname, "w");
        limit = (cur_nsym + 8) * 420 + 8000;

        if (cur_mode == 2) begin                                  // ---- bad RATE code
            mac_start(4'b0000);
            wait_txend_conf(limit);
            repeat (200) @(negedge r_clk);
            if (txstart_cnt != 0) fail("S10 bad RATE: tx_start pulsed");
            if (bb_idx != 0 || map_idx != 0) fail($sformatf("S10 bad RATE: %0d samples / %0d mapper values on air", bb_idx, map_idx));
            if (tend_cnt != 1) fail($sformatf("S10 PHY-TXEND.confirm %0d times", tend_cnt));
            if (dconf_cnt != cur_len) fail($sformatf("S10 %0d PHY-DATA.confirm, LENGTH %0d", dconf_cnt, cur_len));
            $display("pkt %3d | bad RATE code 0000, len %4d | dropped, PHY-TXEND.confirm %0d, nothing on air | %s",
                     cur_pkt, cur_len, tend_cnt, (errors == e0) ? "PASS" : "FAIL");
        end

        else if (cur_mode == 3) begin                             // ---- reset in mid-packet
            chk_en = 0;
            mac_start(rate_code(cur_rate));
            repeat (cur_param) @(negedge r_clk);
            r_rstn = 0; w_rstn = 0;
            repeat (8) @(negedge r_clk);
            @(negedge w_clk); mac_idx = 0;
            r_rstn = 1; w_rstn = 1;
            repeat (50) @(negedge r_clk);
            if (dut.tx_controller_inst.current_state != 3'b000) fail("FSM not IDLE after reset");
            prev_txdone_cyc = -1;
            chk_en = 1;
            $display("pkt %3d | %2d Mb/s len %4d | both resets asserted %0d clocks after PHY-TXSTART.confirm (not checked)",
                     cur_pkt, cur_rate, cur_len, cur_param);
        end

        else begin : norm_blk                                     // ---- normal / abort
            fork
                mac_start(rate_code(cur_rate));
                if (cur_mode == 1) begin
                    do @(negedge w_clk); while (tstart_cnt == 0);
                    repeat (cur_param) @(negedge r_clk);
                    @(negedge w_clk); PHY_TXEND_req = 1;
                    @(negedge w_clk); PHY_TXEND_req = 0;
                end
            join
            t0 = cyc;
            if (cur_mode == 1) begin
                // abort: PHY-TXEND.confirm comes from the FIFO flush; a packet that had
                // not started yet must never start, one that had started is closed
                wait_txend_conf(limit);
                repeat (GAP_CLK + 400) @(negedge r_clk);
                if (txstart_cnt == 0) begin
                    if (bb_idx != 0 || map_idx != 0) fail("S11 aborted before start but something went on air");
                    if (tend_cnt != 1) fail($sformatf("S11 PHY-TXEND.confirm %0d times", tend_cnt));
                    $display("pkt %3d | %2d Mb/s len %4d | ABORT %0d clk after TXSTART.confirm, before the PHY started: nothing on air, PHY-TXEND.confirm %0d | %s",
                             cur_pkt, cur_rate, cur_len, cur_param, tend_cnt, (errors == e0) ? "PASS" : "FAIL");
                    disable norm_blk;
                end
            end
            while (txdone_cnt == 0 && (cyc - t0) < limit) @(negedge r_clk);
            if (txdone_cnt == 0) begin
                fail($sformatf("S9 TIMEOUT pkt %0d (mapper %0d/%0d, baseband %0d/%0d, PHY-DATA %0d/%0d)", cur_pkt,
                     map_idx, 48*(cur_nsym+1), bb_idx, 320+80*(cur_nsym+1), dconf_cnt, cur_len));
                $display("*** TEST FAILED : %0d errors (timeout) ***", errors);
                $finish;
            end
            prev_txdone_cyc = txdone_cyc;
            wait_txend_conf(20000);
            repeat (70) @(negedge r_clk);
            if (txdone_cnt != 1)  fail($sformatf("S5 tx_done pulsed %0d times", txdone_cnt));
            if (tstart_cnt != 1)  fail($sformatf("S6 PHY-TXSTART.confirm %0d times", tstart_cnt));
            if (tend_cnt != 1)    fail($sformatf("S6 PHY-TXEND.confirm %0d times", tend_cnt));
            if (txstart_cnt != 1) fail($sformatf("S9 tx_start %0d times", txstart_cnt));
            if (bb_idx < 320 || ((bb_idx - 320) % 80) != 0 || bb_idx != 320 + 80*(map_idx/48))
                fail($sformatf("S5 %0d samples for %0d mapper values", bb_idx, map_idx));
            if (map_idx % 48 != 0) fail($sformatf("S1 %0d mapper values (not whole symbols)", map_idx));
            nrx = map_idx / 48;
            bad_sym = 0; max_err = 0;
            // all symbols must be exact; after an abort the closing symbol (the last one) is excluded
            for (int k = 0; k < nrx - ((cur_mode == 1 && !abort_late) ? 1 : 0); k++) begin
                if (map_sym_err[k] != 0 || bb_sym_err[k] != 0) begin
                    bad_sym++;
                    if (bad_sym <= 3) fail($sformatf("S1/S3 symbol %0d: %0d mapper values wrong, %0d samples > TOL", k, map_sym_err[k], bb_sym_err[k]));
                end
                if (bb_sym_max[k] > max_err) max_err = bb_sym_max[k];
            end
            if (cur_mode == 0) begin
                if (nrx != cur_nsym + 1) fail($sformatf("S1 %0d symbols, expected %0d", nrx, cur_nsym + 1));
                if (dconf_cnt != cur_len) fail($sformatf("S6 %0d PHY-DATA.confirm, LENGTH %0d", dconf_cnt, cur_len));
                if (pe_cnt != cur_nsym) fail($sformatf("S9 packet_end %0d times, expected %0d", pe_cnt, cur_nsym));
                if (seed_cnt != 0) fail("S12 scrambler seed of the DUT differs from the golden vectors (rerun pass 2)");
                snr = (bb_err_e > 0.0) ? 10.0*$log10(bb_sig_e / bb_err_e) : 999.0;
                if (snr < SNR_MIN) fail($sformatf("S3 SNR %.1f dB < %.1f", snr, SNR_MIN));
                tag = "";
            end else begin
                if (abort_late) begin
                    if (nrx != cur_nsym + 1) fail($sformatf("S11 late abort: %0d of %0d symbols sent (packet must complete)", nrx, cur_nsym + 1));
                end else if (nrx >= cur_nsym + 1)
                    fail($sformatf("S11 abort: %0d of %0d symbols sent (not truncated)", nrx, cur_nsym + 1));
                if (dconf_cnt > cur_len) fail("S11 more PHY-DATA.confirm than LENGTH");
                snr = 0.0;
                // if/else, not ?: - Icarus returns an empty string for ?: between two $sformatf
                if (abort_late)
                    tag = $sformatf(" (ABORT %0d clk after TXSTART.confirm, after the last symbol was committed: complete packet, all %0d symbols bit-exact)", cur_param, nrx);
                else
                    tag = $sformatf(" (ABORT %0d clk after TXSTART.confirm: %0d of %0d symbols, closed cleanly)", cur_param, nrx, cur_nsym + 1);
            end
            $display("pkt %3d | %2d Mb/s len %4d seed 0x%02h nsym %4d | map %5d drop %0d | bb %6d gaps %0d maxerr %0d SNR %5.1f | PHY-DATA %4d | %7d clk | %s%s",
                     cur_pkt, cur_rate, cur_len, cur_seed, cur_nsym, map_idx, map_drop, bb_idx, bb_gap, max_err, snr,
                     dconf_cnt, txdone_cyc - first_bb_cyc + 1, (errors == e0) ? "PASS" : "FAIL", tag);
        end
        $fclose(fbb); fbb = 0; $fclose(fdac); fdac = 0;
    endtask

    // ------------------------------------------------------------------ main
    initial begin
        int fd, npkt, pa;
        pa = $value$plusargs("VEC=%s", vec_dir);
        pa = $value$plusargs("OUT=%s", out_dir);
        pa = $value$plusargs("TOL=%d", TOL);
        pa = $value$plusargs("SNR_MIN=%f", SNR_MIN);
        $display("==== tb_tx_top: VEC=%s OUT=%s w_clk period %0d ps TOL=%0d SNR_MIN=%.0f ====", vec_dir, out_dir, WCLK_PS, TOL, SNR_MIN);
        $sformat(fname, "%0s/pkt_list.txt", vec_dir);
        fd = $fopen(fname, "r");
        if (fd == 0) $fatal(1, "cannot open %s/pkt_list.txt", vec_dir);
        pa = $fscanf(fd, "%d", npkt);

        #1 r_rstn = 0; w_rstn = 0;
        repeat (10) @(negedge r_clk);
        r_rstn = 1; w_rstn = 1;
        repeat (10) @(negedge r_clk);
        chk_en = 1;

        for (cur_pkt = 0; cur_pkt < npkt; cur_pkt++)
            run_entry(fd);                // the MAC sends the next packet right after PHY-TXEND.confirm
        $fclose(fd);
        repeat (2000) @(negedge r_clk);
        $display("----------------------------------------------------------------------");
        $display("DAC model: %0d clocks bit-exact, %0d mismatches; min inter-packet gap %0d clocks", dac_ok, dac_err, min_gap);
        if (dac_ok == 0) fail("S8 DAC never compared");
        if (errors == 0) $display("*** TEST PASSED : %0d entries, 0 errors ***", npkt);
        else             $display("*** TEST FAILED : %0d errors ***", errors);
        $finish;
    end

    initial begin
        longint gt_ms = 3;                    // +GTIMEOUT_MS=<n> for long random / max-length runs
        void'($value$plusargs("GTIMEOUT_MS=%d", gt_ms));
        #(gt_ms * 64'd1_000_000);
        $display("*** TEST FAILED : global timeout ***");
        $finish;
    end

endmodule
