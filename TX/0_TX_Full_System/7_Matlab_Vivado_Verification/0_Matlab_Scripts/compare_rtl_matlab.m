function R = compare_rtl_matlab(varargin)
%COMPARE_RTL_MATLAB  Compare the Vivado RTL outputs with the MATLAB golden reference.
%
%   R = compare_rtl_matlab()
%   R = compare_rtl_matlab('VecDir', d1, 'OutDir', d2, 'Log', 'xsim_smoke.log', ...
%                          'TOL', 32, 'SNR_MIN', 50, 'Decode', true)
%
%   Inputs  : <VecDir>/golden_db.mat              (written by generate_tx_vectors)
%             <OutDir>/rtl_bb_pktNNN.txt          tx_mux 20 MS/s stream, "I Q" per line
%             <OutDir>/rtl_dac_pktNNN.txt         DAC pins, one line per 80 MHz clock
%             <OutDir>/xsim_*.log                 TB log (SEED / PASS / FAIL lines)
%   Outputs : <OutDir>/compare_results.mat, compare_report.txt, compare_report.csv
%
%   Checks per normal packet (MODE 0):
%     K1 sample count            = 320 + 80*(NSYM+1)
%     K2 preamble                bit-exact (320 samples)
%     K3 SIGNAL/DATA samples     max(|dI|,|dQ|) <= TOL per sample (same metric as the TB)
%     K4 SNR                     10log10(sum|golden|^2 / sum|err|^2) >= SNR_MIN, per packet;
%                                per-symbol SNR also reported
%     K5 EVM                     FFT of every RTL symbol vs the ideal constellation + pilots,
%                                52 tones, <= -SNR_MIN dB (also shown: Table 90 limit)
%     K6 mapper / subcarrier map hard decision of every data tone == golden point,
%                                pilot signs == p_n (catches ordering / mapping errors)
%     K7 cyclic prefix           RTL samples 0..15 == samples 64..79 of every symbol
%     K8 standard receiver       RTL waveform decoded with wlanLSIGRecover /
%                                wlanNonHTDataRecover -> RATE, LENGTH and PSDU (0 bit errors)
%     K9 DAC                     DAC pins == x4 zero-stuff + FIR model of the RTL baseband
%                                (bit-exact) and SNR of DAC vs model of the golden baseband;
%                                DAC idle (0) outside the packet
%   MODE 1: preamble exact, every complete symbol except the closing one within TOL
%           (all symbols if the packet completed), no extra samples.
%   MODE 2: nothing on air (empty baseband file, DAC all zero).
%   MODE 3: reset entry, not compared (the TB does not check it either).

cfg = tx_config();
opt.vecdir = cfg.vec_dir; opt.outdir = cfg.out_dir; opt.log = '';
opt.tol = []; opt.snr_min = []; opt.decode = true; opt.quiet = false;
for k = 1:2:numel(varargin)
    switch lower(varargin{k})
        case 'vecdir',  opt.vecdir = varargin{k+1};
        case 'outdir',  opt.outdir = varargin{k+1};
        case 'log',     opt.log = varargin{k+1};
        case 'tol',     opt.tol = varargin{k+1};
        case 'snr_min', opt.snr_min = varargin{k+1};
        case 'decode',  opt.decode = varargin{k+1};
        case 'quiet',   opt.quiet = varargin{k+1};
        otherwise, error('compare:arg', 'Unknown option %s', varargin{k});
    end
end
F = tx_rtl_format();
S = load(fullfile(opt.vecdir, 'golden_db.mat'));
db = S.db; meta = S.meta;
N = numel(db);

% ---- TB log
LG = [];
if isempty(opt.log)
    d = dir(fullfile(opt.outdir, 'xsim_*.log'));
    if ~isempty(d)
        [~, j] = max([d.datenum]);
        opt.log = fullfile(opt.outdir, d(j).name);
    end
elseif ~exist(opt.log, 'file')
    opt.log = fullfile(opt.outdir, opt.log);
end
if ~isempty(opt.log) && exist(opt.log, 'file')
    LG = read_tb_log(opt.log);
end
tol = cfg.tb.TOL; snr_min = cfg.tb.SNR_MIN;
if ~isempty(LG) && ~isempty(LG.header)
    t = regexp(LG.header, 'TOL=(\d+)', 'tokens', 'once');      if ~isempty(t), tol = str2double(t{1}); end
    t = regexp(LG.header, 'SNR_MIN=([\d.]+)', 'tokens', 'once'); if ~isempty(t), snr_min = str2double(t{1}); end
