function cases = generate_test_cases(regression)
%GENERATE_TEST_CASES  Packet scenarios for tb_tx_top.sv (one pkt_list.txt entry each).
%
%   cases = generate_test_cases('smoke')     ~16 short entries, first debug run
%   cases = generate_test_cases('extended')  ~110 entries, wide coverage
%   cases = generate_test_cases('stress')    maximum LENGTH (4095) at every rate
%
%   MODE / PARAM semantics are those implemented in tb_tx_top.sv run_entry():
%     MODE 0  normal packet                         PARAM unused (0)
%     MODE 1  abort: PHY-TXEND.request sent PARAM r_clk cycles after
%             PHY-TXSTART.confirm. The TB decides at run time whether the
%             abort was early (nothing on air), mid (truncated at a symbol
%             boundary) or late (last symbol committed -> complete packet).
%     MODE 2  invalid RATE: the TB forces RATE code 4'b0000 in TXVECTOR
%             (the RATE column is only used for the vector files / display)
%     MODE 3  r_rstn and w_rstn asserted PARAM r_clk cycles after
%             PHY-TXSTART.confirm (not checked), then normal packets again
%   The TB executes the entries in order and keeps DUT state between them,
%   so every abort / bad-RATE / reset entry is followed by normal packets that
%   check recovery.  Entry 0 is always a normal packet.
%
%   Payloads are reproducible: a Park-Miller generator (exact in double
%   precision, identical in every MATLAB version) is used, not rand().
%
%   Each case has fields: rate len mode param pattern note psdu

if nargin < 1, regression = 'smoke'; end
C = {};
switch lower(regression)
    case 'smoke'
        C = smoke_list();
    case 'extended'
        C = extended_list();
    case 'stress'
        C = stress_list();
    otherwise
        error('generate_test_cases:arg', 'Regression must be smoke, extended or stress.');
end

cases = repmat(struct('rate', 0, 'len', 0, 'mode', 0, 'param', 0, 'pattern', '', ...
                      'note', '', 'psdu', []), numel(C), 1);
for i = 1:numel(C)
    c = C{i};
    cases(i).rate = c{1};
    cases(i).len = c{2};
    cases(i).mode = c{3};
    cases(i).param = c{4};
    cases(i).pattern = c{5};
    cases(i).note = c{6};
    cases(i).psdu = make_payload(c{5}, c{2}, 1000 + i);
end
check_cases(cases);
end

% -------------------------------------------------------------------------
function C = smoke_list()
C = {};
C{end+1} = {6,   1,   0, 0, 'random', 'min LENGTH, 6 Mb/s (NSYM=2)'};
C{end+1} = {54,  1,   0, 0, 'ones',   'min LENGTH, 54 Mb/s (NSYM=1)'};
C{end+1} = {9,   50,  0, 0, 'zeros',  'all-zero payload'};
C{end+1} = {12,  64,  0, 0, 'alt55',  'alternating 01010101'};
C{end+1} = {18,  100, 0, 0, 'random', 'typical'};
C{end+1} = {24,  100, 0, 0, 'ones',   'all-one payload'};
C{end+1} = {36,  100, 0, 0, 'annexg', 'Annex G Table G.1 payload'};
C{end+1} = {48,  200, 0, 0, 'altAA',  'alternating 10101010'};
C{end+1} = {54,  300, 0, 0, 'random', 'typical'};
C{end+1} = {6,   20,  2, 0, 'random', 'invalid RATE 0000'};
C{end+1} = {12,  40,  0, 0, 'random', 'recovery after invalid RATE'};
C{end+1} = {24,  300, 1, 0, 'random', 'abort 0 clk after TXSTART.confirm (early)'};
C{end+1} = {6,   30,  0, 0, 'random', 'recovery after abort'};
C{end+1} = {36,  600, 1, p_mid(36, 600), 'random', 'abort in mid packet'};
C{end+1} = {9,   33,  0, 0, 'alt55',  'recovery after abort'};
C{end+1} = {18,  400, 3, p_mid(18, 400), 'random', 'reset in mid packet'};
C{end+1} = {54,  100, 0, 0, 'incr',   'recovery after reset'};
end

