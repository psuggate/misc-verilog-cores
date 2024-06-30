`timescale 1ns / 100ps
/**
 * Internal DMA for buffering and prefetching USB packet data.
 *
 * Note(s):
 *  - if transfer-size module packet-size is zero, also queues a ZDP;
 */
module packet_idma
  (
   input clock,
   input reset,

   // -- End-Point #0 -- //
   input ep0_enable_i,
   input ep0_select_i,
   input ep0_finish_i,  // On success ...
   input ep0_cancel_i,  // On failure ...
   output ep0_tx_rdy_o,
   output ep0_tx_zdp_o,
   output ep0_rx_rdy_o,

   input ep0s_tvalid_i,
   output ep0s_tready_o,
   input ep0s_tlast_i,
   input [7:0] ep0s_tdata_i,

   output ep0m_tvalid_o,
   input ep0m_tready_i,
   output ep0m_tlast_o,
   output [7:0] ep0m_tdata_o,

   // -- End-Point #1 -- //
   input ep1_enable_i,
   input ep1_select_i,
   input ep1_finish_i,  // On success ...
   input ep1_cancel_i,  // On failure ...
   output ep1_tx_rdy_o,
   output ep1_tx_zdp_o,
   output ep1_rx_rdy_o,

   input ep1s_tvalid_i,
   output ep1s_tready_o,
   input ep1s_tlast_i,
   input [7:0] ep1s_tdata_i,

   output ep1m_tvalid_o,
   input ep1m_tready_i,
   output ep1m_tlast_o,
   output [7:0] ep1m_tdata_o,

   // -- End-Point #2 -- //
   input ep2_enable_i,
   input ep2_select_i,
   input ep2_finish_i,  // On success ...
   input ep2_cancel_i,  // On failure ...
   output ep2_tx_rdy_o,
   output ep2_tx_zdp_o,
   output ep2_rx_rdy_o,

   input ep2s_tvalid_i,
   output ep2s_tready_o,
   input ep2s_tlast_i,
   input [7:0] ep2s_tdata_i,

   output ep2m_tvalid_o,
   input ep2m_tready_i,
   output ep2m_tlast_o,
   output [7:0] ep2m_tdata_o,

   // -- To the ULPI Encoder -- //
   output enc_tvalid_o,
   input enc_tready_i,
   output enc_tkeep_o,
   output enc_tlast_o,
   output [3:0] enc_tuser_o,
   output [7:0] enc_tdata_o,

   // -- From the ULPI Decoder -- //
   input dec_tvalid_i,
   output dec_tready_o,
   input dec_tkeep_i,
   input dec_tlast_i,
   input [3:0] dec_tuser_i,
   input [7:0] dec_tdata_i,

   // -- USB controller signals -- //
   input usb_enable_i,
   input [6:0] usb_addr_i,
   input [3:0] usb_endp_i
   );


  reg ep1_rx_rdy, ep1_tx_rdy;
  reg ep1_rx_bank, ep1_tx_bank;
  reg [8:0] ep1_rx_addr, ep1_tx_addr;
  reg [7:0] ep1_rx_sram [0:1023]; // 2x max-packets
  reg [7:0] ep1_tx_sram [0:1023]; // 2x max-packets

  reg [7:0] ep2_rx_sram [0:1023]; // 2x max-packets
  reg [7:0] ep2_tx_sram [0:1023]; // 2x max-packets


  // EP0 prefetch buffer, with max-packet size of 64 bytes.
  prefetch_buffer
    #( .LENGTH(64),
       .WIDTH(8)
       )
  PB0
    (
     .clock(clock),
     .reset(reset)
     );

  // EP1 prefetch buffer, with max-packet size of 512 bytes.
  prefetch_buffer
    #( .LENGTH(512),
       .WIDTH(8)
       )
  PB1
    (
     .clock(clock),
     .reset(reset)
     );

  // EP2 prefetch buffer, with max-packet size of 512 bytes.
  prefetch_buffer
    #( .LENGTH(512),
       .WIDTH(8)
       )
  PB2
    (
     .clock(clock),
     .reset(reset)
     );


endmodule  /* packet_idma */
