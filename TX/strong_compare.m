
clear; clc;

%% =========================================================
% STRONG PILOT INSERTION RTL VERIFICATION
% DUT: Pilot_Gen + Pilot_Insertion
% Reference: mapper stimulus + exported verified polarity
%
% Files required:
%   mapper_input.hex
%   expected_polarity.txt
%   pilot_rtl_output.hex
%
% Optional:
%   pilot_expected.hex (previous golden output)
%% =========================================================

NFFT  = 64;
NDATA = 48;
NPILOT = 4;
NSYM_EXPECTED = 127;

INPUT_FILE     = 'mapper_input.hex';
POLARITY_FILE  = 'expected_polarity.txt';
RTL_FILE       = 'pilot_rtl_output.hex';
OLD_GOLDEN_FILE = 'pilot_expected.hex';

%% 1. Read and validate input files
assert(isfile(INPUT_FILE),    'Missing file: %s', INPUT_FILE);
assert(isfile(POLARITY_FILE), 'Missing file: %s', POLARITY_FILE);
assert(isfile(RTL_FILE),      'Missing file: %s', RTL_FILE);

inputWords = readHexWords(INPUT_FILE);
polarity = readmatrix(POLARITY_FILE);
polarity = polarity(:);

actualWords = readHexWords(RTL_FILE);

assert(all(polarity == 1 | polarity == -1), ...
    'Polarity file must contain only +1 or -1.');

NSYM = numel(polarity);

assert(NSYM == NSYM_EXPECTED, ...
    'Expected %d polarity entries, found %d.', ...
    NSYM_EXPECTED, NSYM);

expectedInputCount = NSYM * NDATA;
expectedOutputCount = NSYM * NFFT;

fprintf('\n========================================\n');
fprintf(' PILOT INSERTION VERIFICATION\n');
fprintf('========================================\n');
fprintf('OFDM symbols expected : %d\n', NSYM);
fprintf('Input words expected  : %d\n', expectedInputCount);
fprintf('Output bins expected  : %d\n', expectedOutputCount);
fprintf('Input words found     : %d\n', numel(inputWords));
fprintf('Output bins found     : %d\n', numel(actualWords));

if numel(inputWords) ~= expectedInputCount
    error('Input length mismatch: expected %d words, found %d.', ...
        expectedInputCount, numel(inputWords));
end

if numel(actualWords) ~= expectedOutputCount
    error(['Output length mismatch: expected %d words (%d x %d), ' ...
           'found %d. Check the testbench capture loop.'], ...
        expectedOutputCount, NSYM, NFFT, numel(actualWords));
end

%% 2. Define 802.11a subcarrier mapping
% Input order must match the DUT data_index_for_bin function.
dataTones = [-26:-22, -20:-8, -6:-1, ...
               1:6,     8:20, 22:26];

pilotTones = [-21, -7, 7, 21];

% Zero-based natural-order IFFT bin indices.
dataBins = mod(dataTones, NFFT);
pilotBins = mod(pilotTones, NFFT);

% Null bins: DC, guard bands, and the Nyquist bin.
nullBins = setdiff(0:NFFT-1, [dataBins, pilotBins]);

assert(numel(dataTones) == NDATA);
assert(numel(pilotBins) == NPILOT);
assert(numel(dataBins) == NDATA);
assert(numel(nullBins) == 12);

fprintf('\nData bins  : %s\n', mat2str(dataBins));
fprintf('Pilot bins : %s\n', mat2str(pilotBins));
fprintf('Null bins  : %s\n', mat2str(nullBins));

%% 3. Reconstruct expected output independently
% Rebuild expected bins from input words and polarity.
% Do not use pilot_expected.hex as the primary reference.

expectedWords = zeros(expectedOutputCount, 1, 'uint32');

% Classification of every output bin.
isDataBin  = false(NFFT,1);
isPilotBin = false(NFFT,1);
isNullBin  = false(NFFT,1);