% -------------------------------------------------------------------------
function C = extended_list()
C = {};
rates = [6 9 12 18 24 36 48 54];
pats  = {'random', 'zeros', 'ones', 'alt55', 'altAA', 'incr', 'random'};
% A) every rate x {1, 2, exact-fit length (NPAD minimum), exact-fit+1 (new symbol),
%    255, 1000, 2047}; the payload pattern rotates so every rate sees every pattern
for ri = 1:numel(rates)
    r = rates(ri);
    [lfit, lnext] = boundary_lengths(r);
    Ls = [1 2 lfit lnext 255 1000 2047];
    for li = 1:numel(Ls)
        p = pats{mod(ri + li - 2, numel(pats)) + 1};
        C{end+1} = {r, Ls(li), 0, 0, p, sprintf('rate sweep, NPAD=%d', npad(r, Ls(li)))}; %#ok<AGROW>
    end
end
% B) Annex G payload at every rate
for r = rates
    C{end+1} = {r, 100, 0, 0, 'annexg', 'Annex G Table G.1 payload'}; %#ok<AGROW>
end
% C) invalid RATE, each followed by a normal packet
C{end+1} = {6,   1,   2, 0, 'random', 'invalid RATE, LENGTH 1'};
C{end+1} = {54,  64,  0, 0, 'random', 'recovery after invalid RATE'};
C{end+1} = {24,  300, 2, 0, 'random', 'invalid RATE, LENGTH 300'};
C{end+1} = {9,   77,  0, 0, 'random', 'recovery after invalid RATE'};
% D) aborts (early / during preamble / mid / single-symbol packet / late), each + recovery
C{end+1} = {6,   100, 1, 0,   'random', 'abort 0 clk after TXSTART.confirm'};
C{end+1} = {12,  50,  0, 0,   'random', 'recovery after abort'};
C{end+1} = {54,  500, 1, 30,  'random', 'abort 30 clk after TXSTART.confirm'};
C{end+1} = {18,  120, 0, 0,   'ones',   'recovery after abort'};
C{end+1} = {12,  300, 1, 600, 'random', 'abort during the preamble'};
C{end+1} = {24,  99,  0, 0,   'random', 'recovery after abort'};
C{end+1} = {36, 1000, 1, p_mid(36, 1000), 'random', 'abort in mid packet'};
C{end+1} = {48,  10,  0, 0,   'zeros',  'recovery after abort'};
C{end+1} = {54,  1,   1, p_mid(54, 1)-640, 'random', 'abort, single-DATA-symbol packet'};
C{end+1} = {6,   12,  0, 0,   'random', 'recovery after abort'};
C{end+1} = {24,  800, 1, p_late(24, 800)-640, 'random', 'late abort (last symbol committed)'};
C{end+1} = {36,  200, 0, 0,   'random', 'recovery after late abort'};
C{end+1} = {48, 1500, 1, p_late(48, 1500)-640, 'random', 'late abort (last symbol committed)'};
C{end+1} = {9,   40,  0, 0,   'random', 'recovery after late abort'};
% E) resets, each + recovery
C{end+1} = {12,  200, 3, 0,   'random', 'reset 0 clk after TXSTART.confirm'};
C{end+1} = {24,  60,  0, 0,   'random', 'recovery after reset'};
C{end+1} = {54,  700, 3, 500, 'random', 'reset during the preamble'};
C{end+1} = {6,   25,  0, 0,   'random', 'recovery after reset'};
C{end+1} = {9,   500, 3, p_mid(9, 500), 'random', 'reset in mid packet'};
C{end+1} = {48,  333, 0, 0,   'random', 'recovery after reset'};
C{end+1} = {18,  90,  0, 0,   'altAA',  'second packet after reset'};
% F) back-to-back packets of the same rate (encoder clear, pilot restart, framer)
C{end+1} = {54, 1500, 0, 0, 'random', 'back-to-back 54 Mb/s'};
C{end+1} = {54,    7, 0, 0, 'random', 'back-to-back 54 Mb/s'};
C{end+1} = {54,  333, 0, 0, 'random', 'back-to-back 54 Mb/s'};
C{end+1} = {6,     3, 0, 0, 'random', 'back-to-back 6 Mb/s'};
C{end+1} = {6,     4, 0, 0, 'random', 'back-to-back 6 Mb/s'};
C{end+1} = {6,     5, 0, 0, 'random', 'back-to-back 6 Mb/s'};
% G) 24 reproducible random packets (rate, length log-uniform 1..1500, payload)
st = 20261119;
for k = 1:24
    [u, st] = pm_rand(st, 2);
    r = rates(floor(u(1) * 8) + 1);
    L = max(1, min(1500, round(exp(u(2) * log(1500)))));
    C{end+1} = {r, L, 0, 0, 'random', 'randomized'}; %#ok<AGROW>
