function L = read_tb_log(logfile)
%READ_TB_LOG  Parse the xsim log of tb_tx_top.sv.
%
%   L = read_tb_log('D:/STM/Final_TX_System/rtl_out_vivado/xsim_smoke.log')
%
%   L.seed(pkt+1)   scrambler seed printed by the TB SEED monitor ("SEED <pkt> <seed>",
%                   MATLAB convention bit 6 = x7), NaN if the entry never started
%   L.entry(pkt+1)  struct: line, verdict ('PASS','FAIL','NOT CHECKED','MISSING'),
%                   maxerr, snr, nmap, nbb
%   L.errors        cell {pkt, message} of all "ERROR pkt N:" lines
%   L.final         'PASSED' | 'FAILED' | 'NO RESULT'
%   L.dac_ok, L.dac_err, L.min_gap, L.header, L.fatal

txt = fileread(logfile);
lines = regexp(txt, '\r?\n', 'split');

L.file = logfile;
L.seed = [];
L.entry = struct('line', {}, 'verdict', {}, 'maxerr', {}, 'snr', {}, 'nmap', {}, 'nbb', {});
L.errors = cell(0, 2);
L.final = 'NO RESULT';
L.dac_ok = NaN; L.dac_err = NaN; L.min_gap = NaN;
L.header = '';
L.fatal = {};

for i = 1:numel(lines)
    s = lines{i};
    if isempty(s), continue; end
    t = regexp(s, '^\s*SEED\s+(-?\d+)\s+(\d+)', 'tokens', 'once');
    if ~isempty(t)
        p = str2double(t{1});
        if p >= 0
            if numel(L.seed) < p + 1, L.seed(end+1:p+1) = NaN; end
            if isnan(L.seed(p + 1)), L.seed(p + 1) = str2double(t{2}); end
        end
        continue;
    end
    t = regexp(s, '^\s*pkt\s+(\d+)\s*\|', 'tokens', 'once');
    if ~isempty(t)
        p = str2double(t{1});
        e.line = strtrim(s);
        if ~isempty(regexp(s, '\|\s*PASS', 'once'))
            e.verdict = 'PASS';
        elseif ~isempty(regexp(s, '\|\s*FAIL', 'once'))
            e.verdict = 'FAIL';
        else
            e.verdict = 'NOT CHECKED';
        end
        m = regexp(s, 'maxerr\s+(\d+)\s+SNR\s+([-\d.]+)', 'tokens', 'once');
        if isempty(m), e.maxerr = NaN; e.snr = NaN;
        else, e.maxerr = str2double(m{1}); e.snr = str2double(m{2}); end
        m = regexp(s, 'map\s+(\d+)', 'tokens', 'once');
        if isempty(m), e.nmap = NaN; else, e.nmap = str2double(m{1}); end
        m = regexp(s, 'bb\s+(\d+)', 'tokens', 'once');
        if isempty(m), e.nbb = NaN; else, e.nbb = str2double(m{1}); end
        L.entry(p + 1) = e;
        continue;
    end
    t = regexp(s, 'ERROR pkt\s+(-?\d+):\s*(.*)$', 'tokens', 'once');
    if ~isempty(t)
        L.errors(end+1, :) = {str2double(t{1}), strtrim(t{2})};
        continue;
    end
    t = regexp(s, '\*\*\* TEST (PASSED|FAILED)', 'tokens', 'once');
    if ~isempty(t), L.final = t{1}; continue; end
    t = regexp(s, 'DAC model:\s*(\d+) clocks bit-exact,\s*(\d+) mismatches; min inter-packet gap\s*(-?\d+)', 'tokens', 'once');
    if ~isempty(t)
        L.dac_ok = str2double(t{1}); L.dac_err = str2double(t{2}); L.min_gap = str2double(t{3});
        continue;
    end
    if ~isempty(strfind(s, '==== tb_tx_top:')), L.header = strtrim(s); continue; end
    if ~isempty(regexp(s, '(Fatal|FATAL|\$fatal)', 'once')), L.fatal{end+1} = strtrim(s); end
end
for p = 1:numel(L.entry)
    if isempty(L.entry(p).verdict)
        L.entry(p).line = ''; L.entry(p).verdict = 'MISSING';
        L.entry(p).maxerr = NaN; L.entry(p).snr = NaN; L.entry(p).nmap = NaN; L.entry(p).nbb = NaN;
    end
end
end
