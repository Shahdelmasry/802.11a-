module fifo_rd #(
  parameter P_SIZE = 6                         // pointer width
)
  (
   input  wire                     clk,              // read domian operating clock
   input  wire                     rst,             // read domian active low reset 
   input  wire                     ren,              // read control signal 
   input  wire   [P_SIZE-1:0]      sync_wr_ptr,        // synced gray coded write pointer         
   output wire   [P_SIZE-2:0]      rd_addr,            // generated binary read address
   output wire                     empty,              // fifo empty flag
   output reg    [P_SIZE-1:0]      gray_rd_ptr         // generated gray coded write address

);

reg [P_SIZE-1:0]  rd_ptr ;

wire [P_SIZE-1:0]  comb_gray_rd_ptr ;


assign comb_gray_rd_ptr = rd_ptr ^ (rd_ptr >> 1);

// increment binary pointer
always @(posedge clk or negedge rst)
 begin
  if(!rst)
   begin
    rd_ptr <= 0 ;
   end
 else if (!empty && ren)
    rd_ptr <= rd_ptr + 1 ;
 end


// generation of read address
assign rd_addr = rd_ptr[P_SIZE-2:0] ;

// converting binary read pointer to gray coded
always @(posedge clk or negedge rst)
begin
 if(!rst)
   begin
    gray_rd_ptr <= 0 ;
   end
 else 
  begin
   gray_rd_ptr <= comb_gray_rd_ptr;
  end
 end


// generation of empty flag
assign empty = (sync_wr_ptr == comb_gray_rd_ptr) ;

endmodule
