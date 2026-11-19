
module sync #(
  parameter DATA_SIZE =6                        // data width
)
  (
    input                           clk , 
    input                           rst ,
    input       [DATA_SIZE-1:0]     unsync_ip ,
    output  reg [DATA_SIZE-1:0]     sync_op
  ) ;


reg [DATA_SIZE-1:0]  meta_flop ;


always @ (posedge clk or negedge rst)
 begin
  if(!rst)
   begin
    meta_flop   <= 0 ;
    sync_op  <= 0 ;
   end
 else
  begin
    meta_flop  <= unsync_ip ;
    sync_op  <= meta_flop ;
  end
 end



endmodule
