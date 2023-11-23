`timescale 1ns / 100ps
module fake_ulpi_phy (/*AUTOARG*/);

input clock;
input reset;

output ulpi_clock_o;
input ulpi_rst_ni;
output ulpi_dir_o;
input ulpi_stp_i;
output ulpi_nxt_o;
inout [7:0] ulpi_data_io;


reg dir_q, nxt_q;
reg [7:0] tdat_q;
wire stp_w;


assign ulpi_clock_o = clock;
assign ulpi_dir_o   = dir_q;
assign ulpi_nxt_o   = nxt_q;
assign ulpi_data_io = dir_q ? tdat_q : 'bz;

assign stp_w = ulpi_stp_i;


//
// todo:
//  - prepend SYNC pattern at start of packet, and append EOP pattern after;
//  - send RX CMD to Link indicating EOP;
//  - detect Start-Of-Frame (SOF) packets (PID = 0x5), and append long EOP;
//

always @(posedge clock) begin
  if (reset) begin
    dir_q <= 1'b0;
    nxt_q <= 1'b0;
  end else begin
    if (dir_q && stp_w) begin
      // De-assert data drivers
      dir_q <= 1'b0;
      nxt_q <= 1'b0;
    end else if (!dir_q && stp_w) begin
      // Bus turnaround, send an 'RX CMD' ??
      dir_q <= 1'b1;
      nxt_q <= 1'b0;
    end
  end
end


endmodule // fake_ulpi_phy
