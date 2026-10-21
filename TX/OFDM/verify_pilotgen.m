
clc;
clear;
close all;

filename = 'rtl_pilot_bits.txt';

fid = fopen(filename, 'r');

if fid == -1
    error('Cannot open rtl_pilot_bits.txt. Check the file path.');
end

actualPolarity = fscanf(fid, '%d');
fclose(fid);

actualPolarity = actualPolarity(:);

referenceString = ['00001110' ...
                   '11110010' ...
                   '11001001' ...
                   '00000010' ...
                   '00100110' ...
                   '00101110' ...
                   '10110110' ...
                   '00001100' ...
                   '11010100' ...
                   '11100111' ...
                   '10110100' ...
                   '00101010' ...
                   '11111010' ...
                   '01010001' ...
                   '10111000' ...
                   '1111111'];

expectedBits = double(referenceString(:) - '0');
expectedPolarity = 1 - 2*expectedBits;

if length(actualPolarity) ~= 127
    error('FAIL: Expected 127 polarities, but received %d.', ...
          length(actualPolarity));
end

if any(actualPolarity ~= -1 & actualPolarity ~= 1)
    error('FAIL: The input file must contain only -1 and +1.');
end

if length(expectedPolarity) ~= 127
    error('Reference sequence length is not 127.');
end

mismatch = find(actualPolarity ~= expectedPolarity);

fprintf('\nIEEE 802.11a Pilot Polarity Generator Verification\n');
fprintf('-------------------------------------------------\n');
fprintf('Samples received : %d\n', length(actualPolarity));
fprintf('Positive (+1)    : %d\n', sum(actualPolarity == 1));
fprintf('Negative (-1)    : %d\n', sum(actualPolarity == -1));

if isempty(mismatch)
    fprintf('\nRESULT: PASS\n');
    fprintf('All 127 RTL polarities match the reference.\n');
else
    fprintf('\nRESULT: FAIL\n');
    fprintf('Number of mismatches: %d\n', length(mismatch));

    fprintf('\nFirst mismatches:\n');

    for k = 1:min(10, length(mismatch))
        idx = mismatch(k);

        fprintf('Index %3d: Expected=%+d, Actual=%+d\n', ...
            idx-1, expectedPolarity(idx), actualPolarity(idx));
    end
end

fprintf('\nFirst 16 expected pilot polarities:\n');
disp(expectedPolarity(1:16).');

fprintf('First 16 actual pilot polarities:\n');
disp(actualPolarity(1:16).');

figure;

subplot(2,1,1);
stairs(0:126, expectedPolarity, 'LineWidth', 1.2);
grid on;
ylim([-1.5 1.5]);
yticks([-1 1]);
xlabel('Sequence index n');
ylabel('Polarity');
title('IEEE 802.11a Reference Pilot Polarity');

subplot(2,1,2);
stairs(0:126, actualPolarity, 'LineWidth', 1.2);
grid on;
ylim([-1.5 1.5]);
yticks([-1 1]);
xlabel('Sequence index n');
ylabel('Polarity');
title('QuestaSim RTL Pilot Polarity');

if isempty(mismatch)
    fprintf('\nPilot polarity verification: PASS\n');
    fprintf('Reference and RTL sequences match.\n');
end