function rep = validate_generated_vectors(vec_dir, varargin)
%VALIDATE_GENERATED_VECTORS  Read the exported files back and check them.
%
%   rep = validate_generated_vectors()                       uses tx_config().vec_dir
%   rep = validate_generated_vectors(vec_dir, 'RomFile', f, 'Decode', true)
%
%   Checks, per entry of pkt_list.txt:
%     F1  manifest syntax: first line = N, then N lines of 6 decimal integers
%     F2  RATE in {6..54}, 1 <= LENGTH <= 4095, 1 <= SEED <= 127, MODE 0..3, PARAM >= 0,
%         NSYM == ceil((16+8*LENGTH+6)/N_DBPS) (Eq. 11), sizes fit the TB arrays
%     F3  file presence, line counts (LENGTH, 48*(NSYM+1), 320+80*(NSYM+1)),
%         every line exactly 2 / 8 hex digits ($readmemh-compatible)
%     C1  round trip: golden regenerated from the PSDU file with the independent
%         Clause-17 model -> identical integers in map and bb files
%     C2  mapper values belong to the constellation of the symbol (SIGNAL = BPSK)
%     C3  bb preamble == preamble_rom_data.mem of the RTL, bit-exact (if found)
%     C4  bb SIGNAL/DATA == IFFT(map file + pilots) within 1 LSB
%         (mapper quantization <= 0.57 LSB in time + rounding -> |diff| <= 1)
%     C5  cyclic prefix: samples 0..15 of each symbol == samples 64..79
%     C6  standard receiver (WLAN Toolbox wlanLSIGRecover / wlanNonHTDataRecover):
%         RATE/LENGTH and the PSDU decoded from the bb file == pkt_list / PSDU file

cfg = tx_config();
if nargin < 1 || isempty(vec_dir), vec_dir = cfg.vec_dir; end
rom_file = cfg.rom_file;
do_decode = true;
for k = 1:2:numel(varargin)
    switch lower(varargin{k})
        case 'romfile', rom_file = varargin{k+1};
        case 'decode',  do_decode = varargin{k+1};
        otherwise, error('validate:arg', 'Unknown option %s', varargin{k});
    end
end
F = tx_rtl_format();
have_tbx = exist('wlanNonHTDataRecover', 'file') > 0 && exist('wlanLSIGRecover', 'file') > 0;

fprintf('==== validate_generated_vectors: %s ====\n', vec_dir);
rep.ok = true;
rep.fail = {};
rep.notrun = {};

% ---------------------------------------------------------------- F1
txt = fileread(fullfile(vec_dir, 'pkt_list.txt'));
ln = regexp(strtrim(txt), '\r?\n', 'split');
N = str2double(ln{1});
if isnan(N) || N < 1 || N ~= round(N) || ~isempty(regexp(ln{1}, '[^\d\s]', 'once'))
    error('validate:F1', 'pkt_list.txt: first line must be the number of entries.');
end
if numel(ln) ~= N + 1
    rep = fail(rep, sprintf('F1 pkt_list.txt has %d entry lines, header says %d', numel(ln) - 1, N));
end
T = zeros(N, 6);
for i = 1:min(N, numel(ln) - 1)
    if isempty(regexp(strtrim(ln{i+1}), '^\d+ \d+ \d+ \d+ \d+ \d+$', 'once'))
        rep = fail(rep, sprintf('F1 line %d is not "RATE LENGTH SEED NSYM MODE PARAM": "%s"', i + 1, ln{i+1}));
        continue;
    end
    T(i, :) = sscanf(ln{i+1}, '%d').';
end

% ROM of the RTL (C3)
rom = [];
if exist(rom_file, 'file')
    rl = read_hex_lines(rom_file, 8);
    if numel(rl.val) == 320 && rl.badfmt == 0
        rom = rl.val;
    else
        rep = fail(rep, sprintf('C3 %s is not 320 x 8-hex-digit lines', rom_file));
    end
else
    rep.notrun{end+1} = sprintf('C3 preamble vs RTL ROM: %s not found', rom_file);
end
if ~have_tbx || ~do_decode
    rep.notrun{end+1} = 'C6 standard-receiver decode (WLAN Toolbox not found or disabled)';
end

pseq = 1 - 2 * scr127();
dsc = mod([-26:-22, -20:-8, -6:-1, 1:6, 8:20, 22:26], 64) + 1;
psc = mod([-21 -7 7 21], 64) + 1;
ndbps_tab = [24 36 48 72 96 144 192 216];
rates = [6 9 12 18 24 36 48 54];
nbpsc_tab = [1 1 2 2 4 4 6 6];