isDataBin(dataBins + 1) = true;
isPilotBin(pilotBins + 1) = true;
isNullBin(nullBins + 1) = true;

for s = 1:NSYM

    % Decode 48 packed input words.
    firstIn = (s-1)*NDATA + 1;
    lastIn  = s*NDATA;

    words = inputWords(firstIn:lastIn);

    % Upper half is I, lower half is Q.
    iBits = uint16(bitshift(words, -16));
    qBits = uint16(bitand(words, uint32(65535)));

    % Interpret the bit patterns as signed 16-bit values.
    I = typecast(iBits, 'int16');
    Q = typecast(qBits, 'int16');

    % Initialize the complete 64-bin vector to zero.
    binsI = zeros(NFFT,1,'int16');
    binsQ = zeros(NFFT,1,'int16');

    % Insert data in the documented input order.
    for d = 1:NDATA
        idx = dataBins(d) + 1;
        binsI(idx) = I(d);
        binsQ(idx) = Q(d);
    end

    % Insert pilot sequence for this OFDM symbol:
    % [-21,-7,+7,+21] -> [Pn,Pn,Pn,-Pn].
    p = polarity(s);
    pilotValues = [p, p, p, -p];

    for k = 1:NPILOT
        idx = pilotBins(k) + 1;

        if pilotValues(k) == 1
            binsI(idx) = int16(32767);
        else
            binsI(idx) = int16(-32768);
        end

        binsQ(idx) = int16(0);
    end

    % Pack all bins as {I[15:0], Q[15:0]}.
    firstOut = (s-1)*NFFT + 1;

    for b = 1:NFFT
        ib = uint32(typecast(binsI(b), 'uint16'));
        qb = uint32(typecast(binsQ(b), 'uint16'));

        expectedWords(firstOut+b-1) = ...
            bitor(bitshift(ib,16), qb);
    end
end

%% 4. Full 32-bit comparison
mismatch = expectedWords ~= actualWords;
bad = find(mismatch);

% Map every output word to its symbol and zero-based bin.
wordIndex = (1:expectedOutputCount).';
symbolIndex = floor((wordIndex-1)/NFFT) + 1;
binIndex = mod(wordIndex-1, NFFT);

% Categorize mismatches.
category = strings(expectedOutputCount,1);
category(isDataBin(binIndex+1))  = "DATA";
category(isPilotBin(binIndex+1)) = "PILOT";
category(isNullBin(binIndex+1))  = "NULL";

dataMismatch  = mismatch & category == "DATA";
pilotMismatch = mismatch & category == "PILOT";
nullMismatch  = mismatch & category == "NULL";

%% 5. Separate I and Q mismatch analysis
expectedI = uint16(bitshift(expectedWords,-16));
actualI   = uint16(bitshift(actualWords,-16));

expectedQ = uint16(bitand(expectedWords,uint32(65535)));
actualQ   = uint16(bitand(actualWords,uint32(65535)));

iMismatch = expectedI ~= actualI;
qMismatch = expectedQ ~= actualQ;

%% 6. Explicit structural checks
% Reconstruct the observed complex bins.
actualBinsI = typecast(expectedI, 'int16');
actualBinsQ = typecast(expectedQ, 'int16');

% Count pilot mismatches per individual pilot bin.
pilotMismatchCount = zeros(NPILOT,1);

for k = 1:NPILOT
    mask = binIndex == pilotBins(k);
    pilotMismatchCount(k) = sum(mismatch(mask));
end

% Count nonzero words at null bins.
nullNonzeroCount = 0;

for k = 1:numel(nullBins)
    mask = binIndex == nullBins(k);
    nullNonzeroCount = nullNonzeroCount + ...
        sum(actualWords(mask) ~= uint32(0));
end

% Validate polarity sequence format and report transitions.
polarityTransitions = sum(polarity(2:end) ~= polarity(1:end-1));

