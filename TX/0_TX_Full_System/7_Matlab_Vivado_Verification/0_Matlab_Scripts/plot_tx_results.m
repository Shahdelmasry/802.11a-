function plot_tx_results(R, pkt, varargin)
%PLOT_TX_RESULTS  Verification plots for one packet and for the whole regression.
%
%   plot_tx_results()                    loads <out_dir>/compare_results.mat, worst MODE-0 packet
%   plot_tx_results(R, pkt)              R from compare_rtl_matlab, pkt = 0-based entry index
%   plot_tx_results(R, pkt, 'Save', true, 'Visible', 'on')
%
%   Figures (saved as PNG in <out_dir>/plots when 'Save' is true, default):
%     1 baseband I/Q, RTL over golden, with field / symbol boundaries
%     2 I/Q error per sample with +/-TOL, per-symbol max error
%     3 constellation of the RTL symbols (FFT of the RTL output) over the ideal points
%     4 per-symbol SNR and EVM with the thresholds
%     5 error histogram (I and Q)
%     6 DAC output (80 MS/s): spectrum vs the 17.3.9.2 transmit mask, time overlay with model
%     7 regression overview: max error, SNR, EVM per entry

cfg = tx_config();
if nargin < 1 || isempty(R)
    S = load(fullfile(cfg.out_dir, 'compare_results.mat'));
    R = S.R;
end
save_png = true; vis = 'on';
for k = 1:2:numel(varargin)
    switch lower(varargin{k})
        case 'save', save_png = varargin{k+1};
        case 'visible', vis = varargin{k+1};
    end
end
P = R.pkt;
if nargin < 2 || isempty(pkt)
    cand = find([P.mode] == 0 & [P.n_bb] > 0);
    if isempty(cand), cand = find([P.n_bb] > 0); end
    if isempty(cand), error('plot_tx_results:nodata', 'No packet with RTL data.'); end
    [~, j] = max([P(cand).max_err]);
    pkt = P(cand(j)).pkt;
end
F = tx_rtl_format();
S = load(fullfile(R.opt.vecdir, 'golden_db.mat'));
g = S.db(pkt + 1);
p = P(pkt + 1);
outdir = R.opt.outdir;
plotdir = fullfile(outdir, 'plots');
if save_png && ~exist(plotdir, 'dir'), mkdir(plotdir); end
bb  = read_iq(fullfile(outdir, sprintf('rtl_bb_pkt%03d.txt', pkt)));
dac = read_iq(fullfile(outdir, sprintf('rtl_dac_pkt%03d.txt', pkt)));
n = numel(bb);
if n == 0, error('plot_tx_results:nodata', 'Entry %d has no RTL baseband samples.', pkt); end
gi = g.bb_int(1:n);
ttl = sprintf('pkt %d: %d Mb/s, LENGTH %d, NSYM %d, mode %d', pkt, g.rate, g.len, g.nsym, g.mode);
t = 0:n-1;
bounds = [160 320:80:n];

% ---- 1 waveform overlay
f = figure('Name', 'waveform', 'Visible', vis);
for c = 1:2
    subplot(2, 1, c);
    if c == 1, gr = real(gi); rr = real(bb); lab = 'I'; else, gr = imag(gi); rr = imag(bb); lab = 'Q'; end
