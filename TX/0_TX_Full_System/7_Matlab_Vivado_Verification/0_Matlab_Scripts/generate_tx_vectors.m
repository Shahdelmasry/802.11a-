function generate_tx_vectors(regression, seed_log, varargin)
%GENERATE_TX_VECTORS  Build, export and validate the golden vectors for tb_tx_top.sv.
%
%   generate_tx_vectors                     smoke regression, PASS 1 (placeholder seeds)
%   generate_tx_vectors('extended')         'smoke' | 'extended' | 'stress'
%   generate_tx_vectors('smoke', 'D:/STM/Final_TX_System/rtl_out_vivado/xsim_smoke.log')
%                                           PASS 2: seeds taken from the Vivado log
%   generate_tx_vectors(..., 'Root', 'D:/STM/Final_TX_System', 'Engine', 'auto')
%
%   WHY TWO PASSES: the DUT picks the scrambler seed itself (input_buffer.v,
%   free-running LFSR "rnd" sampled at tx_start, as 17.3.5.4 requires), so the
%   seed of each packet is only known after a simulation.  tb_tx_top.sv prints
%   it ("SEED <pkt> <seed>").  The DUT timing does not depend on the vector
%   contents, so the seeds of pass 2 are identical to those of pass 1.
%   In pass 1, SIGNAL symbols, preambles, control and DAC checks are valid;
%   DATA-symbol mismatches and S12 seed errors are EXPECTED.  Only pass 2 counts.
%
%   Steps: self-test of the golden model (Annex G) -> scenarios -> golden per
%   packet -> export -> read-back validation.

if nargin < 1 || isempty(regression), regression = 'smoke'; end
if nargin < 2, seed_log = ''; end
root = ''; engine = 'auto';
for k = 1:2:numel(varargin)
    switch lower(varargin{k})
        case 'root',   root = varargin{k+1};
        case 'engine', engine = varargin{k+1};
        otherwise, error('generate_tx_vectors:arg', 'Unknown option %s', varargin{k});
    end
end
if isempty(root), cfg = tx_config(); else, cfg = tx_config('root', root); end
t0 = tic;
fprintf('================================================================\n');
fprintf(' generate_tx_vectors  regression=%s  root=%s\n', regression, cfg.root);
fprintf(' MATLAB %s\n', version);
fprintf('================================================================\n');

% ---- 1. golden model self-test against the standard
rep = tx_golden_reference('selftest');
if ~rep.pass
    error('generate_tx_vectors:selftest', 'Golden model self-test FAILED - no vectors written.');
end

% ---- 2. scenarios
cases = generate_test_cases(regression);
N = numel(cases);
fprintf('%d entries in regression "%s"\n', N, regression);

% ---- 3. seeds
seeds = 93 * ones(N, 1);              % placeholder (pass 1); 93 = 1011101b
from_log = false(N, 1);
if ~isempty(seed_log)
    if ~exist(seed_log, 'file')
        error('generate_tx_vectors:log', 'Seed log %s not found.', seed_log);
    end
    LG = read_tb_log(seed_log);
    ns = numel(LG.seed);
    for i = 1:min(N, ns)
        if ~isnan(LG.seed(i)) && LG.seed(i) >= 1 && LG.seed(i) <= 127
            seeds(i) = LG.seed(i); from_log(i) = true;
        end
    end
    fprintf('PASS 2: %d seeds taken from %s\n', sum(from_log), seed_log);
    if numel(LG.entry) ~= N && numel(LG.entry) > 0
        warning('generate_tx_vectors:log', ['The log has %d entries, this regression has %d: ' ...
            'was the log produced with the same regression?'], numel(LG.entry), N);
    end
    miss = find(~from_log & [cases.mode].' == 0);
    if ~isempty(miss)
        warning('generate_tx_vectors:seed', 'No SEED line for normal entries %s (simulation stopped early?).', ...
            mat2str(miss.' - 1));
    end
    pass = 2;
else
    fprintf('PASS 1: placeholder seed 93 for every entry (DATA-symbol checks of the TB will fail - expected)\n');
    pass = 1;
end

% ---- 4. golden per packet
refs = cell(N, 1);
for i = 1:N
    refs{i} = tx_golden_reference(cases(i).psdu, cases(i).rate, seeds(i), 'Engine', engine);
end
fprintf('golden engine: %s\n', refs{1}.engine);

% ---- 5. export
meta.regression = regression;
meta.pass = pass;
meta.seed_log = seed_log;
meta.seed_from_log = from_log;
meta.engine = refs{1}.engine;
meta.matlab = version;
meta.selftest = rep.items;
info = export_tb_vectors(cfg.vec_dir, cases, refs, meta);
if ~exist(cfg.out_dir, 'dir'), mkdir(cfg.out_dir); end

% ---- 6. read-back validation
v = validate_generated_vectors(cfg.vec_dir);
if ~v.ok
    error('generate_tx_vectors:validate', 'Validation FAILED - do not simulate with these vectors.');
end

fprintf('\nDone in %.1f s.  Vectors: %s\n', toc(t0), cfg.vec_dir);
fprintf('Next (Windows cmd):  %s\\vivado\\run_tx_sim.bat %s\n', strrep(cfg.root, '/', '\'), regression);
if pass == 1
    fprintf('Then in MATLAB    :  generate_tx_vectors(''%s'', ''%s/xsim_%s.log'')\n', regression, cfg.out_dir, regression);
    fprintf('and run the simulation again (pass 2).\n');
else
    fprintf('Then in MATLAB    :  R = compare_rtl_matlab(''Log'', ''xsim_%s.log''); plot_tx_results(R);\n', regression);
end
fprintf('+GTIMEOUT_MS for this regression: %d (written to gtimeout_ms.txt)\n', info.gtimeout_ms);
end