end
end

% -------------------------------------------------------------------------
function C = stress_list()
C = {};
rates = [6 9 12 18 24 36 48 54];
pats  = {'random', 'zeros', 'ones', 'alt55', 'altAA', 'incr', 'random', 'random'};
for ri = 1:numel(rates)
    C{end+1} = {rates(ri), 4095, 0, 0, pats{ri}, 'max LENGTH 4095'}; %#ok<AGROW>
end
C{end+1} = {54, 4094, 0, 0, 'random', 'LENGTH 4094'};
C{end+1} = {54, 4095, 1, p_late(54, 4095)-640, 'random', 'late abort of a max-length packet'};
C{end+1} = {24,  500, 0, 0, 'random', 'recovery after late abort'};
C{end+1} = {6,  4095, 3, p_mid(6, 4095), 'random', 'reset in mid max-length packet'};
C{end+1} = {12, 4095, 0, 0, 'random', 'max LENGTH after reset'};
end

% -------------------------------------------------------------------------
function n = nsym_of(r, L)
nd = [24 36 48 72 96 144 192 216];
ndb = nd([6 9 12 18 24 36 48 54] == r);
n = ceil((16 + 8 * L + 6) / ndb);
end

function p = npad(r, L)
nd = [24 36 48 72 96 144 192 216];
ndb = nd([6 9 12 18 24 36 48 54] == r);
p = nsym_of(r, L) * ndb - (16 + 8 * L + 6);
end

function [lfit, lnext] = boundary_lengths(r)
% smallest LENGTH >= 3 with the minimum possible pad, and the next LENGTH
% (one more octet -> one more OFDM symbol, maximum pad)
cand = 3:400;
pads = arrayfun(@(L) npad(r, L), cand);
lfit = cand(find(pads == min(pads), 1));
lnext = lfit + 1;
end

function p = p_mid(r, L)
% half of the packet on air (r_clk): preamble 1280 + 320 per OFDM symbol
p = 1280 + 320 * floor(nsym_of(r, L) / 2) + 160;
end

function p = p_late(r, L)
% inside the last-but-one symbol on air: the last symbol has already been
% committed by the bit-processing chain -> the TB expects the complete packet
p = 4 * (320 + 80 * nsym_of(r, L)) - 160;
end

% -------------------------------------------------------------------------
function b = make_payload(pattern, L, s0)
switch pattern
    case 'random'
        [u, ~] = pm_rand(s0 * 7919 + L, L);
        b = floor(u * 256);
    case 'zeros',  b = zeros(L, 1);
    case 'ones',   b = 255 * ones(L, 1);
    case 'alt55',  b = 85 * ones(L, 1);
    case 'altAA',  b = 170 * ones(L, 1);
    case 'incr',   b = mod((0:L-1).', 256);
    case 'annexg'
        A = annexg_reference();
        b = A.psdu(mod(0:L-1, numel(A.psdu)) + 1);
    otherwise
        error('generate_test_cases:pattern', 'Unknown pattern %s.', pattern);
end
b = b(:);
end

function [u, s] = pm_rand(s, n)
% Park-Miller minimal standard generator, x <- 16807 x mod (2^31 - 1)
m = 2147483647;
s = mod(s, m);
if s == 0, s = 1; end
u = zeros(n, 1);
for k = 1:n
    s = mod(16807 * s, m);
    u(k) = s / m;
end
end

function check_cases(cases)
if cases(1).mode ~= 0
    error('generate_test_cases:order', 'Entry 0 must be a normal packet.');
end
for i = 1:numel(cases)
    c = cases(i);
    if ~any(c.rate == [6 9 12 18 24 36 48 54]) || c.len < 1 || c.len > 4095 || ...
            ~any(c.mode == 0:3) || c.param < 0 || numel(c.psdu) ~= c.len
        error('generate_test_cases:case', 'Entry %d is not valid.', i - 1);
    end
    n = nsym_of(c.rate, c.len);
    if 48 * (n + 1) > 70000 || 320 + 80 * (n + 1) > 120000
        error('generate_test_cases:size', 'Entry %d exceeds the TB arrays.', i - 1);
    end
    if c.mode ~= 0 && i < numel(cases) && cases(i+1).mode ~= 0
        error('generate_test_cases:order', 'Entry %d (mode %d) must be followed by a normal packet.', i - 1, c.mode);
    end
end
end
