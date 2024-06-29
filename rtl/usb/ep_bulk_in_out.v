`timescale 1ns / 100ps
/**
 * USB End-Point (EP) for CONTROL and Bulk IN/OUT transfers.
 */
module ep_bulk_in_out
  #(
    parameter ENABLED = 1,
    parameter USE_CTL = 0,
    parameter USE_IN  = 1,
    parameter USE_OUT = 1,
    parameter USE_ZDP = 0 // TODO
  )
  (
   input clock,
   input reset,

   input set_conf_i,     // From CONTROL PIPE0
   input clr_conf_i,     // From CONTROL PIPE0

   input sel_ctl_in_i,   // From USB decoder
   input sel_ctl_out_i,
   input sel_blk_in_i,
   input sel_blk_out_i,

   output rdy_ctl_in_o,  // To USB controller
   output rdy_ctl_out_o,
   output rdy_blk_in_o,
   output rdy_blk_out_o,

   input ack_recv_i, // From USB decoder
   input err_recv_i, // From USB decoder

   // From bulk data source
   input s_tvalid,
   output s_tready,
   input s_tkeep,
   input s_tlast,
   input [7:0] s_tdata,

   // To USB/ULPI packet encoder MUX
   output m_tvalid,
   input m_tready,
   output m_tkeep,
   output m_tlast,
   output [3:0] m_tuser,
   output [7:0] m_tdata
   );

`include "usb_defs.vh"


  reg [7:0] packet_buf[0:2047];

  always @(posedge clock) begin
  end


endmodule // ep_bulk_in_out