end
if ~isempty(opt.tol), tol = opt.tol; end
if ~isempty(opt.snr_min), snr_min = opt.snr_min; end
have_tbx = opt.decode && exist('wlanNonHTDataRecover', 'file') > 0;

pseq = 1 - 2 * scr127();
dsc = mod([-26:-22, -20:-8, -6:-1, 1:6, 8:20, 22:26], 64) + 1;
psc = mod([-21 -7 7 21], 64) + 1;
occ = sort([dsc psc]);
nbpsc_tab = containers.Map({6, 9, 12, 18, 24, 36, 48, 54}, {1, 1, 2, 2, 4, 4, 6, 6});

R.meta = meta; R.opt = opt; R.tol = tol; R.snr_min = snr_min; R.log = LG;
R.pkt = repmat(empty_result(), N, 1);

for i = 1:N
    g = db(i);
    r = empty_result();
    r.pkt = i - 1; r.rate = g.rate; r.len = g.len; r.nsym = g.nsym; r.mode = g.mode;
    r.param = g.param; r.seed = g.seed; r.note = g.note;
    r.n_exp = 320 + 80 * (g.nsym + 1);
    if ~isempty(LG) && numel(LG.entry) >= i
        r.tb_verdict = LG.entry(i).verdict;
        r.tb_line = LG.entry(i).line;
    end
    if ~isempty(LG) && numel(LG.seed) >= i && ~isnan(LG.seed(i))
        r.dut_seed = LG.seed(i);
    end
    bbf  = fullfile(opt.outdir, sprintf('rtl_bb_pkt%03d.txt', i - 1));
    dacf = fullfile(opt.outdir, sprintf('rtl_dac_pkt%03d.txt', i - 1));
    if ~exist(bbf, 'file')
        r.verdict = 'NO DATA'; r.notes{end+1} = 'rtl_bb file missing (entry not simulated?)';
        R.pkt(i) = r; continue;
    end
    bb = read_iq(bbf);
    dac = read_iq(dacf);
    r.n_bb = numel(bb);

    if g.mode == 3
        r.verdict = 'NOT CHECKED'; r.notes{end+1} = 'reset entry';
        R.pkt(i) = r; continue;
    end
    if g.mode == 2
        r = check(r, r.n_bb == 0, sprintf('K1 bad RATE: %d samples on air (expected 0)', r.n_bb));
        if ~isempty(dac)
            r = check(r, all(dac == 0), 'K9 bad RATE: DAC pins not idle');
        end
        R.pkt(i) = finalize(r); continue;
    end

    % ---- MODE 0 / 1
    if g.mode == 1 && r.n_bb == 0
        r.complete = false; r.n_sym_rx = 0;
        r.notes{end+1} = 'aborted before the PHY started: nothing on air';
        if ~isempty(dac), r = check(r, all(dac == 0), 'K9 DAC pins not idle'); end
        R.pkt(i) = finalize(r); continue;
    end
    nrx = (r.n_bb - 320) / 80;
    r = check(r, r.n_bb >= 320 && nrx == round(nrx) && nrx <= g.nsym + 1, ...
        sprintf('K1 %d samples is not preamble + whole symbols (expected %d)', r.n_bb, r.n_exp));
    if r.n_bb < 320 || nrx ~= round(nrx) || nrx > g.nsym + 1
        R.pkt(i) = finalize(r); continue;
    end
    r.n_sym_rx = nrx;
    r.complete = (nrx == g.nsym + 1);
    if g.mode == 0
        r = check(r, r.complete, sprintf('K1 %d symbols, expected %d', nrx, g.nsym + 1));
    end
    gi = g.bb_int(1:r.n_bb);
    gf = g.wave(1:r.n_bb) * 2^14;
    % K2 preamble
    r.pre_mismatch = sum(bb(1:320) ~= gi(1:320));
    r = check(r, r.pre_mismatch == 0, sprintf('K2 preamble: %d samples differ', r.pre_mismatch));
    % symbols to judge: all for a complete packet, all but the closing one after a truncating abort
    njudge = nrx;
    if g.mode == 1 && ~r.complete, njudge = nrx - 1; end
    r.sym_maxerr = zeros(1, nrx); r.sym_snr = zeros(1, nrx); r.sym_evm_db = zeros(1, nrx);
    r.sym_rms = zeros(1, nrx);
    se = 0; ee = 0; hard = 0; pil = 0; cpb = 0; ev_num = 0; ev_den = 0; leak = 0;
    nb = nbpsc_tab(g.rate);
    for s = 0:nrx - 1
        ix = 320 + 80 * s + (1:80);
        rs = bb(ix); gs = gi(ix);
        dI = real(rs) - real(gs); dQ = imag(rs) - imag(gs);
        r.sym_maxerr(s + 1) = max(max(abs(dI)), max(abs(dQ)));
        r.sym_rms(s + 1) = sqrt(mean(abs(rs - gf(ix)).^2));
        es = sum(abs(gf(ix)).^2); er = sum(abs(rs - gf(ix)).^2);
        r.sym_snr(s + 1) = 10 * log10(es / max(er, eps));
        Xr = fft(double(rs(17:80))) / 2^14;
        Xg = golden_freq(g, s, dsc, psc, pseq);
        en = sum(abs(Xr(occ) - Xg(occ)).^2); ed = sum(abs(Xg(occ)).^2);
        r.sym_evm_db(s + 1) = 10 * log10(max(en, eps) / ed);
        leak = max(leak, max(abs(Xr(setdiff(1:64, occ)))));
        if s < njudge
            se = se + es; ee = ee + er; ev_num = ev_num + en; ev_den = ev_den + ed;
            nbs = nb; if s == 0, nbs = 1; end
            hard = hard + sum(slice(Xr(dsc), nbs) ~= slice(Xg(dsc), nbs));
            pil = pil + sum(sign(real(Xr(psc))) ~= sign(real(Xg(psc))));
            cpb = cpb + any(rs(1:16) ~= rs(65:80));
        end
    end
    j = 1:njudge;
    if njudge > 0
        r.max_err = max(r.sym_maxerr(j));
        r.snr_db = 10 * log10(se / max(ee, eps));
        r.evm_db = 10 * log10(max(ev_num, eps) / ev_den);
        r.rms_err = sqrt(ee / (80 * njudge));
        r.leak_lsb = leak * 2^14;
        r.hard_err = hard; r.pilot_err = pil; r.cp_err = cpb;
        r.n_tol_viol = sum(r.sym_maxerr(j) > tol);
        r = check(r, r.max_err <= tol, sprintf('K3 max |err| %d > TOL %d in %d symbol(s)', r.max_err, tol, r.n_tol_viol));
        if g.mode == 0
            r = check(r, r.snr_db >= snr_min, sprintf('K4 SNR %.1f dB < %.1f dB', r.snr_db, snr_min));
        end
        r = check(r, r.evm_db <= -snr_min, sprintf('K5 EVM %.1f dB > %.1f dB', r.evm_db, -snr_min));
        r = check(r, hard == 0 && pil == 0, sprintf('K6 %d data tones / %d pilots decided wrong', hard, pil));
        r = check(r, cpb == 0, sprintf('K7 cyclic prefix wrong in %d symbols', cpb));
    end
    % K8 standard receiver on the RTL waveform
    if g.mode == 0 && have_tbx && r.complete
        try
            [ok, msg] = rx_decode(bb, g);
            r.decode = ternary(ok, 'PASS', 'FAIL');
            r = check(r, ok, ['K8 ' msg]);
        catch err
            r.decode = 'ERROR'; r = check(r, false, ['K8 receiver error: ' err.message]);
        end
    else
        r.decode = 'NOT RUN';
    end
    % K9 DAC
    if ~isempty(dac)
        m1 = F.dac_model(bb, F);
        lag = best_lag(dac, m1);
        [mm, outside, win] = dac_compare(dac, m1, lag);
        r.dac_lag = lag; r.dac_mismatch = mm; r.dac_outside = outside;
        r = check(r, mm == 0, sprintf('K9 DAC differs from FIR model of the RTL baseband in %d clocks', mm));
        r = check(r, outside == 0, sprintf('K9 DAC not idle outside the packet (%d clocks)', outside));
        % SNR of the DAC output vs the FIR model driven by the GOLDEN baseband
        % (only over judged symbols: the closing symbol of a truncated abort is excluded)
        nj = 320 + 80 * njudge;
        m2 = F.dac_model(gi(1:nj), F);
        n2 = min(numel(win), 4 * nj);
        r.dac_snr_db = 10 * log10(sum(abs(m2(1:n2)).^2) / max(sum(abs(win(1:n2) - m2(1:n2)).^2), eps));
        r.dac_peak = max(abs([real(dac); imag(dac)]));
    else
        r.notes{end+1} = 'rtl_dac file missing or empty';
    end
    R.pkt(i) = finalize(r);
