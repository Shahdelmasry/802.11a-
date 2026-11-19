
module fifo_wr #(
  parameter P_SIZE = 6                          // pointer width
)
  (
   input  wire                    clk,              // mac clock
   input  wire                    rst,             
   input  wire                    wen,              // write control signal 
   input  wire  [P_SIZE-1:0]      sync_rd_ptr,        // synced gray coded read pointer         
   output wire  [P_SIZE-2:0]      w_addr,             // generated binary write address
   output reg   [P_SIZE-1:0]      gray_w_ptr,         // generated gray coded write address 
   output wire                    full                // fifo full flag

);

reg [P_SIZE-1:0]  w_ptr ;

wire [P_SIZE-1:0]  comb_gray_w_ptr ;


assign comb_gray_w_ptr = w_ptr ^ (w_ptr >> 1);

// increment binary pointer
always @(posedge clk or negedge rst)
 begin
  if(!rst)
   begin
    w_ptr <= 0 ;
   end
 else if (!full && wen)
    w_ptr <= w_ptr + 1 ;
 end


// generation of write address
assign w_addr = w_ptr[P_SIZE-2:0] ;

// converting binary write pointer to gray coded
always @(posedge clk or negedge rst)
 begin
  if(!rst)
   begin
    gray_w_ptr <= 0 ;
   end
 else
  begin
   gray_w_ptr <= comb_gray_w_ptr;
  end
 end


// generation of full flag
assign full = (sync_rd_ptr[P_SIZE-1]!= comb_gray_w_ptr[P_SIZE-1] && sync_rd_ptr[P_SIZE-2]!= comb_gray_w_ptr[P_SIZE-2] && sync_rd_ptr[P_SIZE-3:0]== comb_gray_w_ptr[P_SIZE-3:0]) ;



endmodule

