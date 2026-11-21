function F = tx_rtl_format()
%TX_RTL_FORMAT  RTL-specific number formats and interface conventions.
%
%   F = tx_rtl_format() returns constants and function handles.  Everything in
%   here is an IMPLEMENTATION convention of the RTL / testbench (not something
%   the standard defines).  Each item names the RTL source it was read from.
%   The standard-defined signal itself is produced by tx_golden_reference.m.
%
%   Fixed-point format (mapper output, pilots, IFFT/CP output, preamble ROM):
%     signed 16 bit, Q2.14, 1.0 = 16384
%       amplitude_lut.v       : "Q2.(W-2) (1.0 = 2^(W-2))", BPSK 1.0 = 16384
%       Pilot_Insertion.v     : P_P = 16'h4000 (+1 in Q2.14)
%       generate_preamble.py  : FRACTIONAL_BITS = 14, np.fft.ifft (1/64 scaling)
%       FFT64_Top.v           : "/2 in every butterfly ... IFFT output = IDFT (includes 1/64)"
%     => time-domain RTL value = round( 2^14 * (1/64) * sum_k X_k exp(+j2*pi*k*n/64) )
%        with X_k the normalized constellation (K_MOD applied) and pilots = +/-1.
%        This is exactly the scaling of the time-domain tables of Annex G.
%
%   32-bit word packing  {I[15:0], Q[15:0]}  (I in bits 31:16)
%       symbol_output.v       : complex_symbol_out <= {I, Q}
%       FFT64_OFDM_Tx_Top.v   : I = data[31:16], Q = data[15:0]
%       tb_tx_top.sv          : hi16() = I, lo16() = Q for exp_bb
%   NOTE: the header comments of mapper_top.v / symbol_output.v / top_wrapper
%   say "{Q, I}" but the code is {I, Q}.  The code is authoritative; the
%   comments are wrong (documentation issue only).
%
%   Scrambler seed convention used in pkt_list.txt (tb_tx_top.sv SEED monitor):
%     bit 6 = x7 ... bit 0 = x1 of the Figure 113 shift register.

F.FRAC  = 14;
F.SCALE = 2^14;
F.W     = 16;

% ---- 802.11a rate table (Table 78 / Table 80)
%           Mb/s Nbpsc Ncbps Ndbps  R      R1..R4 (transmit order)
F.rates = [  6    1     48    24   1/2  ;
             9    1     48    36   3/4  ;
            12    2     96    48   1/2  ;
            18    2     96    72   3/4  ;
            24    4    192    96   1/2  ;
            36    4    192   144   3/4  ;
            48    6    288   192   2/3  ;
            54    6    288   216   3/4  ];
F.rate_bits = [1 1 0 1; 1 1 1 1; 0 1 0 1; 0 1 1 1; 1 0 0 1; 1 0 1 1; 0 0 0 1; 0 0 1 1];
% Relative constellation error limits, Table 90 [dB]
F.evm_limit_db = [-5 -8 -10 -13 -16 -19 -22 -25];

% ---- interpolation FIR (upsampler_fir.v, 43 taps, Q2.14, floor >>>14, sat16)
%      Implementation choice, NOT from the standard.  Same list as tb_tx_top.sv.
c22 = [363 564 715 614 207 -388 -894 -996 -530 372 1272 1600 970 -542 ...
       -2289 -3251 -2465 483 5149 10287 14282 15788];
F.fir_coef = [c22, fliplr(c22(1:21))].';
F.L_UP = 4;     % upsample_rzero_stuffing.v, L = 4 in pp_top.v

F.quantize    = @quantize_q214;
F.pack_iq     = @pack_iq;
F.unpack_iq   = @unpack_iq;
F.dac_model   = @dac_model;
F.rate_index  = @rate_index;
F.tb_rate_code= @tb_rate_code;
F.seed_bits   = @seed_bits;
end

% -------------------------------------------------------------------------
function q = quantize_q214(x)
%QUANTIZE_Q214  complex double -> [I Q] int (Nx2), round half away from zero.
% generate_preamble.py uses numpy round (half to even); for the preamble no
% value lies within 0.004 LSB of a tie, so both rules give identical integers
% (checked bit-exactly against preamble_rom_data.mem in validate).
x = x(:);
q = round([real(x) imag(x)] * 2^14);
if any(q(:) > 32767) || any(q(:) < -32768)
    error('tx_rtl_format:overflow', ...
        'Q2.14 overflow: value %.4f outside [-2, 2).', max(abs([real(x); imag(x)])));
end
end

function w = pack_iq(I, Q)
%PACK_IQ  signed 16-bit I, Q -> 32-bit word {I, Q} (as double, 0..2^32-1)
w = mod(double(I(:)), 65536) * 65536 + mod(double(Q(:)), 65536);
end

function [I, Q] = unpack_iq(w)
%UNPACK_IQ  32-bit word {I, Q} -> signed I, Q
w = double(w(:));
hi = floor(w / 65536);
lo = mod(w, 65536);
I = hi - 65536 * (hi >= 32768);
Q = lo - 65536 * (lo >= 32768);
end

function y = dac_model(x20, F)
%DAC_MODEL  x4 zero-stuffing + 43-tap FIR + floor(>>>14) + saturation.
%   x20 : complex integer samples at 20 MS/s (RTL tx_mux output)
%   y   : complex integer samples at 80 MS/s, length 4*N + 42
x20 = x20(:);
xu = zeros(F.L_UP * numel(x20), 1);
xu(1:F.L_UP:end) = x20;
yi = conv(real(xu), F.fir_coef);       % exact: |values| < 2^53
yq = conv(imag(xu), F.fir_coef);
yi = min(max(floor(yi / 2^14), -32768), 32767);
yq = min(max(floor(yq / 2^14), -32768), 32767);
y = complex(yi, yq);
end

function r = rate_index(mbps)
F = tx_rtl_format_rates();
r = find(F == mbps, 1);
if isempty(r)
    error('tx_rtl_format:rate', 'Unsupported rate %g Mb/s.', mbps);
end
end

function v = tx_rtl_format_rates()
v = [6 9 12 18 24 36 48 54];
end

function c = tb_rate_code(mbps)
%TB_RATE_CODE  4-bit code {R4,R3,R2,R1} used by TXVECTOR / tb_tx_top.sv rate_code()
rb = [1 1 0 1; 1 1 1 1; 0 1 0 1; 0 1 1 1; 1 0 0 1; 1 0 1 1; 0 0 0 1; 0 0 1 1];
b = rb(rate_index(mbps), :);            % R1 R2 R3 R4
c = b(1) + 2*b(2) + 4*b(3) + 8*b(4);
end

function x = seed_bits(seed)
%SEED_BITS  pkt_list seed (bit k-1 = x_k) -> [x1 x2 ... x7]
x = mod(floor(seed ./ 2.^(0:6)), 2);
end