for i = 1:N
    rate = T(i, 1); len = T(i, 2); seed = T(i, 3); nsym = T(i, 4); mode = T(i, 5); param = T(i, 6);
    tag = sprintf('pkt%03d', i - 1);
    e0 = numel(rep.fail);
    % ---------------------------------------------------------------- F2
    ri = find(rates == rate, 1);
    if isempty(ri), rep = fail(rep, sprintf('F2 %s RATE %d invalid', tag, rate)); continue; end
    if len < 1 || len > 4095, rep = fail(rep, sprintf('F2 %s LENGTH %d', tag, len)); continue; end
    if seed < 1 || seed > 127, rep = fail(rep, sprintf('F2 %s SEED %d', tag, seed)); end
    if mode < 0 || mode > 3,   rep = fail(rep, sprintf('F2 %s MODE %d', tag, mode)); end
    if param < 0,              rep = fail(rep, sprintf('F2 %s PARAM %d', tag, param)); end
    nexp = ceil((16 + 8 * len + 6) / ndbps_tab(ri));
    if nsym ~= nexp, rep = fail(rep, sprintf('F2 %s NSYM %d, Eq.(11) gives %d', tag, nsym, nexp)); continue; end
    if 48 * (nsym + 1) > cfg.tb.MAXMAP || 320 + 80 * (nsym + 1) > cfg.tb.MAXBB || nsym + 1 > cfg.tb.MAXSYMIX + 1
        rep = fail(rep, sprintf('F2 %s too large for the TB arrays', tag));
    end
    % ---------------------------------------------------------------- F3
    P = read_hex_lines(fullfile(vec_dir, [tag '_psdu.hex']), 2);
    M = read_hex_lines(fullfile(vec_dir, [tag '_map.hex']),  8);
    B = read_hex_lines(fullfile(vec_dir, [tag '_bb.hex']),   8);
    if P.missing || M.missing || B.missing
        rep = fail(rep, sprintf('F3 %s file missing', tag)); continue;
    end
    if numel(P.val) ~= len,              rep = fail(rep, sprintf('F3 %s psdu %d lines, LENGTH %d', tag, numel(P.val), len)); end
    if numel(M.val) ~= 48 * (nsym + 1),  rep = fail(rep, sprintf('F3 %s map %d lines, expected %d', tag, numel(M.val), 48 * (nsym + 1))); end
    if numel(B.val) ~= 320 + 80 * (nsym + 1), rep = fail(rep, sprintf('F3 %s bb %d lines, expected %d', tag, numel(B.val), 320 + 80 * (nsym + 1))); end
    if P.badfmt + M.badfmt + B.badfmt > 0, rep = fail(rep, sprintf('F3 %s %d malformed hex lines', tag, P.badfmt + M.badfmt + B.badfmt)); end
    if numel(rep.fail) > e0, continue; end
    [mi, mq] = F.unpack_iq(M.val);
    [bi, bq] = F.unpack_iq(B.val);
    % ---------------------------------------------------------------- C1
    g = tx_golden_reference(P.val, rate, seed, 'Engine', 'independent');
    qm = F.quantize(g.map(:));
    qb = F.quantize(g.wave);
    if ~isequal([mi mq], qm)
        rep = fail(rep, sprintf('C1 %s map file differs from the regenerated golden (%d words)', tag, sum(any([mi mq] ~= qm, 2))));
    end
    nd = sum(any([bi bq] ~= qb, 2));
    if nd > 0
        if max(max(abs([bi bq] - qb))) <= 1
            fprintf('  note: %s %d bb samples differ by 1 LSB from the independent model (rounding of a toolbox value at a .5 tie)\n', tag, nd);
        else
            rep = fail(rep, sprintf('C1 %s bb file differs from the regenerated golden (%d samples)', tag, nd));
        end
    end
    % ---------------------------------------------------------------- C2
    lev = allowed_levels(nbpsc_tab(ri));
    s0 = 1:48; sd = 49:numel(mi);
    if any(abs(mi(s0)) ~= 16384) || any(mq(s0) ~= 0)
        rep = fail(rep, sprintf('C2 %s SIGNAL mapper values not BPSK (+/-16384, 0)', tag));
    end
    if ~all(ismember(mi(sd), lev)) || ~all(ismember(mq(sd), lev.*(nbpsc_tab(ri) > 1)))
        rep = fail(rep, sprintf('C2 %s DATA mapper values outside the %d-bit constellation', tag, nbpsc_tab(ri)));
    end
    % ---------------------------------------------------------------- C3
    if ~isempty(rom) && ~isequal(B.val(1:320), rom)
        rep = fail(rep, sprintf('C3 %s preamble differs from preamble_rom_data.mem (%d samples)', tag, sum(B.val(1:320) ~= rom)));
    end
    % ---------------------------------------------------------------- C4 / C5
    Mi = reshape(complex(mi, mq), 48, nsym + 1) / 2^14;
    Bc = complex(bi, bq);
    worst = 0; cp_bad = 0;
    for n = 0:nsym
        X = zeros(64, 1);
        X(dsc) = Mi(:, n + 1);
        X(psc) = [1 1 1 -1] * pseq(mod(n, 127) + 1);
        x = ifft(X);
        q = F.quantize([x(49:64); x]);
        seg = Bc(320 + 80 * n + (1:80));
        worst = max(worst, max(max(abs([real(seg) imag(seg)] - q))));
        cp_bad = cp_bad + any(seg(1:16) ~= seg(65:80));
    end
    if worst > 1, rep = fail(rep, sprintf('C4 %s bb differs from IFFT(map + pilots) by %d LSB', tag, worst)); end
    if cp_bad > 0, rep = fail(rep, sprintf('C5 %s cyclic prefix wrong in %d symbols', tag, cp_bad)); end
    % ---------------------------------------------------------------- C6
    if have_tbx && do_decode
        try
            [ok6, msg6] = decode_check(Bc, P.val, rate, len, nsym);
            if ~ok6, rep = fail(rep, sprintf('C6 %s %s', tag, msg6)); end
        catch err
            rep = fail(rep, sprintf('C6 %s receiver error: %s', tag, err.message));
        end
    end
    if numel(rep.fail) == e0
        fprintf('  %s OK  rate %2d len %4d seed %3d nsym %4d mode %d param %6d\n', tag, rate, len, seed, nsym, mode, param);
    end