end

R.summary = summarize(R, db);
write_reports(R, opt.outdir);
if ~opt.quiet, print_report(R); end
save(fullfile(opt.outdir, 'compare_results.mat'), 'R', '-v7');
end

% =========================================================================
function r = empty_result()
r = struct('pkt', 0, 'rate', 0, 'len', 0, 'nsym', 0, 'mode', 0, 'param', 0, 'seed', 0, ...
    'dut_seed', NaN, 'note', '', 'n_bb', 0, 'n_exp', 0, 'n_sym_rx', NaN, 'complete', false, ...
    'pre_mismatch', NaN, 'max_err', NaN, 'rms_err', NaN, 'snr_db', NaN, 'evm_db', NaN, ...
    'leak_lsb', NaN, 'n_tol_viol', NaN, 'hard_err', NaN, 'pilot_err', NaN, 'cp_err', NaN, ...
    'sym_maxerr', [], 'sym_snr', [], 'sym_evm_db', [], 'sym_rms', [], 'decode', 'NOT RUN', ...
    'dac_lag', NaN, 'dac_mismatch', NaN, 'dac_outside', NaN, 'dac_snr_db', NaN, 'dac_peak', NaN, ...
    'tb_verdict', 'NO LOG', 'tb_line', '', 'verdict', '', 'fails', {{}}, 'notes', {{}});
