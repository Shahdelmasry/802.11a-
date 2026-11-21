function out = tx_golden_reference(psdu, rate_mbps, seed, varargin)
%TX_GOLDEN_REFERENCE  IEEE 802.11a-1999 OFDM PPDU transmitter reference.
%
%   ref = tx_golden_reference(psdu, rate_mbps, seed)
%   ref = tx_golden_reference(..., 'Engine', 'auto'|'toolbox'|'independent')
%   rep = tx_golden_reference('selftest')
%
%   psdu      : vector of octets 0..255, LENGTH = numel(psdu) = 1..4095
%   rate_mbps : 6, 9, 12, 18, 24, 36, 48 or 54
%   seed      : scrambler initial state 1..127, pkt_list convention
%               (bit 6 = x7 ... bit 0 = x1, tb_tx_top.sv SEED monitor)
%
%   Two implementations are run and must agree:
%     1. INDEPENDENT model written directly from Clause 17 (17.3.2 - 17.3.5.9).
%        Self-tested against Annex G Table G.24 (the standard's own example).
%     2. MATLAB WLAN Toolbox wlanWaveformGenerator (non-HT, CBW20, no windowing).
%   With Engine = 'auto' (default) the toolbox is used when it is installed and
%   its waveform must match the independent model to 1e-9, otherwise an error is
%   raised.  Without the toolbox the independent model is used (a warning is
%   printed once).
%
%   Output scaling: Annex G time-domain scaling, x[n] = (1/64) sum X_k e^{+j2pi kn/64},
%   X_k = normalized constellation (K_MOD) and pilots +/-1; L-STF with sqrt(13/6).
%   No time-domain windowing (it is informative in 17.3.2.4 and not in the RTL).
%
%   Fields of ref:
%     rate, length, seed, nsym, ndbps, ncbps, nbpsc, coding_rate, npad
%     signal_bits (24x1), data_bits (unscrambled DATA field), scr_seq,
%     scrambled_bits (tail zeroed), coded_bits (punctured), interleaved (Ncbps x NSYM)
%     map   : 48 x (NSYM+1) complex constellation, column 1 = SIGNAL,
%             rows = data subcarriers -26..26 in increasing frequency (17.3.5.9)
%     freq  : 64 x (NSYM+1) IFFT input, natural bin order (bin k at row mod(k,64)+1)
%     pilot_pol : 1 x (NSYM+1) p_n, n = 0 (SIGNAL) .. NSYM
%     wave  : (320 + 80*(NSYM+1)) x 1 complex, Annex G scaling
%     engine, xcheck

if ischar(psdu) && strcmpi(psdu, 'selftest')
    out = run_selftest();
    return;
end

engine = 'auto';
for k = 1:2:numel(varargin)
    switch lower(varargin{k})
        case 'engine', engine = lower(varargin{k+1});
        otherwise, error('tx_golden_reference:arg', 'Unknown option "%s".', varargin{k});
    end
end

psdu = double(psdu(:));
if isempty(psdu) || numel(psdu) > 4095 || any(psdu < 0 | psdu > 255 | psdu ~= round(psdu))
    error('tx_golden_reference:psdu', 'PSDU must be 1..4095 octets with values 0..255.');
end
if ~isscalar(seed) || seed < 1 || seed > 127 || seed ~= round(seed)
    error('tx_golden_reference:seed', 'Scrambler seed must be an integer 1..127 (0 is the lock-up state).');
end

out = independent_tx(psdu, rate_mbps, seed);
out.engine = 'independent (Clause 17)';
out.xcheck = struct('wave_maxabs', NaN, 'map_maxabs', NaN);

use_tbx = false;
switch engine
    case 'independent'
    case 'toolbox'
        if ~toolbox_available()
            error('tx_golden_reference:toolbox', 'WLAN Toolbox (wlanWaveformGenerator) not found.');
        end
        use_tbx = true;
    case 'auto'
        use_tbx = toolbox_available();
        if ~use_tbx
            warn_once('WLAN Toolbox not found: golden vectors come from the independent Clause-17 model only.');
        end
    otherwise
        error('tx_golden_reference:arg', 'Engine must be auto, toolbox or independent.');
end

if use_tbx
    tb = toolbox_tx(psdu, rate_mbps, seed, out.nsym);
    dw = max(abs(tb.wave - out.wave));
    dm = max(max(abs(tb.map - out.map)));
    out.xcheck.wave_maxabs = dw;
    out.xcheck.map_maxabs  = dm;
    if dw > 1e-9 || dm > 1e-9
        error('tx_golden_reference:mismatch', ...
            ['WLAN Toolbox and independent model disagree (rate %d, LENGTH %d, seed %d): ' ...
             'max |dwave| = %.3g, max |dmap| = %.3g. Golden vectors NOT generated.'], ...
            rate_mbps, numel(psdu), seed, dw, dm);
    end
    out.wave   = tb.wave;          % toolbox waveform is the exported golden
    out.engine = 'WLAN Toolbox wlanWaveformGenerator (cross-checked with Clause-17 model)';
end
end

% =========================================================================
%  INDEPENDENT CLAUSE-17 MODEL
% =========================================================================
function r = independent_tx(psdu, rate_mbps, seed)
P = rate_params(rate_mbps);
L = numel(psdu);

r.rate = rate_mbps; r.length = L; r.seed = seed;
r.nbpsc = P.nbpsc; r.ncbps = P.ncbps; r.ndbps = P.ndbps; r.coding_rate = P.R;

% ---- SIGNAL field (17.3.4, Figure 111): RATE R1..R4, reserved, LENGTH LSB first, parity, tail
sig = [P.rbits(:); 0; mod(floor(L ./ 2.^(0:11)), 2).'];
sig = [sig; mod(sum(sig), 2); zeros(6, 1)];
r.signal_bits = sig;
sig_coded = conv_encode(sig);                     % R = 1/2, not scrambled (17.3.4)
sig_il    = interleave(sig_coded, 48, 1);
map0      = map_bits(sig_il, 1);

% ---- DATA field (17.3.5): SERVICE(16) | PSDU | tail(6) | pad
nsym  = ceil((16 + 8*L + 6) / P.ndbps);           % Eq. (11)
ndata = nsym * P.ndbps;                           % Eq. (12)
npad  = ndata - (16 + 8*L + 6);                   % Eq. (13)
r.nsym = nsym; r.npad = npad;
data = [zeros(16, 1); bytes_to_bits(psdu); zeros(6 + npad, 1)];
r.data_bits = data;

scr = scrambler_seq(seed_to_x(seed), ndata);      % 17.3.5.4
s = mod(data + scr, 2);
s(16 + 8*L + (1:6)) = 0;                          % 17.3.5.2: tail replaced AFTER scrambling
r.scr_seq = scr;
r.scrambled_bits = s;

coded = puncture(conv_encode(s), P.R);            % 17.3.5.5
r.coded_bits = coded;
if numel(coded) ~= nsym * P.ncbps
    error('tx_golden_reference:internal', 'Coded length %d ~= NSYM*NCBPS.', numel(coded));
end

il  = zeros(P.ncbps, nsym);
map = zeros(48, nsym + 1);
map(:, 1) = map0;
for n = 1:nsym
    blk = coded((n-1)*P.ncbps + (1:P.ncbps));
    il(:, n) = interleave(blk, P.ncbps, P.nbpsc);   % 17.3.5.6
    map(:, n+1) = map_bits(il(:, n), P.nbpsc);      % 17.3.5.7
end
r.interleaved = il;
r.map = map;

% ---- pilots (17.3.5.9), subcarrier mapping, IFFT, GI (17.3.5.9 / 17.3.2.4)
pseq = 1 - 2 * scrambler_seq(ones(1, 7), 127);    % p_0..p_126
pol  = pseq(mod(0:nsym, 127) + 1).';
r.pilot_pol = pol;
dsc = data_subcarriers();
freq = zeros(64, nsym + 1);
for n = 0:nsym
    X = zeros(64, 1);
    X(mod(dsc, 64) + 1) = map(:, n+1);
    X(mod([-21 -7 7 21], 64) + 1) = [1 1 1 -1] * pol(n+1);
    freq(:, n+1) = X;
end
r.freq = freq;
t = ifft(freq);                                   % 1/64 scaling, Annex G convention
t = [t(49:64, :); t];                             % 16-sample cyclic prefix
r.wave = [preamble(); t(:)];
end

function P = rate_params(mbps)
tab = [ 6 1  48  24 1/2; 9 1  48  36 3/4; 12 2  96  48 1/2; 18 2  96  72 3/4;
       24 4 192  96 1/2; 36 4 192 144 3/4; 48 6 288 192 2/3; 54 6 288 216 3/4];
rb  = [1 1 0 1; 1 1 1 1; 0 1 0 1; 0 1 1 1; 1 0 0 1; 1 0 1 1; 0 0 0 1; 0 0 1 1]; % Table 80
i = find(tab(:, 1) == mbps, 1);
if isempty(i)
    error('tx_golden_reference:rate', 'Unsupported rate %g Mb/s.', mbps);
end
P.nbpsc = tab(i, 2); P.ncbps = tab(i, 3); P.ndbps = tab(i, 4); P.R = tab(i, 5);
P.rbits = rb(i, :);
end

function b = bytes_to_bits(bytes)
% 17.3.5.4: octets placed in the serial stream bit 0 first
b = mod(floor(bytes(:) * 2.^-(0:7)), 2).';
b = b(:);
end

function x = seed_to_x(seed)
x = mod(floor(seed ./ 2.^(0:6)), 2);   % [x1 .. x7]
end

function seq = scrambler_seq(x, n)
% Figure 113: S(x) = x^7 + x^4 + 1, output = x7 XOR x4, fed back into x1.
% x = [x1 .. x7].  The sequence is periodic with period 127.
st = x(:).';
base = zeros(127, 1);
for k = 1:127
    t = xor(st(7), st(4));
    base(k) = t;
    st = [t st(1:6)];
end
seq = base(mod(0:n-1, 127) + 1);
end

function c = conv_encode(b)
% Figure 114: K = 7, g0 = 133 (octal) -> output A, g1 = 171 (octal) -> output B,
% A output before B.  Encoder starts in the all-zero state.
b = double(b(:));
g0 = [1 0 1 1 0 1 1];
g1 = [1 1 1 1 0 0 1];
a  = mod(filter(g0, 1, b), 2);
bb = mod(filter(g1, 1, b), 2);
c = reshape([a bb].', [], 1);
end

function p = puncture(c, R)
% Figure 115: keep pattern over the A0 B0 A1 B1 ... stream
switch R
    case 1/2, p = c; return;
    case 3/4, keep = [1 1 1 0 0 1];      % A0 B0 A1 (B1 A2 stolen) B2
    case 2/3, keep = [1 1 1 0];          % A0 B0 A1 (B1 stolen)
end
if mod(numel(c), numel(keep)) ~= 0
    error('tx_golden_reference:internal', 'Puncturing period mismatch.');
end
k = repmat(keep(:), numel(c) / numel(keep), 1);
p = c(k == 1);
end

function out = interleave(in, ncbps, nbpsc)
% Eq. (15)-(17)
s = max(nbpsc / 2, 1);
k = (0:ncbps-1).';
i = (ncbps/16) * mod(k, 16) + floor(k / 16);
j = s * floor(i / s) + mod(i + ncbps - floor(16 * i / ncbps), s);
out = zeros(ncbps, 1);
out(j + 1) = in(k + 1);
end

function d = map_bits(b, nbpsc)
% 17.3.5.7, Tables 81-84 (Gray coded), K_MOD of Table 81
b = reshape(double(b), nbpsc, []).';
switch nbpsc
    case 1
        d = (2 * b(:, 1) - 1);
    case 2
        d = ((2 * b(:, 1) - 1) + 1j * (2 * b(:, 2) - 1)) / sqrt(2);
    case 4
        d = (pam2(b(:, 1:2)) + 1j * pam2(b(:, 3:4))) / sqrt(10);
    case 6
        d = (pam3(b(:, 1:3)) + 1j * pam3(b(:, 4:6))) / sqrt(42);
end
d = complex(d(:));
end

function v = pam2(b)
lut = [-3 -1 3 1];                       % b0b1 = 00 01 10 11 (Table 83)
v = lut(b(:, 1) * 2 + b(:, 2) + 1);
v = v(:);
end

function v = pam3(b)
lut = [-7 -5 -1 -3 7 5 1 3];             % b0b1b2 = 000..111 (Table 84)
v = lut(b(:, 1) * 4 + b(:, 2) * 2 + b(:, 3) + 1);
v = v(:);
end

function k = data_subcarriers()
k = [-26:-22, -20:-8, -6:-1, 1:6, 8:20, 22:26].';
end

function p = preamble()
% 17.3.3: L-STF (Eq. 6) 10 x 16 samples, L-LTF (Eq. 8) GI2 + 2 x 64 samples
S = zeros(64, 1);
ks = [-24 -20 -16 -12 -8 -4 4 8 12 16 20 24];
vs = [1+1j -1-1j 1+1j -1-1j -1-1j 1+1j -1-1j -1-1j 1+1j 1+1j 1+1j 1+1j];
S(mod(ks, 64) + 1) = sqrt(13/6) * vs;
Lv = [1 1 -1 -1 1 1 -1 1 -1 1 1 1 1 1 1 -1 -1 1 1 -1 1 -1 1 1 1 1 0 ...
      1 -1 -1 1 1 -1 1 -1 1 -1 -1 -1 -1 -1 1 1 -1 -1 1 -1 1 -1 1 1 1 1];
LF = zeros(64, 1);
LF(mod(-26:26, 64) + 1) = Lv;
s = ifft(S);
l = ifft(LF);
p = [repmat(s(1:16), 10, 1); l(33:64); l; l];
end

% =========================================================================
%  WLAN TOOLBOX MODEL
% =========================================================================
function ok = toolbox_available()
persistent av;
if isempty(av)
    av = false;
    try
        av = exist('wlanWaveformGenerator', 'file') > 0 && exist('wlanNonHTConfig', 'file') > 0;
    catch
        av = false;
    end
end
ok = av;
end

function tb = toolbox_tx(psdu, rate_mbps, seed, nsym)
mcs = find([6 9 12 18 24 36 48 54] == rate_mbps) - 1;
cfg = wlanNonHTConfig('ChannelBandwidth', 'CBW20', 'Modulation', 'OFDM', ...
                      'MCS', mcs, 'PSDULength', numel(psdu));
bits = bytes_to_bits(psdu);
y = wlanWaveformGenerator(bits, cfg, 'NumPackets', 1, 'IdleTime', 0, ...
        'ScramblerInitialization', toolbox_seed(seed), 'WindowTransitionTime', 0);
% wlanWaveformGenerator normalizes the 20 MHz non-HT waveform to unit average
% power over the 52 occupied tones: y = ifft(X) * 64 / sqrt(52).
% Back to the Annex G / RTL scaling:
tb.wave = double(y(:)) * sqrt(52) / 64;
if numel(tb.wave) ~= 320 + 80 * (nsym + 1)
    error('tx_golden_reference:toolbox', 'Toolbox waveform length %d unexpected.', numel(tb.wave));
end
dsc = mod(data_subcarriers(), 64) + 1;
tb.map = zeros(48, nsym + 1);
for n = 0:nsym
    seg = tb.wave(320 + 80*n + (17:80));
    X = fft(seg);
    tb.map(:, n+1) = X(dsc);
end
end

function s = toolbox_seed(seed)
% Detected once by run_selftest; default = same convention (bit 6 = x7).
s = seed;
if seed_convention() == 2
    s = bin_reverse7(seed);
end
end

function v = seed_convention(set_value)
persistent c;
if nargin > 0
    c = set_value;
end
if isempty(c)
    c = 1;
end
v = c;
end

function r = bin_reverse7(s)
b = mod(floor(s ./ 2.^(0:6)), 2);
r = sum(fliplr(b) .* 2.^(0:6));
end

function warn_once(msg)
persistent done;
if isempty(done)
    done = true;
    fprintf(2, 'WARNING: %s\n', msg);
end
end

% =========================================================================
%  SELF-TEST
% =========================================================================
function rep = run_selftest()
fprintf('---- tx_golden_reference self-test ----\n');
rep.pass = true;
rep.items = cell(0, 3);

% 1) scrambler sequence, 17.3.5.4 (all-ones initial state)
exp127 = ['00001110' '11110010' '11001001' '00000010' '00100110' '00101110' '10110110' ...
          '00001100' '11010100' '11100111' '10110100' '00101010' '11111010' '01010001' ...
          '10111000' '1111111'];
got = char('0' + scrambler_seq(ones(1, 7), 127).');
rep = add_item(rep, 'Scrambler 127-bit sequence (17.3.5.4)', isequal(got, exp127), '');

% 2) pilot polarity p_0..p_7 of Table G.23 / Eq. (25) start: 1 1 1 1 -1 -1 -1 1
p = 1 - 2 * scrambler_seq(ones(1, 7), 8);
rep = add_item(rep, 'Pilot polarity p0..p7 (Eq. 25)', isequal(p(:).', [1 1 1 1 -1 -1 -1 1]), '');

% 3) Annex G complete packet, Table G.24 (36 Mb/s, 100 octets, seed 1011101)
A = annexg_reference();
g = independent_tx(A.psdu, A.rate, A.seed);
idx = setdiff(0:880, A.windowed_idx) + 1;
e = max(abs(g.wave(idx) - A.g24(idx)));
ok = numel(g.wave) == 880 && e <= 7.2e-4;     % table printed with 3 decimals: |err| <= 0.0005*sqrt(2)
rep = add_item(rep, 'Annex G Table G.24 whole packet (874 non-windowed samples)', ok, ...
    sprintf('max |err| = %.2e (3-decimal table, limit 7.2e-4)', e));
% SIGNAL bits of Table G.7
expG7 = [1 0 1 1 0 0 0 1 0 0 1 1 0 0 0 0 0 0 0 0 0 0 0 0].';
rep = add_item(rep, 'Annex G Table G.7 SIGNAL bits', isequal(g.signal_bits, expG7), '');

% 4) Communications Toolbox convolutional encoder / puncturing cross-check
if exist('convenc', 'file') > 0 && exist('poly2trellis', 'file') > 0
    try
        b = double(scrambler_seq(seed_to_x(37), 600));
        t = poly2trellis(7, [133 171]);
        c1 = convenc(b, t);
        c34 = convenc(b, t, [1 1 1 0 0 1]);
        c23 = convenc(b, t, [1 1 1 0]);
        ok = isequal(c1(:), conv_encode(b)) && isequal(c34(:), puncture(conv_encode(b), 3/4)) && ...
             isequal(c23(:), puncture(conv_encode(b), 2/3));
        rep = add_item(rep, 'Comms Toolbox convenc/puncpat vs Clause-17 encoder', ok, '');
    catch err
        rep = add_item(rep, 'Comms Toolbox convenc cross-check', false, err.message);
    end
else
    rep = add_skip(rep, 'Comms Toolbox convenc cross-check', 'Communications Toolbox not found');
end

% 5) WLAN Toolbox cross-check, all rates, several lengths and seeds
if toolbox_available()
    % seed bit-order convention of ScramblerInitialization (seed 1 is not a palindrome)
    q = independent_tx((0:30).', 24, 1);
    seed_convention(1);  t1 = toolbox_tx((0:30).', 24, 1, q.nsym);
    seed_convention(2);  t2 = toolbox_tx((0:30).', 24, 1, q.nsym);
    d1 = max(abs(t1.wave - q.wave)); d2 = max(abs(t2.wave - q.wave));
    if d1 < 1e-9
        seed_convention(1); conv_txt = 'ScramblerInitialization bit 6 = x7 (same as pkt_list)';
    elseif d2 < 1e-9
        seed_convention(2); conv_txt = 'ScramblerInitialization bit-reversed w.r.t. pkt_list';
    else
        seed_convention(1); conv_txt = sprintf('NO convention matches (%.2e / %.2e)', d1, d2);
    end
    rep = add_item(rep, 'WLAN Toolbox scrambler-seed convention', d1 < 1e-9 || d2 < 1e-9, conv_txt);
    worst = 0; nchk = 0; ok = true;
    for rr = [6 9 12 18 24 36 48 54]
        for L = [1 37 100 255]
            for sd = [1 64 93 127]
                bytes = mod((0:L-1).' * 37 + sd, 256);
                q = independent_tx(bytes, rr, sd);
                t = toolbox_tx(bytes, rr, sd, q.nsym);
                d = max([abs(t.wave - q.wave); abs(t.map(:) - q.map(:))]);
                worst = max(worst, d); nchk = nchk + 1;
                ok = ok && d < 1e-9;
            end
        end
    end
    rep = add_item(rep, 'WLAN Toolbox waveform == Clause-17 model (8 rates x 4 lengths x 4 seeds)', ok, ...
        sprintf('%d packets, max |diff| = %.2e (limit 1e-9)', nchk, worst));
    % Annex G through the toolbox as well
    t = toolbox_tx(A.psdu, A.rate, A.seed, 6);
    e = max(abs(t.wave(idx) - A.g24(idx)));
    rep = add_item(rep, 'WLAN Toolbox vs Annex G Table G.24', e <= 7.2e-4, sprintf('max |err| = %.2e', e));
else
    rep = add_skip(rep, 'WLAN Toolbox cross-check', 'WLAN Toolbox not found (NOT RUN)');
end

fprintf('---- self-test %s ----\n', ternary(rep.pass, 'PASSED', 'FAILED'));
end

function rep = add_item(rep, name, ok, info)
rep.items(end+1, :) = {name, ternary(ok, 'PASS', 'FAIL'), info};
rep.pass = rep.pass && ok;
fprintf('  [%s] %s %s\n', ternary(ok, 'PASS', 'FAIL'), name, info);
end

function rep = add_skip(rep, name, info)
rep.items(end+1, :) = {name, 'NOT RUN', info};
fprintf('  [NOT RUN] %s (%s)\n', name, info);
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end