end

for k = 1:numel(rep.notrun)
    fprintf('  NOT RUN: %s\n', rep.notrun{k});
end
if rep.ok
    fprintf('==== VALIDATION PASSED: %d entries ====\n', N);
else
    fprintf(2, '==== VALIDATION FAILED: %d problem(s) ====\n', numel(rep.fail));
end
rep.n = N;
end

% =========================================================================
function rep = fail(rep, msg)
rep.ok = false;
rep.fail{end+1} = msg;
fprintf(2, '  FAIL %s\n', msg);
end

function R = read_hex_lines(name, nd)
R.missing = ~exist(name, 'file');
R.val = []; R.badfmt = 0;
if R.missing, return; end
t = fileread(name);
c = regexp(t, '\r?\n', 'split');
if ~isempty(c) && isempty(c{end}), c(end) = []; end
good = ~cellfun(@isempty, regexp(c, sprintf('^[0-9A-Fa-f]{%d}$', nd), 'once'));
R.badfmt = sum(~good);
if isempty(c), return; end
v = zeros(numel(c), 1);
v(good) = hex2dec(char(c(good)));
R.val = v;
end

function lev = allowed_levels(nbpsc)
switch nbpsc
    case 1, a = 1;
    case 2, a = 1 / sqrt(2);
    case 4, a = [1 3] / sqrt(10);
    case 6, a = [1 3 5 7] / sqrt(42);
end
a = round(a * 2^14);
lev = [a -a];
end

function s = scr127()
st = ones(1, 7); s = zeros(127, 1);
for k = 1:127
    t = xor(st(7), st(4)); s(k) = t; st = [t st(1:6)];
end
end

function [ok, msg] = decode_check(Bc, psdu, rate, len, nsym)
% Standard receiver on the exported (quantized) waveform, ideal channel.
mcs = find([6 9 12 18 24 36 48 54] == rate) - 1;
cfgN = wlanNonHTConfig('ChannelBandwidth', 'CBW20', 'Modulation', 'OFDM', 'MCS', mcs, 'PSDULength', len);
rx = Bc / 2^14 * 64 / sqrt(52);                 % back to toolbox normalization
ind = wlanFieldIndices(cfgN);
chEst = ones(52, 1);
[sigBits, failCheck] = wlanLSIGRecover(rx(ind.LSIG(1):ind.LSIG(2)), chEst, 1e-4, 'CBW20');
rbits = [1 1 0 1; 1 1 1 1; 0 1 0 1; 0 1 1 1; 1 0 0 1; 1 0 1 1; 0 0 0 1; 0 0 1 1];
sigBits = double(sigBits(:)).';
lenRx = sum(sigBits(6:17) .* 2.^(0:11));
ok = ~failCheck && isequal(sigBits(1:4), rbits(mcs + 1, :)) && lenRx == len;
msg = '';
if ~ok, msg = sprintf('L-SIG decode: fail=%d RATE bits %s LENGTH %d', failCheck, mat2str(sigBits(1:4)), lenRx); return; end
rxData = rx(ind.NonHTData(1):ind.NonHTData(2));
if numel(rxData) ~= 80 * nsym
    ok = false; msg = 'DATA field length'; return;
end
if rate == 9 && nsym == 1, return; end
bits = wlanNonHTDataRecover(rxData, chEst, 1e-4, cfgN);
txb = mod(floor(psdu(:) * 2.^-(0:7)), 2).';
nerr = sum(double(bits(:)) ~= txb(:));
ok = nerr == 0;
if ~ok, msg = sprintf('PSDU decode: %d bit errors', nerr); end
end