end

function r = check(r, ok, msg)
if ~ok
    r.fails{end+1} = msg;
end
end

function r = finalize(r)
if isempty(r.verdict)
    r.verdict = ternary(isempty(r.fails), 'PASS', 'FAIL');
end
end

function x = read_iq(name)
x = [];
if ~exist(name, 'file'), return; end
fid = fopen(name, 'r');
v = fscanf(fid, '%d %d', [2 Inf]);
fclose(fid);
if isempty(v), return; end
x = complex(v(1, :), v(2, :)).';
end

function X = golden_freq(g, s, dsc, psc, pseq)
X = zeros(64, 1);
X(dsc) = g.map(:, s + 1);
X(psc) = [1 1 1 -1] * pseq(mod(s, 127) + 1);
end

function d = slice(X, nbpsc)
% nearest constellation point (hard decision), returned as integer level pair
switch nbpsc
    case 1, K = 1;            lev = [-1 1];
    case 2, K = 1 / sqrt(2);  lev = [-1 1];
    case 4, K = 1 / sqrt(10); lev = [-3 -1 1 3];
    case 6, K = 1 / sqrt(42); lev = [-7 -5 -3 -1 1 3 5 7];
end
d = zeros(numel(X), 2);
for c = 1:2
    if c == 1, v = real(X(:)) / K; else, v = imag(X(:)) / K; end
    [~, j] = min(abs(v - lev), [], 2);
    d(:, c) = lev(j);
end
if nbpsc == 1, d(:, 2) = 0; end
d = d(:, 1) * 100 + d(:, 2);
end

function lag = best_lag(dac, m)
n = numel(dac) + numel(m);
nf = 2^nextpow2(n);
c = ifft(fft(dac, nf) .* conj(fft(m, nf)));
c = abs(c(1:numel(dac)));
[~, j] = max(c);
lag = j - 1;
end

function [mm, outside, win] = dac_compare(dac, m, lag)
n = numel(m);
last = min(numel(dac), lag + n);
win = dac(lag + 1:last);
mm = sum(win ~= m(1:numel(win))) + (n - numel(win));   % missing tail counts as mismatch
o = true(numel(dac), 1); o(lag + 1:last) = false;
outside = sum(dac(o) ~= 0);
end

