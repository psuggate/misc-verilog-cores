`timescale 1ns / 100ps
//
// ACDC -- (A)XI-S (C)ontroller (D)aisy-(C)hain.
//
// Ring-stop module for connecting together simple logic-core controllers,
// across an integrated circuit.
//
//
module acdc #(
parameter [7:0] ADDR = 8'hFF
) (
   input clock,
   input rst_n,

   // From upstream core
   input up_tvalid,
   output up_tready,
   input up_tlast,
   input up_tkeep,
   input [7:0] up_tdata,

   // To downstream core
   output dn_tvalid,
   input dn_tready,
   output dn_tlast,
   output dn_tkeep,
   output [7:0] dn_tdata,

   output selected_o,
   input transmit_i,
   input asbestos_i,
   output [RSB:0] recv_o,
   output [SSB:0] send_o
   );

endmodule  /* acdc */
