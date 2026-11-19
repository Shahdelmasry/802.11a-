module write_ctrl (
    input  wire        clk,
    input  wire        rst,                // active-low async

    // MAC side
    input  wire [34:0] TXVECTOR,           // [34:23]=LENGTH [22:19]=RATE [18:3]=SERVICE [2:0]=TXPWR
    input  wire [7:0]  data_request,
    input  wire        PHY_TXEND_req,      // PHY-TXEND.request (pulse)
    output reg         PHY_TXSTART_conf,   // pulse
    output reg         data_confirm,
    output reg         PHY_TXEND_CONF,     
    // FIFO side
    input  wire        full,
    output wire        wen,
    output wire [7:0]  fifo_wdata,

    // Read side
    input  wire        txend_pulse,        
    output reg         abort_req           
);

// States
localparam [2:0] idle       = 3'd0,
                 w_1        = 3'd1,
                 w_2        = 3'd2,
                 w_3        = 3'd3,
                 w_data     = 3'd4,
                 wait_txend = 3'd5,
                 abort_dly  = 3'd6,
                 abort_wait = 3'd7;

// Internal signals
wire [11:0] tv_length = TXVECTOR[34:23];
wire [3:0]  tv_rate   = TXVECTOR[22:19];
wire [2:0]  tv_txpwr  = TXVECTOR[2:0];

// Registers
reg [2:0]  crnt_st, nxt_st;
reg [3:0]  rate_q;
reg [2:0]  pwr_q;
reg [11:0] len_q, wcnt;
reg [7:0]  vector_byte;
reg        req_q;
reg        abort_pending;    
reg        txend_seen;        
reg [2:0]  dly;

// Request detection
wire req   = (tv_length != 0);
wire start = req && !req_q && (crnt_st == idle);


wire in_tx = (crnt_st == w_1) || (crnt_st == w_2) || (crnt_st == w_3) ||
             (crnt_st == w_data) || (crnt_st == wait_txend);
wire abort_set = PHY_TXEND_req && in_tx;
wire abort_now = abort_pending || abort_set;

// Vector states
wire input_state = (crnt_st == w_1) || (crnt_st == w_2) || (crnt_st == w_3);
wire enable      = input_state && !full;

// Vector byte selection
always @(*) begin
    case (crnt_st)
        w_1:     vector_byte = {4'b0000, rate_q};
        w_2:     vector_byte = {1'b0, pwr_q, len_q[11:8]};
        w_3:     vector_byte = len_q[7:0];
        default: vector_byte = 8'b0;
    endcase
end


always @(*) begin
    data_confirm = (crnt_st == w_data) && !full && (wcnt < len_q) && !abort_now;
end

// FIFO write control
assign wen        = enable || data_confirm;
assign fifo_wdata = input_state ? vector_byte : data_request;


wire fin_normal = (crnt_st == wait_txend) && txend_pulse;
wire fin_abort  = (crnt_st == abort_wait) && (txend_pulse || txend_seen);

// State register
always @(posedge clk or negedge rst) begin
    if (!rst) crnt_st <= idle;
    else      crnt_st <= nxt_st;
end

// Next state logic
always @(*) begin
    nxt_st = crnt_st;
    case (crnt_st)
        idle:       if (start) nxt_st = w_1;

        w_1:        if (enable) nxt_st = w_2;
        w_2:        if (enable) nxt_st = w_3;
        w_3:        if (enable) nxt_st = abort_now ? abort_dly : w_data;

        w_data:     if (abort_now)             nxt_st = abort_dly;
                    else if (wcnt == len_q)    nxt_st = wait_txend;

        wait_txend: if (txend_pulse)           nxt_st = idle;
                    else if (abort_now)        nxt_st = abort_dly;

        abort_dly:  if (dly == 3'd3)           nxt_st = abort_wait;

        abort_wait: if (txend_pulse || txend_seen) nxt_st = idle;

        default: nxt_st = idle;
    endcase
end

// Registers and control outputs
always @(posedge clk or negedge rst) begin
    if (!rst) begin
        rate_q <= 0; pwr_q <= 0; len_q <= 0; wcnt <= 0; req_q <= 0;
        abort_pending <= 0; txend_seen <= 0; dly <= 0; abort_req <= 0;
        PHY_TXEND_CONF <= 0; PHY_TXSTART_conf <= 0;
    end else begin
        req_q            <= req;
        PHY_TXSTART_conf <= 1'b0;
        PHY_TXEND_CONF   <= 1'b0;

        // Capture TXVECTOR once
        if (start) begin
            rate_q <= tv_rate;
            pwr_q  <= tv_txpwr;
            len_q  <= tv_length;
            wcnt   <= 0;
            abort_pending <= 1'b0;
            txend_seen    <= 1'b0;
        end

        if (abort_set) abort_pending <= 1'b1;

        // Count accepted payload bytes
        if (data_confirm) wcnt <= wcnt + 1'b1;

        if ((crnt_st == w_3) && enable && !abort_now)
            PHY_TXSTART_conf <= 1'b1;

        if (crnt_st == abort_dly) begin
            dly <= dly + 1'b1;
            if (txend_pulse) txend_seen <= 1'b1;
            if (dly == 3'd3 && !txend_seen && !txend_pulse) abort_req <= 1'b1;
        end else begin
            dly <= 3'd0;
        end

        if (fin_normal || fin_abort) begin
            PHY_TXEND_CONF <= 1'b1;
            abort_req      <= 1'b0;
            abort_pending  <= 1'b0;
            txend_seen     <= 1'b0;
        end
    end
end

endmodule
