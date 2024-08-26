`timescale 1ns / 100ps
/**
 * Bulk OUT End-Point.
 *
 * Re-assembles frames with size >512B from multiple chunks, and receipt of a
 * ZDP indicates that the frame-size is a multiple of 512, generating a 'tlast'.
 */
module ep_bulk_out
  #(
    parameter USB_MAX_PACKET_SIZE = 512, // For HS-mode
    parameter PACKET_FIFO_DEPTH = 2048,
    parameter ENABLED = 1,
    parameter DUMPSTER = 1,
    parameter USE_ZDP = 0 // TODO
  )
  (
   input clock,
   input reset,

   input set_conf_i, // From CONTROL PIPE0
   input clr_conf_i, // From CONTROL PIPE0

   input selected_i, // From USB controller
   input ack_recv_i,
   input timedout_i,

   output ep_ready_o,
   output stalled_o, // If invariants violated
   output parity_o,

   // From USB/ULPI packet decoder
   input s_tvalid,
   output s_tready, // Only asserted when space for at least one packet
   input s_tlast,
   input [7:0] s_tdata,

   // To bulk data sink
   output m_tvalid, // Only asserted after CRC16 succeeds
   input m_tready,
   output m_tkeep,
   output m_tlast,
   output [7:0] m_tdata
   );

`include "usb_defs.vh"

generate if (DUMPSTER) begin : g_dumpster
  //
  //  Just dump whatever we receive
  ///
  assign ep_ready_o = 1'b1;
  assign stalled_o = 1'b0;
  assign s_tready = selected_i;
  assign m_tvalid = 1'b0;
  assign m_tlast = 1'b0;
  assign m_tkeep = 1'b0;
  assign m_tdata = 8'bx;

end else begin : g_bulk_out

  localparam [4:0] RX_HALT = 5'b00001;
  localparam [4:0] RX_FILL = 5'b00010;

  localparam [3:0] TX_IDLE = 5'b00001;
  localparam [4:0] ST_SEND = 5'b00100;
  localparam [4:0] ST_NONE = 5'b01000;
  localparam [4:0] ST_WAIT = 5'b10000;

  reg [4:0] snext, state;
  wire tvalid_w, tready_w, tlast_w, tkeep_w;
  reg parity, enabled;
  reg [3:0] pid_q;


  assign stalled_o = ~enabled;

  assign redo_w = state == ST_WAIT && timedout_i;
  assign next_w = state == ST_WAIT && ack_recv_i;

  assign tvalid_w = state == ST_SEND && s_tvalid || state == ST_NONE;
  assign s_tready = tready_w && state == ST_SEND;
  assign tkeep_w  = s_tkeep && state != ST_NONE;
  assign tlast_w  = s_tlast || state == ST_NONE;


  // -- FSM for Bulk IN Transfers -- //

  always @* begin
    snext = state;

    if (state == ST_IDLE && selected_i) begin
      snext = s_tvalid ? ST_SEND : ST_NONE;
    end
    // Transferring data from source to USB encoder.
    if (state == ST_SEND && s_tvalid && s_tlast && tready_w) begin
      snext = ST_WAIT;
    end
    // No data to send, so transmit a NAK (TODO: or ZDP)
    if (state == ST_NONE && tready_w) begin
      snext = enabled ? ST_IDLE : ST_HALT;
    end
    // After sending a packet, wait for an ACK/ERR response.
    if (state == ST_WAIT && (ack_recv_i || err_recv_i)) begin
      snext = ST_IDLE;
    end

    if (clr_conf_i) begin
      snext = ST_HALT;
    end else if (set_conf_i) begin
      snext = ST_IDLE;
    end

    // Issue STALL if we get a requested prior to being configured
    if (state == ST_HALT && selected_i) begin
      snext = ST_NONE;
    end
  end

  always @(posedge clock) begin
    if (reset || ENABLED != 1) begin
      state <= ST_HALT;
      enabled <= 1'b0;
      pid_q <= STALL;
    end else begin
      state <= snext;

      if (clr_conf_i) begin
        enabled <= 1'b0;
      end else if (set_conf_i) begin
        enabled <= 1'b1;
      end

      case (state)
        ST_HALT: pid_q <= STALL;
        ST_IDLE: begin
          // Issue NAK response unless 'Bulk IN' data is already waiting
          if (s_tvalid) begin
            pid_q <= parity ? DATA1 : DATA0;
          end else begin
            pid_q <= NAK;
          end
        end
        ST_NONE: pid_q <= pid_q;
        ST_SEND: pid_q <= pid_q;
        ST_WAIT: pid_q <= pid_q;
      endcase
    end
  end


  // -- Output Packet FIFO -- //

  packet_fifo
    #( .WIDTH(8),
       .DEPTH(PACKET_FIFO_DEPTH),
       .STORE_LASTS(1),
       .SAVE_ON_LAST(0), // save on CRC16-valid
       .NEXT_ON_LAST(1),
       .USE_LENGTH(0),
       .MAX_LENGTH(0),
       .OUTREG(2)
       )
  U_TX_FIFO1
    ( .clock(clock),
      .reset(reset),

      .level_o(level_w),

      .drop_i(1'b0),
      .save_i(1'b0),
      .redo_i(redo_w),
      .next_i(next_w),

      .valid_i(s_tvalid),
      .ready_o(tready_w),
      .last_i(s_tlast),
      .data_i(s_tdata),

      .valid_o(tvalid_w),
      .ready_i(m_tready),
      .last_o(tlast_w),
      .data_o(m_tdata)
      );


  // -- Simulation Only -- //

`ifdef __icarus

  reg [39:0] dbg_state;
  reg [47:0] dbg_pid;

  always @* begin
    case (state)
      ST_HALT: dbg_state = "HALT";
      ST_IDLE: dbg_state = "IDLE";
      ST_SEND: dbg_state = "SEND";
      ST_NONE: dbg_state = "NONE";
      ST_WAIT: dbg_state = "WAIT";
      default: dbg_state = " ?? ";
    endcase
  end

  always @* begin
    case (pid_q)
      STALL:   dbg_pid = "STALL";
      DATA0:   dbg_pid = "DATA0";
      DATA1:   dbg_pid = "DATA1";
      NAK:     dbg_pid = "NAK  ";
      default: dbg_pid = " ??? ";
    endcase
  end

`endif /* __icarus */

end  /* g_bulk_out */
endgenerate


endmodule  /* ep_bulk_out */
