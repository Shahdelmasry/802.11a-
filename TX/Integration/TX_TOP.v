module TX_TOP  #(
    parameter DATA_WIDTH = 16   // Width of I and Q (Q2.(DATA_WIDTH-2)); maps to W in bit_proc
) (
 // ================= MAC side (w_clk domain) =================
    input  wire        w_clk,
    input  wire        w_rstn,                 // active-low
    input  wire [34:0] TXVECTOR,               // [34:23]=LENGTH [22:19]=RATE [18:3]=SERVICE [2:0]=TXPWR
    input  wire [7:0]  PHY_DATA_req,           // PSDU byte (pulled by data_confirm)
    input  wire        PHY_TXEND_req,          // PHY-TXEND.request (1-cycle pulse)
    output wire        PHY_TXSTART_conf,       // pulse
    output wire        PHY_DATA_conf,           // PHY-DATA.confirm
    output wire        PHY_TXEND_CONF,         // pulse

 // ================= PHY side (r_clk domain)===================
    input  wire        r_clk,
    input  wire        r_rstn,                 // active-low
    output reg [DATA_WIDTH-1:0] DAC_DATA_I,
    output reg [DATA_WIDTH-1:0] DAC_DATA_Q,
);

// ---------------- internal wires ----------------
wire        header_valid;   // pulse: rate/txpwr/length are valid -> start the transmission           
wire        vec_err;        // pulse: bad RATE or LENGTH=0; packet dropped (no header_valid)
wire [7:0]  data;           // PSDU byte
wire        data_valid;     // data byte is valid (hold until data_ready)
wire        abort;          // abort level (already synchronized to r_clk)
wire        flushing;       // FIFO is being flushed because of an abort
wire        txend_pulse;    // pulse: packet closed (informational)
wire        fifo_busy;  
wire        tx_clear;       // Pulse: clear Encoder history (packet / SIGNAL / DATA start)
wire        il_start;       // Level: request Interleaver block; hold until in_ready = 1
wire        scr_enable;     // High for exactly W+2 cycles per OFDM symbol
wire [6:0]  scr_seed;       // Scrambler seed of current symbol
wire        scr_bypass;     // 1: SIGNAL field; Scrambler skipped
wire [1:0]  coding_rate;    // 0: 1/2; 1: 2/3; 2: 3/4 (3 is illegal)
wire [1:0]  modulation;     // 0: BPSK; 1: QPSK; 2: 16-QAM; 3: 64-QAM
wire        seed_sel;
wire [5:0]  data_in;        // 6 data bits (bit 0 oldest); valid when data_req = 1
wire [5:0]  tail_mask;      // 1 = clear bit after scrambling (tail bits)
wire        data_req;       // Data word consumed in current cycle
wire        in_ready;       // Interleaver write window open
wire        il_busy;        // Interleaver block in flight
wire        cfg_err;        // Debug: illegal coding_rate / modulation pair
wire [1:0]  preamb_mux_sel;
wire        rom_rd_en;
wire [8:0]  rom_addr;
wire        rom_ready;
wire        tx_start;
wire        ifft_mode;
wire        pkt_last;       // Current symbol is the last of the packe
wire        mapper_capture_ready;
wire        tx_done;
wire        start_of_data;
wire        end_of_data;  
wire        data_ready;
wire        counter_en;
wire        input_wr_en;
wire        input_rd_en;
wire [11:0] Length;
wire [3:0]  rate;
wire [2:0]  powerlevel;
wire [8:0]  ndbps;



// MAC_PHY interface
mac_phy_interface #(
    .ADDR_WIDTH(6)
) mac_phy_interface_inst (
    .w_clk(w_clk),
    .w_rstn(w_rstn),
    .r_clk(r_clk),
    .r_rstn(r_rstn),
    .TXVECTOR(TXVECTOR),
    .data_request(PHY_DATA_req),
    .PHY_TXEND_req(PHY_TXEND_req),
    .PHY_TXSTART_conf(PHY_TXSTART_conf),
    .data_confirm(PHY_DATA_conf),
    .PHY_TXEND_CONF(PHY_TXEND_CONF),
    .header_valid(header_valid),
    .vec_err(vec_err),
    .data(data),
    .data_valid(data_valid),
    .abort(abort),
    .flushing(flushing),
    .txend_pulse(txend_pulse),
    .busy(fifo_busy)
);

// Data path 
TX_DATAPATH #(
    .DATA_WIDTH(DATA_WIDTH)
) tx_datapath_inst (
    .clk(r_clk),
    .rst_n(r_rstn),
    .tx_clear(tx_clear),
    .il_start(il_start),
    .scr_enable(scr_enable),
    .scr_seed(scr_seed),
    .scr_bypass(scr_bypass),
    .coding_rate(coding_rate),
    .modulation(modulation),
    .packet_end(end_of_data),
    .seed_sel(seed_sel),
    .data_in(data_in),
    .tail_mask(tail_mask),
    .data_req(data_req),
    .in_ready(in_ready),
    .il_busy(il_busy),
    .cfg_err(cfg_err),
    .mux_sel(preamb_mux_sel),
    .rom_rd_en(rom_rd_en),
    .rom_addr(rom_addr),
    .rom_ready(rom_ready),
    .tx_start(tx_start),
    .ifft_mode(ifft_mode),
    .pkt_last(pkt_last),
    .mapper_capture_ready(mapper_capture_ready),
    .tx_done(tx_done),
    .dac_data_i(DAC_DATA_I),
    .dac_data_q(DAC_DATA_Q)
);

//Controller
TX_CONTROLLER tx_controller_inst(
    .clk(r_clk)
    .rst_n(r_rstn),
    .preamble_valid(), /////
    .fifo_busy(fifo_busy),
    .fifo_data_valid(data_valid),
    .fifo_header_valid(header_valid),
    .abort(abort),
    .vector_err(vec_err),
    .mapper_capture_ready(mapper_capture_ready),////////
    .tx_done(tx_done),
    .in_ready(in_ready),
    .il_busy(il_busy),
    .il_start(il_start),
    .tx_clear(tx_clear),
    .seed_sel(seed_sel),
    .scr_en(scr_enable),
    .data_ready(data_ready),
    .ifft_mode(ifft_mode),
    .ifft_start(ifft_start),
    .rom_read_en(rom_rd_en),
    .counter_en(counter_en),
    .preamb_mux_en(preamb_mux_sel),
    .signal_mux_en(scr_bypass),
    .input_wr_en(input_wr_en),
    .input_rd_en(input_rd_en),

);

signal_field_generation SFG_inst (
    .clk(r_clk),
    .rst(r_rstn),
    .TXVECTOR(),///////
    .rate(rate),
    .Length(Length),
    .powerlevel(powerlevel),
    .ndbps(ndbps),
    .coding_rate(coding_rate),
    .modulation(modulation),
    .Signal()///////
);

data_counter data_counter_inst (
    .clk(r_clk),
    .rst(r_rstn),  
    .enable(counter_en) ,
    .data_valid(data_valid),
    .Length(Length),
    .start_of_data(start_of_data),
    .end_of_data(end_of_data)
);

input_buffer input_buffer_inst(
    .clk(r_clk),
    .rst(r_rstn), 
    .wr_en(input_wr_en),
    .wr_byte(data),
    .read_en(input_rd_en)
    .start_of_data(start_of_data),
    .end_of_data(end_of_data),
    .data_out(data_in)
);
endmodule 