%% 7. Compare with previous golden file, if present
oldGoldenMismatchCount = NaN;

if isfile(OLD_GOLDEN_FILE)
    oldGolden = readHexWords(OLD_GOLDEN_FILE);

    if numel(oldGolden) == expectedOutputCount
        oldGoldenMismatchCount = sum(oldGolden ~= expectedWords);
        fprintf('\nPrevious golden vs rebuilt reference: %d mismatches\n', ...
            oldGoldenMismatchCount);
    else
        fprintf('\nWARNING: Previous golden file has %d words; expected %d.\n', ...
            numel(oldGolden), expectedOutputCount);
    end
end

%% 8. Print summary
fprintf('\n========================================\n');
fprintf(' VERIFICATION SUMMARY\n');
fprintf('========================================\n');
fprintf('Total output words checked : %d\n', expectedOutputCount);
fprintf('Total mismatches            : %d\n', sum(mismatch));
fprintf('Data-bin mismatches         : %d\n', sum(dataMismatch));
fprintf('Pilot-bin mismatches        : %d\n', sum(pilotMismatch));
fprintf('Null-bin mismatches         : %d\n', sum(nullMismatch));
fprintf('I-field mismatches          : %d\n', sum(iMismatch));
fprintf('Q-field mismatches          : %d\n', sum(qMismatch));
fprintf('Nonzero null-bin words      : %d\n', nullNonzeroCount);
fprintf('Pilot polarity transitions  : %d\n', polarityTransitions);

fprintf('\nPer-pilot mismatch counts:\n');
for k = 1:NPILOT
    fprintf('  Signed tone %+3d, bin %2d: %d mismatches\n', ...
        pilotTones(k), pilotBins(k), pilotMismatchCount(k));
end

%% 9. Write a detailed mismatch report
if ~isempty(bad)
    report = table( ...
        symbolIndex(bad), ...
        binIndex(bad), ...
        category(bad), ...
        expectedWords(bad), ...
        actualWords(bad), ...
        expectedI(bad), ...
        actualI(bad), ...
        expectedQ(bad), ...
        actualQ(bad), ...
        'VariableNames', { ...
        'Symbol', 'Bin', 'Category', ...
        'ExpectedWord', 'ActualWord', ...
        'ExpectedI', 'ActualI', ...
        'ExpectedQ', 'ActualQ'});

    writetable(report, 'pilot_mismatch_report.csv');

    fprintf('\nFirst mismatches:\n');
    disp(report(1:min(20,height(report)),:));

    fprintf('Full mismatch report: pilot_mismatch_report.csv\n');
else
    fprintf('\nPASS: all output words match the rebuilt reference.\n');

    if nullNonzeroCount == 0
        fprintf('PASS: all null bins are zero.\n');
    else
        fprintf('FAIL: nonzero values found in null bins.\n');
    end

    if sum(pilotMismatch) == 0
        fprintf('PASS: all four pilot bins match the expected sequence.\n');
    end
end

%% 10. Final machine-readable result
if isempty(bad) && nullNonzeroCount == 0
    fprintf('\nFINAL RESULT: PASS\n');
else
    fprintf('\nFINAL RESULT: FAIL\n');
end

%% =========================================================
% Local helper: read exactly one 32-bit hexadecimal word/line.
%% =========================================================
function words = readHexWords(filename)

    lines = strip(readlines(filename));

    % Ignore empty lines only.
    lines(lines == "") = [];

    % Validate every line contains exactly 8 hex digits.
    valid = ~cellfun('isempty', regexp(cellstr(lines), ...
        '^[0-9A-Fa-f]{8}$', 'once'));

    if any(~valid)
        badLine = find(~valid, 1);
        error('%s: invalid 32-bit hex word at nonempty line %d: "%s"', ...
            filename, badLine, lines(badLine));
    end

    words = uint32(hex2dec(lines));
end