function [ok, msg] = rx_decode(bb, g)
mcs = find([6 9 12 18 24 36 48 54] == g.rate) - 1;
cfgN = wlanNonHTConfig('ChannelBandwidth', 'CBW20', 'Modulation', 'OFDM', 'MCS', mcs, 'PSDULength', g.len);
rx = double(bb) / 2^14 * 64 / sqrt(52);
ind = wlanFieldIndices(cfgN);
chEst = ones(52, 1);
[sb, failCheck] = wlanLSIGRecover(rx(ind.LSIG(1):ind.LSIG(2)), chEst, 1e-4, 'CBW20');
sb = double(sb(:)).';
rbits = [1 1 0 1; 1 1 1 1; 0 1 0 1; 0 1 1 1; 1 0 0 1; 1 0 1 1; 0 0 0 1; 0 0 1 1];
lenRx = sum(sb(6:17) .* 2.^(0:11));
if failCheck || ~isequal(sb(1:4), rbits(mcs + 1, :)) || lenRx ~= g.len
    ok = false; msg = sprintf('L-SIG of the RTL waveform: parity fail %d, RATE %s, LENGTH %d', failCheck, mat2str(sb(1:4)), lenRx);
    return;
end
if rate == 9 && nsym == 1, ok = true; return; end
bits = wlanNonHTDataRecover(rx(ind.NonHTData(1):ind.NonHTData(2)), chEst, 1e-4, cfgN);
txb = mod(floor(g.psdu(:) * 2.^-(0:7)), 2).';
nerr = sum(double(bits(:)) ~= txb(:));
ok = nerr == 0;
msg = sprintf('PSDU decoded from the RTL waveform: %d bit errors', nerr);
end

function S = summarize(R, db)
P = R.pkt;
S.n = numel(P);
S.n_pass = sum(strcmp({P.verdict}, 'PASS'));
S.n_fail = sum(strcmp({P.verdict}, 'FAIL'));
S.n_nodata = sum(strcmp({P.verdict}, 'NO DATA'));
S.n_notchecked = sum(strcmp({P.verdict}, 'NOT CHECKED'));
m0 = [P.mode] == 0 & strcmp({P.verdict}, 'PASS');
S.max_err = max([P([P.mode] <= 1).max_err, -Inf]);
okp = [P.mode] <= 1 & strcmp({P.verdict}, 'PASS');
S.max_err_pass = max([P(okp).max_err, -Inf]);
S.min_snr = min([P([P.mode] == 0).snr_db, Inf]);
S.max_evm = max([P([P.mode] <= 1).evm_db, -Inf]);
rms = [P([P.mode] <= 1).rms_err];
S.mean_rms = mean(rms(~isnan(rms)));
S.rates_pass = unique([P(m0).rate]);
S.len_pass = [P(m0).len];
S.nsym_pass = [P(m0).nsym];
S.patterns_pass = unique({db(m0).pattern});
S.seeds = unique([P(~isnan([P.dut_seed])).dut_seed]);
ab = [P.mode] == 1;
S.abort_none = sum(ab & [P.n_bb] == 0 & strcmp({P.verdict}, 'PASS'));
S.abort_trunc = sum(ab & ~[P.complete] & [P.n_bb] > 0 & strcmp({P.verdict}, 'PASS'));
S.abort_late = sum(ab & [P.complete] & strcmp({P.verdict}, 'PASS'));
S.badrate_pass = sum([P.mode] == 2 & strcmp({P.verdict}, 'PASS'));
S.reset_entries = sum([P.mode] == 3);
S.dac_bitexact_pkts = sum([P.dac_mismatch] == 0);
dmin = [512 512 362 362 162 162 79 79];      % LSB, smallest single-tone error signature per rate
S.tol_window = sprintf(['TOL must exceed the fixed-point error (measured max %g LSB over passing packets) and stay below the ' ...
    'smallest single-subcarrier error signature: one nearest-neighbour error of a 64-QAM tone ' ...
    '= (2/sqrt(42))*2^14/64 = %d LSB on every sample of that symbol (16-QAM %d, QPSK %d, BPSK/pilot %d).'], ...
    S.max_err_pass, dmin(7), dmin(5), dmin(3), dmin(1));
end

function write_reports(R, outdir)
fid = fopen(fullfile(outdir, 'compare_report.csv'), 'w');
fprintf(fid, ['pkt,rate,length,nsym,mode,param,seed,dut_seed,samples,expected,symbols_rx,complete,' ...
    'preamble_mismatch,max_err,rms_err,snr_db,evm_db,hard_err,pilot_err,cp_err,decode,' ...
    'dac_mismatch,dac_outside,dac_snr_db,tb_verdict,matlab_verdict,first_failure\n']);
