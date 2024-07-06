`timescale 1ns / 100ps
/**
 * Handle the transaction-layer of the USB protocol.
 *
 * Responsible for:
 *  - selecting relevant endpoints;
 *  - controlling the MUX that feeds the packet-encoder;
 *  - generating the timeouts, as required by the USB 2.0 spec;
 *  - halting/stalling endpoints, when necessary;
 * 
 * Todo:
 *  - 'STALL' on disabled or missing end-points;
 *  - MUX-select for the end-points;
 */
module protocol
  #( parameter [3:0] BULK_EP1 = 1,
     parameter USE_EP1_IN  = 0,
     parameter USE_EP1_OUT = 1,
     parameter [3:0] BULK_EP2 = 2,
     parameter USE_EP2_IN  = 1,
     parameter USE_EP2_OUT = 0,
     parameter [3:0] BULK_EP3 = 3,
     parameter USE_EP3_IN  = 0,
     parameter USE_EP3_OUT = 0,
     parameter [3:0] BULK_EP4 = 4,
     parameter USE_EP4_IN  = 0,
     parameter USE_EP4_OUT = 0
     )
  (
   input clock,
   input reset,
   input enable,

   input set_conf_i,
   input clr_conf_i,
   input [6:0] usb_addr_i,

   // Signals from the USB packet decoder (upstream)
   input crc_error_i,
   input crc_valid_i,

   input hsk_recv_i,
   input usb_recv_i,
   input [3:0] usb_pid_i,
   input sof_recv_i,
   input eop_recv_i,
   input dec_idle_i,

   input tok_recv_i,
   input tok_ping_i,
   input [6:0] tok_addr_i,
   input [3:0] tok_endp_i,

   // ULPI encoder signals
   output hsk_send_o,
   input hsk_sent_i,
   input usb_busy_i,
   input usb_sent_i,
   output [3:0] usb_pid_o,

   // Control end-point
   input ep0_halted_i, // Useful ??
   output ep0_select_o,
   output ep0_enable_o,

   // Bulk IN/OUT end-points
   input ep1_rx_rdy_i,
   input ep1_tx_rdy_i,
   input ep1_halted_i, // Useful ??
   output ep1_enable_o,
   output ep1_select_o,

   input ep2_rx_rdy_i,
   input ep2_tx_rdy_i,
   input ep2_halted_i, // Useful ??
   output ep2_enable_o,
   output ep2_select_o,

   input ep3_rx_rdy_i,
   input ep3_tx_rdy_i,
   input ep3_halted_i, // Useful ??
   output ep3_enable_o,
   output ep3_select_o,

   input ep4_rx_rdy_i,
   input ep4_tx_rdy_i,
   input ep4_halted_i, // Useful ??
   output ep4_enable_o,
   output ep4_select_o
   );

`include "usb_defs.vh"

