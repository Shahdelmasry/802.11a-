function info = export_tb_vectors(vec_dir, cases, refs, meta)
%EXPORT_TB_VECTORS  Write the files read by tb_tx_top.sv.
%
%   export_tb_vectors(vec_dir, cases, refs, meta)
%
%   Files (exactly the formats parsed by tb_tx_top.sv):
%     pkt_list.txt      line 1: number of entries
%                       then one line per entry: RATE LENGTH SEED NSYM MODE PARAM
%                       ($fscanf "%d %d %d %d %d %d", all decimal)
%     pktNNN_psdu.hex   LENGTH lines, 2 hex digits      ($readmemh -> logic [7:0])
%     pktNNN_map.hex    48*(NSYM+1) lines, 8 hex digits ($readmemh -> logic [31:0])
%                       {I[15:0], Q[15:0]} two's complement Q2.14, SIGNAL symbol first,
%                       48 values per OFDM symbol in data-subcarrier order -26..26
%     pktNNN_bb.hex     320+80*(NSYM+1) lines, 8 hex digits, same packing,
%                       20 MS/s stream at tx_mux: preamble, SIGNAL, DATA 1..NSYM
%   Extra files for the MATLAB side (not read by the TB):
%     golden_db.mat     float golden + metadata for compare_rtl_matlab.m
%     manifest.csv      readable scenario list
%     gtimeout_ms.txt   +GTIMEOUT_MS value large enough for this regression
%     regression.txt    name of the regression in this folder
%
%   Old pkt*.hex files are deleted first, so a shorter regression never leaves
%   stale files behind.

F = tx_rtl_format();
if ~exist(vec_dir, 'dir')
    [ok, msg] = mkdir(vec_dir);
    if ~ok, error('export_tb_vectors:mkdir', 'Cannot create %s: %s', vec_dir, msg); end
end
old = [dir(fullfile(vec_dir, 'pkt*_psdu.hex')); dir(fullfile(vec_dir, 'pkt*_map.hex')); ...
       dir(fullfile(vec_dir, 'pkt*_bb.hex'))];
for k = 1:numel(old)
    delete(fullfile(vec_dir, old(k).name));
end

N = numel(cases);
fid = fopen_w(fullfile(vec_dir, 'pkt_list.txt'));
fprintf(fid, '%d\n', N);
for i = 1:N
    r = refs{i};
    fprintf(fid, '%d %d %d %d %d %d\n', cases(i).rate, cases(i).len, r.seed, r.nsym, ...
            cases(i).mode, round(cases(i).param));
end
fclose(fid);

db = struct('rate', {}, 'len', {}, 'seed', {}, 'nsym', {}, 'mode', {}, 'param', {}, ...
            'pattern', {}, 'note', {}, 'psdu', {}, 'map', {}, 'wave', {}, 'map_int', {}, ...
            'bb_int', {}, 'engine', {}, 'seed_from_log', {});
for i = 1:N
    r = refs{i};
    tag = sprintf('pkt%03d', i - 1);

    fid = fopen_w(fullfile(vec_dir, [tag '_psdu.hex']));
    fprintf(fid, '%02X\n', cases(i).psdu);
    fclose(fid);

    qm = F.quantize(r.map(:));                     % column-major: symbol by symbol
    wm = F.pack_iq(qm(:, 1), qm(:, 2));
    fid = fopen_w(fullfile(vec_dir, [tag '_map.hex']));
    fprintf(fid, '%08X\n', wm);
    fclose(fid);

    qb = F.quantize(r.wave);
    wb = F.pack_iq(qb(:, 1), qb(:, 2));
    fid = fopen_w(fullfile(vec_dir, [tag '_bb.hex']));
    fprintf(fid, '%08X\n', wb);
    fclose(fid);

    db(i).rate = cases(i).rate;   db(i).len = cases(i).len;   db(i).seed = r.seed;
    db(i).nsym = r.nsym;          db(i).mode = cases(i).mode; db(i).param = cases(i).param;
    db(i).pattern = cases(i).pattern; db(i).note = cases(i).note;
    db(i).psdu = cases(i).psdu;   db(i).map = r.map;          db(i).wave = r.wave;
    db(i).map_int = complex(qm(:, 1), qm(:, 2));
    db(i).bb_int  = complex(qb(:, 1), qb(:, 2));
    db(i).engine  = r.engine;
    db(i).seed_from_log = meta.seed_from_log(i);
end

% ---- readable manifest
fid = fopen_w(fullfile(vec_dir, 'manifest.csv'));
fprintf(fid, 'pkt,rate_mbps,length,seed,nsym,mode,param,pattern,seed_from_vivado_log,note\n');
mname = {'normal', 'abort', 'bad_rate', 'reset'};
for i = 1:N
    fprintf(fid, '%d,%d,%d,%d,%d,%s,%d,%s,%d,"%s"\n', i - 1, db(i).rate, db(i).len, db(i).seed, ...
            db(i).nsym, mname{db(i).mode + 1}, round(db(i).param), db(i).pattern, ...
            db(i).seed_from_log, db(i).note);
end
fclose(fid);

% ---- global timeout estimate for +GTIMEOUT_MS (simulated time, not wall clock)
t_us = 0;
for i = 1:N
    air = (320 + 80 * (db(i).nsym + 1)) * 0.05;        % 20 MS/s samples [us]
    switch db(i).mode
        case 0, t_us = t_us + air + 40;                  % + gap 16 us + handshakes
        case 1, t_us = t_us + air + 60;                  % + GAP_CLK + 400 clk wait
        case 2, t_us = t_us + 20 + 0.1 * db(i).len;      % FIFO drop of LENGTH octets
        case 3, t_us = t_us + db(i).param * 0.0125 + 5;
    end
end
gt_ms = ceil(1.5 * t_us / 1000) + 2;
fid = fopen_w(fullfile(vec_dir, 'gtimeout_ms.txt'));
fprintf(fid, '%d\n', gt_ms);
fclose(fid);
fid = fopen_w(fullfile(vec_dir, 'regression.txt'));
fprintf(fid, '%s\n', meta.regression);
fclose(fid);

meta.created   = datestr(now, 'yyyy-mm-dd HH:MM:SS');
meta.gtimeout_ms = gt_ms;
meta.sim_time_us_estimate = t_us;
save(fullfile(vec_dir, 'golden_db.mat'), 'db', 'meta', '-v7');

info.n = N;
info.gtimeout_ms = gt_ms;
info.sim_time_us = t_us;
fprintf('Exported %d entries to %s (estimated simulated time %.2f ms, +GTIMEOUT_MS=%d)\n', ...
        N, vec_dir, t_us / 1000, gt_ms);
end

function fid = fopen_w(name)
fid = fopen(name, 'w');
if fid < 0
    error('export_tb_vectors:open', 'Cannot write %s', name);
end
end
