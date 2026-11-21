module TX_TOP  #(
    parameter DATA_WIDTH = 16,  
    parameter GAP_CLK    = 1280 
) (
 // ================= MAC side (w_clk domain) =================
    input  wire        w_clk,
    input  wire        w_rstn,                 
    input  wire [34:0] TXVECTOR,               
    input  wire [7:0]  PHY_DATA_req,           
    input  wire        PHY_TXEND_req,          
    output wire        PHY_TXSTART_conf,       
    output wire        PHY_DATA_conf,          
    output wire        PHY_TXEND_CONF,         

 // ================= PHY side (r_clk domain)===================
    input  wire        r_clk,                  
    input  wire        r_rstn,                 
    output wire [DATA_WIDTH-1:0] DAC_DATA_I,   
    output wire [DATA_WIDTH-1:0] DAC_DATA_Q    
);

wire        header_valid;   
wire        vec_err;        
wire [5:0]  data;           
wire        data_valid;     
wire        data_last;      
wire        data_ready;     
wire        abort;          
wire        flushing;       
wire        txend_pulse;    
wire        fifo_busy;
wire        tx_clear;       
wire        il_start;       
wire        scr_enable;     
wire [6:0]  scr_seed;       
wire        scr_bypass;     
wire [1:0]  coding_rate;    
wire [1:0]  modulation;     
wire        seed_sel;
wire        packet_end;     
wire [5:0]  data_in;        
wire [5:0]  tail_mask;      
wire [5:0]  scr_in;         
wire [5:0]  scr_tail;       
wire        data_req;       
wire        in_ready;       
wire        il_busy;        
wire        cfg_err;        
wire [1:0]  preamb_mux_sel;
wire        rom_rd_en;
wire [8:0]  rom_addr;
wire        rom_ready;
wire        tx_start;
wire        ifft_mode;
wire        pkt_last;       
wire        mapper_capture_ready;
wire        mapper_valid;   
wire        mapper_last;    
wire        tx_done;
wire        input_wr_en;
wire        input_rd_en;
wire [11:0] Length;
wire [3:0]  rate;
wire [8:0]  ndbps;
wire [5:0]  nwords;         
wire [1:0]  data_coding_rate;  
wire [1:0]  data_modulation;   
wire [5:0]  mux1,mux2,mux3,mux4,signal_sr;
wire [1:0]  signal_sel;     
wire        address_count_en;
wire        in_psdu, in_tail, end_of_data, count_en;   
wire        fill_done, last_sym;                       
wire [6:0]  sym_seed;                                  
wire [10:0] sym_count;                                 
wire [10:0] nsym;                                      
wire        nsym_valid;                                
wire        pkt_abort;                                 


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
    .rate(rate),
    .length(Length),
    .rate_length_valid(header_valid),   
    .vec_err(vec_err),
    .data(data),
    .data_valid(data_valid),
    .data_last(data_last),              
    .abort(abort),
    .flushing(flushing),
    .txend_pulse(txend_pulse),
    .busy(fifo_busy),
    .data_ready(data_ready),            
    .phy_tx_done(tx_done)
);

Top_Wrapper_Tx #(                       
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
    .packet_end(packet_end),           
    .seed_sel(seed_sel),
    .data_in(scr_in),
    .tail_mask(scr_tail),              
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
    .mapper_valid(mapper_valid),        
    .mapper_last(mapper_last),
    .tx_done(tx_done),
    .dac_data_i(DAC_DATA_I),
    .dac_data_q(DAC_DATA_Q)
);

TX_CONTROLLER #(
    .GAP_CLK(GAP_CLK)
) tx_controller_inst(
    .clk(r_clk),                        
    .rst_n(r_rstn),
    .fifo_header_valid(header_valid),
    .abort(abort),
    .rom_ready(rom_ready),
    .rom_addr(rom_addr),
    .data_req(data_req),
    .in_ready(in_ready),
    .mapper_capture_ready(mapper_capture_ready),
    .sym_count(sym_count),
    .nwords(nwords),
    .data_coding_rate(data_coding_rate),
    .data_modulation(data_modulation),
    .fill_done(fill_done),
    .last_sym(last_sym),
    .sym_seed(sym_seed),
    .tx_done(tx_done),
    .tx_start(tx_start),
    .tx_clear(tx_clear),
    .il_start(il_start),
    .scr_en(scr_enable),
    .seed_sel(seed_sel),
    .ifft_mode(ifft_mode),
    .rom_read_en(rom_rd_en),
    .address_count_en(address_count_en),
    .preamb_mux_en(preamb_mux_sel),
    .signal_mux_en(scr_bypass),
    .signal_sel(signal_sel),            
    .input_wr_en(input_wr_en),
    .input_rd_en(input_rd_en),
    .coding_rate(coding_rate),          
    .modulation(modulation),
    .scr_seed(scr_seed),
    .packet_end(packet_end),
    .nsym(nsym),
    .nsym_valid(nsym_valid),
    .pkt_abort(pkt_abort)
);

signal_field_generation SFG_inst (
    .clk(r_clk),
    .rst(r_rstn),
    .load(tx_start),                    
    .rate(rate),
    .Length(Length),
    .ndbps(ndbps),
    .nwords(nwords),
    .coding_rate(data_coding_rate),     
    .modulation(data_modulation),
    .Signal1(mux1),
    .Signal2(mux2),
    .Signal3(mux3),
    .Signal4(mux4)
);

data_counter data_counter_inst (
    .clk(r_clk),
    .reset(r_rstn),                     
    .clear(tx_start),
    .enable(count_en),                  
    .Length(Length),
    .in_psdu(in_psdu),
    .in_tail(in_tail),
    .end_of_data(end_of_data)
);

input_buffer input_buffer_inst(
    .clk(r_clk),
    .rst(r_rstn),
    .start(tx_start),
    .abort(pkt_abort),
    .wr_en(input_wr_en),
    .read_en(input_rd_en),              
    .ndbps(ndbps),
    .wr_data(data),
    .wr_valid(data_valid),
    .wr_ready(data_ready),
    .in_psdu(in_psdu),
    .in_tail(in_tail),
    .end_of_data(end_of_data),
    .count_en(count_en),
    .data_out(data_in),
    .tail_mask(tail_mask),
    .sym_seed(sym_seed),
    .fill_done(fill_done),
    .last_sym(last_sym)
);

symbol_counter symbol_counter_inst(     
    .clk(r_clk),
    .rst(r_rstn),
    .clear(tx_start),
    .nsym(nsym),
    .nsym_valid(nsym_valid),
    .symbol_valid(mapper_valid),        
    .last_valid(mapper_last),
    .mapper_capture_ready(mapper_capture_ready),
    .last_sym(pkt_last),
    .sym_count(sym_count)
);

address_counter add_cnt_inst(
    .clk(r_clk),
    .rst(r_rstn),
    .clear(tx_start),                   
    .en(address_count_en),
    .add_count(rom_addr)
);

mux4to1 mux (
    .mux1(mux1),
    .mux2(mux2),
    .mux3(mux3),
    .mux4(mux4),
    .sel(signal_sel),
    .muxout(signal_sr)
);
assign scr_in   = scr_bypass ? signal_sr : data_in;
assign scr_tail = scr_bypass ? 6'd0      : tail_mask;   

endmodule
