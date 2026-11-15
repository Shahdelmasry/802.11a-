%% verify_mapper_ifft_reference.m
% Reference model for mapper_input.hex -> 802.11a 64-bin spectrum -> IFFT.
% Uses the exact Pilot_Insertion bin map and Pilot_Gen LFSR from the RTL.
% This is an ideal double-precision reference, NOT yet a bit-accurate RTL model.

clear; clc;

inputFile = 'mapper_input.hex';
if ~isfile(inputFile)
    error('Cannot find %s in the current MATLAB folder.', inputFile);
end

% Read exactly 32-bit packed words: {I[15:0], Q[15:0]}.
fid = fopen(inputFile, 'r');
if fid < 0, error('Cannot open %s.', inputFile); end
C = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
fclose(fid);
hexWords = strtrim(C{1});
hexWords = hexWords(~cellfun('isempty', hexWords));

if any(cellfun(@numel, hexWords) ~= 8)
    error('Every input word must contain exactly 8 hex digits.');
end
if numel(hexWords) ~= 6096
    error('Expected 6096 words (127*48); found %d.', numel(hexWords));
end

u32 = uint32(hex2dec(char(hexWords)));
uI = uint16(bitshift(u32, -16));
uQ = uint16(bitand(u32, uint32(65535)));
I = double(typecast(uI(:), 'int16'));
Q = double(typecast(uQ(:), 'int16'));
mapper = complex(I, Q);
mapper = reshape(mapper, 48, []).';  % 127 rows, 48 data carriers

numSymbols = size(mapper,1);
Xall = complex(zeros(numSymbols,64));
xall = complex(zeros(numSymbols,64));

% Pilot_Gen: seed=7'h7f; feedback=lfsr[6]^lfsr[3].
% RTL pilot_out = feedback ? -1 : +1. Advance once per completed symbol.
lfsr = uint8(hex2dec('7F'));

for s = 1:numSymbols
    feedback = bitget(lfsr,7) ~= bitget(lfsr,4);
    pilotPolarity = 1;
    if feedback, pilotPolarity = -1; end

    X = complex(zeros(1,64));

    % Exact data-bin mapping from Pilot_Insertion.v.
    % MATLAB index = RTL bin number + 1.
    dataBins = [38:42, 44:56, 58:63, 1:6, 8:20, 22:26];
    if numel(dataBins) ~= 48
        error('Internal mapping error: expected 48 data bins.');
    end
    X(dataBins + 1) = mapper(s,:);

    % Four pilot bins: 7, 21, 43, 57 (RTL zero-based).
    X(7+1)  = pilotPolarity * 16384;
    X(21+1) = -pilotPolarity * 16384; % bin 21 has opposite polarity
    X(43+1) = pilotPolarity * 16384;
    X(57+1) = pilotPolarity * 16384;

    % All other bins are null, including DC bin 0.
    Xall(s,:) = X;

    % MATLAB ifft uses the standard positive-exponent IDFT and 1/64 scale.
    xall(s,:) = ifft(X,64);

    % Match Pilot_Gen's {lfsr[5:0], feedback} shift.
    lfsr = uint8(bitand(bitshift(lfsr,1), uint8(127)));
    if feedback
        lfsr = bitor(lfsr, uint8(1));
    end
end

% Report spectrum structure and reference ranges.
fprintf('Loaded %d OFDM symbols (%d mapper words).\n', numSymbols, numSymbols*48);
fprintf('Data bins: 48; pilot bins: 4; null bins: 12.\n');
fprintf('Pilot amplitudes: +/-16384 (Q2.14).\n');
fprintf('Ideal IFFT raw-domain range: I=[%.3f, %.3f], Q=[%.3f, %.3f]\n', ...
    min(real(xall),[],'all'), max(real(xall),[],'all'), ...
    min(imag(xall),[],'all'), max(imag(xall),[],'all'));

% Export per-symbol frequency bins and ideal time samples as packed hex.
% Each output word is {signed I[15:0], signed Q[15:0]}.
write_complex_hex('matlab_reference_bins.hex', Xall);
write_complex_hex('matlab_reference_ifft.hex', xall);

% Plot first symbol to inspect the expected spectrum and time-domain waveform.
figure('Name','OFDM symbol 1 reference');
subplot(2,1,1);
stem(0:63, abs(Xall(1,:)), '.');
grid on; xlabel('Subcarrier bin'); ylabel('|X[k]|');
title('First OFDM symbol: 64-bin spectrum');
subplot(2,1,2);
plot(0:63, real(xall(1,:)), '-o'); hold on;
plot(0:63, imag(xall(1,:)), '-x');
grid on; xlabel('Time sample'); ylabel('Amplitude (input integer units)');
legend('I','Q'); title('Ideal 64-point IFFT (double precision)');

% Optional cyclic prefix reference: last 16 samples then all 64 samples.
cpall = [xall(:,49:64), xall];
write_complex_hex('matlab_reference_ifft_cp.hex', cpall);
fprintf('Wrote matlab_reference_bins.hex, matlab_reference_ifft.hex, and matlab_reference_ifft_cp.hex.\n');

function write_complex_hex(filename, z)
    fid = fopen(filename,'w');
    if fid < 0, error('Cannot create %s.', filename); end
    cleanup = onCleanup(@() fclose(fid));
    for r = 1:size(z,1)
        for c = 1:size(z,2)
            % Round to nearest integer for transport only; ideal double data
            % remains in MATLAB variables. Saturate to signed 16-bit range.
            ii = min(max(round(real(z(r,c))), -32768), 32767);
            qq = min(max(round(imag(z(r,c))), -32768), 32767);
            iu = uint16(mod(ii,65536));
            qu = uint16(mod(qq,65536));
            word = bitor(bitshift(uint32(iu),16), uint32(qu));
            fprintf(fid,'%08X\n',word);
        end
    end
end