plot(t, gr, 'b-', 'LineWidth', 1.5); hold on;
plot(t, rr, '--', 'Color', [0 0.75 0], 'LineWidth', 1.5);    yl = ylim; plot([bounds; bounds], repmat(yl.', 1, numel(bounds)), 'k:'); hold off;
    ylabel([lab ' (LSB, Q2.14)']); grid on;
    legend('MATLAB golden', 'RTL', 'Location', 'best');
end
xlabel('sample @ 20 MS/s'); subplot(2, 1, 1); title(ttl);
save_fig(f, plotdir, sprintf('pkt%03d_1_waveform.png', pkt), save_png);

% ---- 2 error
f = figure('Name', 'error', 'Visible', vis);
subplot(2, 1, 1);
e = bb - gi;
plot(t, real(e), 'b.', t, imag(e), 'r.'); hold on;
plot([0 n], [R.tol R.tol], 'k--', [0 n], -[R.tol R.tol], 'k--'); hold off;
grid on; ylabel('RTL - golden (LSB)'); legend('I', 'Q', '\pmTOL'); title([ttl ' - error']);
subplot(2, 1, 2);
if ~isempty(p.sym_maxerr)
    bar(0:numel(p.sym_maxerr) - 1, p.sym_maxerr); hold on;
    plot([-0.5 numel(p.sym_maxerr) - 0.5], [R.tol R.tol], 'r--'); hold off;
end
grid on; xlabel('OFDM symbol (0 = SIGNAL)'); ylabel('max |err| (LSB)');
save_fig(f, plotdir, sprintf('pkt%03d_2_error.png', pkt), save_png);

% ---- 3 constellation
f = figure('Name', 'constellation', 'Visible', vis);
dsc = mod([-26:-22, -20:-8, -6:-1, 1:6, 8:20, 22:26], 64) + 1;
psc = mod([-21 -7 7 21], 64) + 1;
nrx = floor((n - 320) / 80);
Xd = []; Xp = []; Xs = [];
for s = 0:nrx - 1
    X = fft(double(bb(320 + 80 * s + (17:80)))) / 2^14;
    if s == 0, Xs = [Xs; X(dsc)]; else, Xd = [Xd; X(dsc)]; end %#ok<AGROW>
    Xp = [Xp; X(psc)]; %#ok<AGROW>
end
ideal = unique(round(g.map(:, 2:end) * 1e6) / 1e6);
plot(real(Xd), imag(Xd), 'b.', real(Xs), imag(Xs), 'g.', real(Xp), imag(Xp), 'm.', ...
     real(ideal), imag(ideal), 'ko', 'MarkerSize', 8);
axis equal; grid on; xlabel('I'); ylabel('Q');
legend('RTL DATA tones', 'RTL SIGNAL tones', 'RTL pilots', 'ideal points', 'Location', 'bestoutside');
title(sprintf('%s - RTL constellation, EVM %.1f dB', ttl, p.evm_db));
save_fig(f, plotdir, sprintf('pkt%03d_3_constellation.png', pkt), save_png);

% ---- 4 per-symbol SNR / EVM
f = figure('Name', 'snr_evm', 'Visible', vis);
subplot(2, 1, 1);
if ~isempty(p.sym_snr)
    plot(0:numel(p.sym_snr) - 1, p.sym_snr, 'b.-'); hold on;
    plot([0 numel(p.sym_snr) - 1], [R.snr_min R.snr_min], 'r--'); hold off;
end
grid on; ylabel('SNR (dB)'); title([ttl ' - per-symbol SNR / EVM']); legend('RTL vs golden', 'SNR\_MIN');
subplot(2, 1, 2);
if ~isempty(p.sym_evm_db)
    lim = F.evm_limit_db(F.rate_index(g.rate));
    plot(0:numel(p.sym_evm_db) - 1, p.sym_evm_db, 'b.-'); hold on;
    plot([0 numel(p.sym_evm_db) - 1], -[R.snr_min R.snr_min], 'r--', ...
         [0 numel(p.sym_evm_db) - 1], [lim lim], 'k:'); hold off;
    legend('RTL EVM', '-SNR\_MIN', 'Table 90 limit');
end
grid on; xlabel('OFDM symbol (0 = SIGNAL)'); ylabel('EVM (dB)');
save_fig(f, plotdir, sprintf('pkt%03d_4_snr_evm.png', pkt), save_png);

% ---- 5 histogram
f = figure('Name', 'histogram', 'Visible', vis);
ed = e(321:end);
if ~isempty(ed)
    lo = min([real(ed); imag(ed)]); hi = max([real(ed); imag(ed)]);
    nbin = hi - lo + 1;
    ci = accumarray(real(ed) - lo + 1, 1, [nbin 1]);
    cq = accumarray(imag(ed) - lo + 1, 1, [nbin 1]);
    bar(lo:hi, [ci cq]);
    legend('I error', 'Q error');
end
grid on; xlabel('RTL - golden (LSB), SIGNAL + DATA'); ylabel('count'); title([ttl ' - error histogram']);
save_fig(f, plotdir, sprintf('pkt%03d_5_histogram.png', pkt), save_png);

% ---- 6 DAC
if ~isempty(dac) && any(dac ~= 0)
    f = figure('Name', 'dac', 'Visible', vis);
    m = F.dac_model(bb, F);
    lag = p.dac_lag; if isnan(lag), lag = 0; end
    seg = dac(lag + 1:min(numel(dac), lag + numel(m)));
    [fr, pw] = welch_psd(double(seg), 80e6, 1024);
    pw = 10 * log10(pw / max(pw(abs(fr) <= 9e6)));
    subplot(2, 1, 1);
    [mf, mm] = tx_mask();
    plot(fr / 1e6, pw, 'b', mf / 1e6, mm, 'r--');
    grid on; xlim([-40 40]); ylim([-80 5]);
    xlabel('frequency (MHz), fs = 80 MS/s'); ylabel('dBr'); legend('DAC output PSD', '17.3.9.2 mask');
    viol = pw.' > interp1(mf, mm, fr.', 'linear', 0) + 1e-9;
    title(sprintf('%s - DAC spectrum, mask margin %.1f dB%s', ttl, ...
        min(interp1(mf, mm, fr.', 'linear', 0) - pw.'), ternary(any(viol), ' (VIOLATION)', '')));
    subplot(2, 1, 2);
    k = 1:min(numel(seg), 1600);
    plot(k - 1, real(m(k)), 'b-', k - 1, real(seg(k)), 'r:');
    grid on; xlabel('DAC clock (80 MHz) from packet start'); ylabel('DAC I');
    legend('FIR model of RTL baseband', 'RTL DAC pins');
    save_fig(f, plotdir, sprintf('pkt%03d_6_dac.png', pkt), save_png);
end

% ---- 7 regression overview
f = figure('Name', 'regression', 'Visible', vis);
idx = [P.pkt];
subplot(3, 1, 1); bar(idx, [P.max_err]); hold on; plot([idx(1) - 1 idx(end) + 1], [R.tol R.tol], 'r--'); hold off;
grid on; ylabel('max |err| (LSB)'); title(sprintf('regression: %d entries', numel(P)));
subplot(3, 1, 2); plot(idx, [P.snr_db], 'bo'); hold on; plot([idx(1) - 1 idx(end) + 1], [R.snr_min R.snr_min], 'r--'); hold off;
grid on; ylabel('SNR (dB)');
subplot(3, 1, 3); plot(idx, [P.evm_db], 'bo'); grid on; ylabel('EVM (dB)'); xlabel('pkt');
save_fig(f, plotdir, 'regression_overview.png', save_png);
end

% =========================================================================
function x = read_iq(name)
x = [];
if ~exist(name, 'file'), return; end
fid = fopen(name, 'r'); v = fscanf(fid, '%d %d', [2 Inf]); fclose(fid);
if ~isempty(v), x = complex(v(1, :), v(2, :)).'; end
end

function [f, p] = welch_psd(x, fs, nfft)
x = x(:);
if numel(x) < nfft, x = [x; zeros(nfft - numel(x), 1)]; end
w = 0.5 - 0.5 * cos(2 * pi * (0:nfft-1).' / nfft);
hop = nfft / 2;
nseg = floor((numel(x) - nfft) / hop) + 1;
p = zeros(nfft, 1);
for k = 0:nseg - 1
    s = x(k * hop + (1:nfft)) .* w;
    p = p + abs(fft(s)).^2;
end
p = fftshift(p / nseg);
f = ((0:nfft-1).' - nfft / 2) * fs / nfft;
end

function [f, m] = tx_mask()
% 17.3.9.2: 0 dBr to 9 MHz, -20 dBr at 11 MHz, -28 dBr at 20 MHz, -40 dBr at 30 MHz and beyond
fp = [0 9 11 20 30 40] * 1e6;
mp = [0 0 -20 -28 -40 -40];
f = [-fliplr(fp(2:end)) fp];
m = [fliplr(mp(2:end)) mp];
end

function save_fig(f, d, name, do_save)
if do_save
    print(f, fullfile(d, name), '-dpng', '-r110');
end
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end