`ifdef __potato_tomato

  // -- End-Point Control -- //

  localparam EP1_EN = BULK_EP1 != 0 && (USE_EP1_IN || USE_EP1_OUT);
  localparam EP2_EN = BULK_EP2 != 0 && (USE_EP2_IN || USE_EP2_OUT);
  localparam EP3_EN = BULK_EP3 != 0 && (USE_EP3_IN || USE_EP3_OUT);
  localparam EP4_EN = BULK_EP4 != 0 && (USE_EP4_IN || USE_EP4_OUT);

  reg ep0_en, ep1_en, ep2_en, ep3_en, ep4_en;

  always @(posedge clock) begin
    if (reset) begin
      ep0_en <= 1'b1;
    end else if (ep0_halted_i) begin
      ep0_en <= 1'b0;
    end

    if (reset || clr_conf_i || ep1_halted_i) begin
      ep1_en <= 1'b0;
    end else if (set_conf_i) begin
      ep1_en <= EP1_EN;
    end

    if (reset || clr_conf_i || ep2_halted_i) begin
      ep2_en <= 1'b0;
    end else if (set_conf_i) begin
      ep2_en <= EP2_EN;
    end

    if (reset || clr_conf_i || ep3_halted_i) begin
      ep3_en <= 1'b0;
    end else if (set_conf_i) begin
      ep3_en <= EP3_EN;
    end

    if (reset || clr_conf_i || ep4_halted_i) begin
      ep4_en <= 1'b0;
    end else if (set_conf_i) begin
      ep4_en <= EP4_EN;
    end
  end


  // -- DATA0/1/2/M Logic -- //

  reg ep0_par_q, ep1_par_q, ep2_par_q, ep3_par_q, ep4_par_q;


  // -- Bus Turnaround Timer -- //

  //
  //  If we have sent a packet, then we require a handshake within 816 clocks,
  //  or else the packet failed to be transmitted, or the response failed to
  //  (successfully) arrive.
  //
  reg [6:0] bus_timer;
  wire timeout_w;

  localparam [6:0] MAX_TIMER = (816 / 8) - 1;

  always @(posedge clock) begin
    if (reset) begin
      bus_timer = MAX_TIMER;
    end else begin
      // Todo ...
    end
  end


  // -- End-Point Selects -- //

  //
  // Todo:
  //  - pipeline the end-point decoding ??
  //
  reg ep0_sel_q, ep1_sel_q, ep2_sel_q, ep3_sel_q, ep4_sel_q;

  always @(posedge clock) begin
    if (reset) begin
      {ep4_sel_q, ep3_sel_q, ep2_sel_q, ep1_sel_q, ep0_sel_q} <= 5'b00000;
    end else if (tok_addr_i == usb_addr_i && tok_recv_i) begin
      if (tok_endp_i == 4'h0) begin
        {ep4_sel_q, ep3_sel_q, ep2_sel_q, ep1_sel_q, ep0_sel_q} <= 5'b00001;
      end else if (EP1_EN && tok_endp_i == BULK_EP1) begin
        {ep4_sel_q, ep3_sel_q, ep2_sel_q, ep1_sel_q, ep0_sel_q} <= 5'b00010;
      end else if (EP2_EN && tok_recv_i && tok_endp_i == BULK_EP2) begin
        {ep4_sel_q, ep3_sel_q, ep2_sel_q, ep1_sel_q, ep0_sel_q} <= 5'b00100;
      end else if (EP3_EN && tok_recv_i && tok_endp_i == BULK_EP3) begin
        {ep4_sel_q, ep3_sel_q, ep2_sel_q, ep1_sel_q, ep0_sel_q} <= 5'b01000;
      end else if (EP4_EN && tok_recv_i && tok_endp_i == BULK_EP4) begin
        {ep4_sel_q, ep3_sel_q, ep2_sel_q, ep1_sel_q, ep0_sel_q} <= 5'b10000;
      end else begin
        {ep4_sel_q, ep3_sel_q, ep2_sel_q, ep1_sel_q, ep0_sel_q} <= 5'b00000;
      end
    end else if (tok_recv_i) begin
      {ep4_sel_q, ep3_sel_q, ep2_sel_q, ep1_sel_q, ep0_sel_q} <= 5'b00000;
    end
  end


  // -- FSM -- //

  //
  // Todo:
  //  - PING protocol;
  //  - track whether we have been 'PING'ed, so that we can generate 'NYET'
  //    responses, when required ??
  //  - DATAx parity;
  //  - MUX-select for 'IN' transactions;
  //  - if a packet arrives that is not valid for the state we are in, then
  //    terminate transaction and signal some kind of error ??
  //
  // Note(s):
  //  - USB spec says to ignore transaction requests if not supported
  //

  reg [7:0] state, snext;
  reg [3:0] respo, pid_q;
  reg setup, ctl_q;
  wire sel_w, hlt_w, nak_w, out_w;
  wire sel0_w, sel1_w, sel2_w, sel3_w, sel4_w;
  wire rdy1_w, rdy2_w, rdy3_w, rdy4_w;


  assign sel0_w = tok_endp_i == 4'h0 &&
                  (usb_pid_i == `USBPID_SETUP ||
                   (ep0_ctl && // Are we in a CONTROL transaction ??
                    (usb_pid_i == `USBPID_IN || usb_pid_i == `USBPID_OUT)));

  assign sel1_w = BULK_EP1 != 0 && tok_endp_i == BULK_EP1 &&
                  (USE_EP1_IN && usb_pid_i == `USBPID_IN ||
                   USE_EP1_OUT && usb_pid_i == `USBPID_OUT);
  assign rdy1_w = BULK_EP1 != 0 && tok_endp_i == BULK_EP1 &&
                  (USE_EP1_IN && usb_pid_i == `USBPID_IN && ep1_tx_rdy_i ||
                   USE_EP1_OUT && usb_pid_i == `USBPID_OUT && ep1_rx_rdy_i);

  assign sel2_w = BULK_EP2 != 0 && tok_endp_i == BULK_EP2 &&
                  (USE_EP2_IN && usb_pid_i == `USBPID_IN ||
                   USE_EP2_OUT && usb_pid_i == `USBPID_OUT);
  assign rdy2_w = BULK_EP2 != 0 && tok_endp_i == BULK_EP2 &&
                  (USE_EP2_IN && usb_pid_i == `USBPID_IN && ep2_tx_rdy_i ||
                   USE_EP2_OUT && usb_pid_i == `USBPID_OUT && ep2_rx_rdy_i);

  assign sel3_w = BULK_EP3 != 0 && tok_endp_i == BULK_EP3 &&
                  (USE_EP3_IN && usb_pid_i == `USBPID_IN ||
                   USE_EP3_OUT && usb_pid_i == `USBPID_OUT);
  assign rdy3_w = BULK_EP3 != 0 && tok_endp_i == BULK_EP3 &&
                  (USE_EP3_IN && usb_pid_i == `USBPID_IN && ep3_tx_rdy_i ||
                   USE_EP3_OUT && usb_pid_i == `USBPID_OUT && ep3_rx_rdy_i);

  assign sel4_w = BULK_EP4 != 0 && tok_endp_i == BULK_EP4 &&
                  (USE_EP4_IN && usb_pid_i == `USBPID_IN ||
                   USE_EP4_OUT && usb_pid_i == `USBPID_OUT);
  assign rdy4_w = BULK_EP4 != 0 && tok_endp_i == BULK_EP4 &&
                  (USE_EP4_IN && usb_pid_i == `USBPID_IN && ep4_tx_rdy_i ||
                   USE_EP4_OUT && usb_pid_i == `USBPID_OUT && ep4_rx_rdy_i);

  assign sel_w = sel0_w || sel1_w || sel2_w || sel3_w || sel4_w;
  assign hlt_w = !ep0_en && sel0_w || !ep1_en && sel1_w || !ep2_en && sel2_w ||
                 !ep3_en && sel3_w || !ep4_en && sel4_w;
  assign nak_w = !(sel0_w || rdy1_w || rdy2_w || rdy3_w || rdy4_w);
  assign out_w = usb_pid_i != `USBPID_IN;

  localparam ST_HALT = 0;
  localparam ST_IDLE = 1;
  localparam ST_DPID = 2; // Wait for a DATAx PID
  localparam ST_RECV = 4; // RX data from the ULPI
  localparam ST_RESP = 8; // Send a handshake
  localparam ST_FAIL = 0;
  localparam ST_SEND = 0; // Route data from EP to ULPI
  localparam ST_WAIT = 0; // Wait for USB host handshake

  reg [4:0] sel_s, sel_q;

  wire ep1_out_sel_w = BULK_EP1 != 0 && USE_EP1_OUT && tok_endp_i == BULK_EP1;
  wire ep1_par_seq_w = ep1_out_sel_w && ep1_par_q != usb_pid_i[3];
  wire ep1_out_rdy_w = ep1_out_sel_w && !ep1_halted_i && ep1_rx_rdy_i;
  wire ep1_in_sel_w = BULK_EP1 != 0 && USE_EP1_IN && tok_endp_i == BULK_EP1;
  wire ep1_in_rdy_w = ep1_in_sel_w && !ep1_halted_i && ep1_tx_rdy_i;

  wire ep2_out_sel_w = BULK_EP2 != 0 && USE_EP2_OUT && tok_endp_i == BULK_EP2;
  wire ep2_par_seq_w = ep2_out_sel_w && ep2_par_q != usb_pid_i[3];
  wire ep2_out_rdy_w = ep2_out_sel_w && !ep2_halted_i && ep2_rx_rdy_i;
  wire ep2_in_sel_w = BULK_EP2 != 0 && USE_EP2_IN && tok_endp_i == BULK_EP2;
  wire ep2_in_rdy_w = ep2_in_sel_w && !ep2_halted_i && ep2_tx_rdy_i;

  wire ep3_out_sel_w = BULK_EP3 != 0 && USE_EP3_OUT && tok_endp_i == BULK_EP3;
  wire ep3_par_seq_w = ep3_out_sel_w && ep3_par_q != usb_pid_i[3];
  wire ep3_out_rdy_w = ep3_out_sel_w && !ep3_halted_i && ep3_rx_rdy_i;
  wire ep3_in_sel_w = BULK_EP3 != 0 && USE_EP3_IN && tok_endp_i == BULK_EP3;
  wire ep3_in_rdy_w = ep3_in_sel_w && !ep3_halted_i && ep3_tx_rdy_i;

  wire ep4_out_sel_w = BULK_EP4 != 0 && USE_EP4_OUT && tok_endp_i == BULK_EP4;
  wire ep4_par_seq_w = ep4_out_sel_w && ep4_par_q != usb_pid_i[3];
  wire ep4_out_rdy_w = ep4_out_sel_w && !ep4_halted_i && ep4_rx_rdy_i;
  wire ep4_in_sel_w = BULK_EP4 != 0 && USE_EP4_IN && tok_endp_i == BULK_EP4;
  wire ep4_in_rdy_w = ep4_in_sel_w && !ep4_halted_i && ep4_tx_rdy_i;


  always @* begin
    snext = state;
    respo = pid_q;
    setup = ctl_q;

    case (state)

      ST_IDLE: begin
        if (tok_recv_i && tok_addr_i == usb_addr_i) begin
          case (usb_pid_i)
            `USBPID_SETUP: begin
              // Todo:
              //  - for any other end-point, ignore
              if (tok_endp_i == 4'h0) begin
                snext = ST_DPID;
                setup = 1'b1;
              // end else begin
              //   // Indicate that operation is unsupported
              //   snext = ST_DROP;
              //   respo = `USBPID_STALL;
              end
            end

            `USBPID_OUT: begin
              if (ep1_par_seq_w || ep2_par_seq_w || ep3_par_seq_w || ep4_par_seq_w) begin
                // Parity-bits sequence error, so we ignore the DATAx, but ACK
                // response
                snext = ST_DROP;
                respo = `USBPID_ACK;
              if (ep1_out_rdy_w || ep2_out_rdy_w || ep3_out_rdy_w || ep4_out_rdy_w) begin
                // We have space, so RX some data
                snext = ST_DPID;
              end else if (ep1_out_sel_w || ep2_out_sel_w || ep3_out_sel_w || ep4_out_sel_w) begin
                // No space, so we NAK
                snext = ST_DROP;
                respo = `USBPID_NAK;
              end else if (tok_endp_i == 4'h0 && ctl_q) begin
                // EP0 CONTROL transfers always succeed
                snext = ST_DPID;
              end
            end

            `USBPID_IN: begin
              if (ep1_in_rdy_w || ep2_in_rdy_w || ep3_in_rdy_w || ep4_in_rdy_w) begin
                // We have at least one packet ready to TX
                snext = ST_SEND;
              end else if (ep1_in_sel_w || ep2_in_sel_w || ep3_in_sel_w || ep4_in_sel_w) begin
                // Selected, but no packet is ready, so NAK
                snext = ST_RESP;
                respo = `USBPID_NAK;
              end else if (tok_endp_i == 4'h0 && ctl_q) begin
                // Let EP0 sort out this CONTROL transfer
                snext = ST_SEND;
              end
            end

            `USBPID_PING: begin
              if (ep1_out_rdy_w || ep2_out_rdy_w || ep3_out_rdy_w || ep4_out_rdy_w) begin
                snext = ST_RESP;
                respo = `USBPID_ACK;
              end else if (ep1_out_sel_w || ep2_out_sel_w || ep3_out_sel_w || ep4_out_sel_w) begin
                snext = ST_RESP;
                respo = `USBPID_NAK;
              end else if (ep0_sel_w) begin
                snext = ST_RESP;
                respo = `USBPID_ACK;
              end
            end

            default: begin
              // Ignore, and impossible to reach here
            end
          endcase

          if (tok_endp_i != 4'h0) begin
            setup = 1'b0;
          end
        end
      end

      // -- OUT and SETUP -- //

      ST_DPID: begin
        // Expecting 'DATAx' PID, after an 'OUT' or 'SETUP'
        // Todo:
        //  - check the DATA0/1 parity
        //  - if not RX-ready, respond with 'NAK'
        //  - correct response if OUT to DATAx time exceeded ??
        if (usb_recv_i) begin
          snext = par_w ? ST_RECV : ST_DUMP;
          respo = par_w ? `USBPID_ACK : (rx_rdy_w ? `USBPID_ACK : `USBPID_NAK);
        end else if (timeout_w) begin
          // OUT token to DATAx packet timeout
          snext = ST_IDLE;
        end
      end

      ST_RECV: begin
        // Wait for the packet to complete
        // Todo:
        //  - if we RX a packet that exceeds MAX_LENGTH, then we need to assert
        //    'stp' !?
        if (crc_error_i) begin
          // Ignore on data corruption, and host will retry
          snext = ST_FAIL;
        end else if (eop_recv_i) begin
          // Decoder asserts EOP only on success
          snext = ST_RESP;
          respo = `USBPID_ACK;
        end else if (len_error_w) begin
          // Don't need a separate state, because exceptional ??
          snext = ST_STOP;
        end
      end

      ST_RESP: begin
        // Send 'ACK/NAK/NYET/STALL' in response to 'DATAx'
        if (hsk_sent_i || timeout_w) begin
          snext = ST_IDLE;
        end
      end

      // -- IN -- //

      ST_SEND: begin
        // Waiting for endpoint to send 'DATAx', after an 'IN'
        // Todo:
        //  - do we check to see if the TX begins, or timeout !?
        //  - 'NAK' on timeout !?
        if (usb_sent_i) begin
          snext = ST_WAIT;
        end else if (timeout_w) begin
          snext = ST_IDLE;
        end
      end

      ST_WAIT: begin
        // Waiting for host to send 'ACK'
        // On receipt of an 'ACK', we toggle a parity-bit, or else we leave
        // them unchanged
        if (hsk_recv_i || timeout_w) begin
          snext = ST_IDLE;
        end
      end

      // -- Error Handling -- //

      ST_FAIL: begin
        if (timeout_w) begin
          snext = ST_IDLE;
        end
      end

      ST_HALT, default: begin
        // We are inactive
        // Who knows, right !?
        if (enable && set_conf_i) begin
          snext = ST_IDLE;
        end
      end

    endcase

    if (reset || !enable || big_error) begin
      snext = ST_HALT;
    end
  end


  always @(posedge clock) begin
    if (reset) begin
      state <= ST_IDLE;
      pid_q <= 4'bx;
      ctl_q <= 1'b0;
    end else begin
      state <= snext;
      pid_q <= respo;
      ctl_q <= setup;
    end
  end


  // -- Simulation Only -- //

`ifdef __icarus

  reg [47:0] dbg_pid;

  always @* begin
    case (usb_pid_i)
      `USBPID_OUT:   dbg_pid = "OUT";
      `USBPID_IN:    dbg_pid = "IN";
      `USBPID_SOF:   dbg_pid = "SOF";
      `USBPID_SETUP: dbg_pid = "SETUP";
      `USBPID_DATA0: dbg_pid = "DATA0"; 
      `USBPID_DATA1: dbg_pid = "DATA1"; 
      `USBPID_DATA2: dbg_pid = "DATA2"; 
      `USBPID_MDATA: dbg_pid = "MDATA"; 
      `USBPID_ACK:   dbg_pid = "ACK";
      `USBPID_NAK:   dbg_pid = "NAK";
      `USBPID_STALL: dbg_pid = "STALL";
      `USBPID_NYET:  dbg_pid = "NYET";
      `USBPID_PRE:   dbg_pid = "PRE";
      `USBPID_ERR:   dbg_pid = "ERR";
      `USBPID_SPLIT: dbg_pid = "SPLIT";
      `USBPID_PING:  dbg_pid = "PING";
      default:       dbg_pid = " ??? ";
    endcase
  end

`endif /* __icarus */

`endif /* __potato_tomato */


endmodule  /* protocol */