for i = 1:numel(R.pkt)
    p = R.pkt(i);
    ff = ''; if ~isempty(p.fails), ff = strrep(p.fails{1}, ',', ';'); end
    fprintf(fid, '%d,%d,%d,%d,%d,%d,%d,%g,%d,%d,%g,%d,%g,%g,%.3f,%.2f,%.2f,%g,%g,%g,%s,%g,%g,%.2f,%s,%s,"%s"\n', ...
        p.pkt, p.rate, p.len, p.nsym, p.mode, round(p.param), p.seed, p.dut_seed, p.n_bb, p.n_exp, ...
        p.n_sym_rx, p.complete, p.pre_mismatch, p.max_err, p.rms_err, p.snr_db, p.evm_db, p.hard_err, ...
        p.pilot_err, p.cp_err, p.decode, p.dac_mismatch, p.dac_outside, p.dac_snr_db, p.tb_verdict, p.verdict, ff);
end
fclose(fid);
fid = fopen(fullfile(outdir, 'compare_report.txt'), 'w');
print_report(R, fid);
fclose(fid);
end

function print_report(R, fid)
if nargin < 2, fid = 1; end
S = R.summary;
fprintf(fid, '==== compare_rtl_matlab  (TOL=%d, SNR_MIN=%.1f dB) ====\n', R.tol, R.snr_min);
if ~isempty(R.log), fprintf(fid, 'TB log: %s  -> TB verdict %s\n', R.log.file, R.log.final); end
fprintf(fid, ' pkt rate  len nsym mode |   bb  sym | pre maxE  rmsE   SNRdB  EVMdB hard cp | dec  | DAC mm  DAC SNR | TB      MATLAB\n');
for i = 1:numel(R.pkt)
    p = R.pkt(i);
    fprintf(fid, '%4d %4d %4d %4d %4d | %5d %4g | %3g %4g %5.2f %7.2f %6.1f %4g %2g | %-4s | %6g %7.1f | %-7s %s\n', ...
        p.pkt, p.rate, p.len, p.nsym, p.mode, p.n_bb, p.n_sym_rx, p.pre_mismatch, p.max_err, p.rms_err, ...
        p.snr_db, p.evm_db, p.hard_err, p.cp_err, shortdec(p.decode), p.dac_mismatch, p.dac_snr_db, ...
        p.tb_verdict, p.verdict);
    for k = 1:numel(p.fails)
        fprintf(fid, '        FAIL: %s\n', p.fails{k});
    end
    for k = 1:numel(p.notes)
        fprintf(fid, '        note: %s\n', p.notes{k});
    end
end
fprintf(fid, '---- summary ----\n');
fprintf(fid, 'entries %d: PASS %d, FAIL %d, NOT CHECKED %d, NO DATA %d\n', S.n, S.n_pass, S.n_fail, S.n_notchecked, S.n_nodata);
fprintf(fid, 'worst max|err| %g LSB, mean RMS err %.3f LSB, worst packet SNR %.2f dB, worst EVM %.2f dB\n', ...
    S.max_err, S.mean_rms, S.min_snr, S.max_evm);
fprintf(fid, 'rates passed: %s\n', mat2str(S.rates_pass));
if ~isempty(S.len_pass)
    fprintf(fid, 'LENGTH passed: min %d max %d (%d packets), NSYM %d..%d\n', min(S.len_pass), max(S.len_pass), ...
        numel(S.len_pass), min(S.nsym_pass), max(S.nsym_pass));
end
fprintf(fid, 'payload patterns passed: %s\n', strjoin(S.patterns_pass, ', '));
fprintf(fid, 'distinct DUT scrambler seeds: %d\n', numel(S.seeds));
fprintf(fid, 'aborts passed: before start %d, truncated %d, late/complete %d; bad RATE passed %d; reset entries %d\n', ...
    S.abort_none, S.abort_trunc, S.abort_late, S.badrate_pass, S.reset_entries);
fprintf(fid, '%s\n', S.tol_window);
if ~isempty(R.log)
    fprintf(fid, 'TB DAC model: %g clocks bit-exact, %g mismatches; TB ERROR lines: %d\n', ...
        R.log.dac_ok, R.log.dac_err, size(R.log.errors, 1));
end
end

function s = shortdec(d)
switch d
    case 'NOT RUN', s = 'n/r';
    otherwise, s = d;
end
end

function s = scr127()
st = ones(1, 7); s = zeros(127, 1);
for k = 1:127
    t = xor(st(7), st(4)); s(k) = t; st = [t st(1:6)];
end
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end
