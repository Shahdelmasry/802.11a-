function cfg = tx_config(varargin)
%TX_CONFIG  Paths and constants shared by the TX verification scripts.
%
%   cfg = tx_config()                     default project root D:/STM/Final_TX_System
%   cfg = tx_config('root', 'E:/work/Final_TX_System')
%
%   The root can also be set with the environment variable TX_ROOT.
%   All paths use forward slashes (accepted by MATLAB on Windows and by xsim).

root = 'D:/ST/WIFI_802.11a_GP/Implementation/Tx_Full_System/Final_TX_System';env_root = getenv('TX_ROOT');
if ~isempty(env_root)
    root = env_root;
end
for k = 1:2:numel(varargin)
    switch lower(varargin{k})
        case 'root'
            root = varargin{k+1};
        otherwise
            error('tx_config:arg', 'Unknown option "%s".', varargin{k});
    end
end
root = strrep(root, '\', '/');
if root(end) == '/'
    root = root(1:end-1);
end

cfg.root     = root;
cfg.vec_dir  = [root '/matlab_vectors_stress'];
cfg.out_dir  = [root '/rtl_out_vivado_stress'];
cfg.rom_file = [root '/Bit_Symbol_Processing_Integration/2_Symbol_Processing/4_Preamble_Rom/preamble_rom_data.mem'];

% ---- tb_tx_top.sv contract (read from the testbench source, 2026-11-19 revision)
cfg.tb.TOL      = 32;       % +TOL default
cfg.tb.SNR_MIN  = 50;       % +SNR_MIN default [dB]
cfg.tb.WCLK_PS  = 17300;    % +WCLK_PS default
cfg.tb.GAP_CLK  = 1280;     % localparam GAP_CLK
cfg.tb.MAXMAP   = 70000;    % exp_map depth  -> 48*(NSYM+1)  <= 70000
cfg.tb.MAXBB    = 120000;   % exp_bb depth   -> 320+80*(NSYM+1) <= 120000
cfg.tb.MAXPSDU  = 4096;     % psdu depth     -> LENGTH <= 4096 (LENGTH field: 12 bits -> 4095)
cfg.tb.MAXSYMIX = 4200;     % map_sym_err / bb_sym_err depth -> NSYM+1 <= 4201
cfg.tb.DAC_LAT  = 6;        % localparam DAC_LAT
cfg.tb.RCLK_NS  = 12.5;     % r_clk 80 MHz
end
