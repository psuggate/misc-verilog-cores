`timescale 1ns / 100ps
/**
 * Handle the transaction-layer of the USB protocol.
 *
 * Responsible for:
 *  - selecting relevant endpoints;
 *  - checking DATAx parity/sequence bits;
 *  - controlling the MUX that feeds the packet-encoder;
 *  - generating the timeouts, as required by the USB 2.0 spec;
 * 
 * Todo:
 *  - registered/pipelined EP-selects;
 *  - MUX-select for the end-points;
 */
module protocol #(
    parameter [3:0] BULK_EP1 = 1,
    parameter USE_EP1_IN = 0,
    parameter USE_EP1_OUT = 1,
    parameter [3:0] BULK_EP2 = 2,
    parameter USE_EP2_IN = 1,
    parameter USE_EP2_OUT = 0,
    parameter [3:0] BULK_EP3 = 3,
    parameter USE_EP3_IN = 0,
    parameter USE_EP3_OUT = 0,
    parameter [3:0] BULK_EP4 = 4,
    parameter USE_EP4_IN = 0,
    parameter USE_EP4_OUT = 0
) (
    input clock,
    input reset,

    input [1:0] RxEvent,
    output timedout_o,

    input set_conf_i,
    input clr_conf_i,
    input [6:0] usb_addr_i,

    // Signals from the USB packet decoder (upstream)
    input crc_error_i,

    input hsk_recv_i,
    input usb_recv_i,
    input [3:0] usb_pid_i,
    input eop_recv_i,

    input tok_recv_i,
    input tok_ping_i,
    input [6:0] tok_addr_i,
    input [3:0] tok_endp_i,

    // ULPI encoder signals
    output hsk_send_o,
    input  hsk_sent_i,
    input  usb_busy_i,
    input  usb_sent_i,

    output mux_enable_o,
    output [2:0] mux_select_o,
    output [3:0] ulpi_tuser_o,

    // Control end-point
    input ep0_select_i,
    input ep0_parity_i,
    input ep0_finish_i,

    // Bulk IN/OUT end-points
    input  ep1_rx_rdy_i,
    input  ep1_tx_rdy_i,
    input  ep1_parity_i,
    input  ep1_halted_i,
    output ep1_select_o,
    output ep1_finish_o,

    input  ep2_rx_rdy_i,
    input  ep2_tx_rdy_i,
    input  ep2_parity_i,
    input  ep2_halted_i,
    output ep2_select_o,
    output ep2_finish_o,

    input  ep3_rx_rdy_i,
    input  ep3_tx_rdy_i,
    input  ep3_parity_i,
    input  ep3_halted_i,
    output ep3_select_o,
    output ep3_finish_o,

    input  ep4_rx_rdy_i,
    input  ep4_tx_rdy_i,
    input  ep4_parity_i,
    input  ep4_halted_i,
    output ep4_select_o,
    output ep4_finish_o
);

  `include "usb_defs.vh"

  reg ep1_en, ep2_en, ep3_en, ep4_en;
  reg ep0_sel_q, ep1_sel_q, ep2_sel_q, ep3_sel_q, ep4_sel_q;
  reg ep0_ack_q, ep1_ack_q, ep2_ack_q, ep3_ack_q, ep4_ack_q;
  reg end_q, hsk_q;
  reg [3:0] pid_c, pid_q;
  reg [5:0] state, snext;
  reg [6:0] bus_timer;
  reg timeout_q = 1'b0;
  wire par_w, len_error_w;

  reg mux_q;
  reg [2:0] sel_q;
  wire seq_w;
  wire [3:0] pid_w;

  assign timedout_o   = timeout_q;

  assign mux_enable_o = mux_q;
  assign mux_select_o = sel_q;
  assign ulpi_tuser_o = pid_q;

  assign hsk_send_o   = hsk_q;

  assign ep1_select_o = ep1_sel_q;
  assign ep2_select_o = ep2_sel_q;
  assign ep3_select_o = ep3_sel_q;
  assign ep4_select_o = ep4_sel_q;

  assign ep1_finish_o = ep1_ack_q;
  assign ep2_finish_o = ep2_ack_q;
  assign ep3_finish_o = ep3_ack_q;
  assign ep4_finish_o = ep4_ack_q;

  // -- End-Point Control -- //

  localparam EP1_EN = BULK_EP1 != 0 && (USE_EP1_IN || USE_EP1_OUT);
  localparam EP2_EN = BULK_EP2 != 0 && (USE_EP2_IN || USE_EP2_OUT);
  localparam EP3_EN = BULK_EP3 != 0 && (USE_EP3_IN || USE_EP3_OUT);
  localparam EP4_EN = BULK_EP4 != 0 && (USE_EP4_IN || USE_EP4_OUT);

  always @(posedge clock) begin
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

  // -- End-Point Readies & Selects -- //

  // Deselect all of the end-points at the end of each transaction, due to a
  // configuration event, on reset, or on error.
  always @(posedge clock) begin
    if (reset || clr_conf_i || hsk_recv_i || hsk_sent_i || timeout_q) begin
      end_q <= 1'b1;
    end else begin
      end_q <= 1'b0;
    end
  end

  // An end-point remains selected from when an appropriate token is received,
  // until the of the transaction.
  always @(posedge clock) begin
    if (end_q) begin
      {ep4_sel_q, ep3_sel_q, ep2_sel_q, ep1_sel_q, ep0_sel_q} <= 5'b00000;
    end else if (tok_addr_i == usb_addr_i && tok_recv_i) begin
      case (tok_endp_i)
        4'h0: {ep4_sel_q, ep3_sel_q, ep2_sel_q, ep1_sel_q, ep0_sel_q} <= 5'b00001;

        BULK_EP1: begin
          {ep4_sel_q, ep3_sel_q, ep2_sel_q, ep1_sel_q, ep0_sel_q} <= {3'b000, ep1_en, 1'b0};
        end

        BULK_EP2: begin
          {ep4_sel_q, ep3_sel_q, ep2_sel_q, ep1_sel_q, ep0_sel_q} <= {2'b00, ep2_en, 2'b00};
        end

        BULK_EP3: begin
          {ep4_sel_q, ep3_sel_q, ep2_sel_q, ep1_sel_q, ep0_sel_q} <= {1'b0, ep3_en, 3'b000};
        end

        BULK_EP4: begin
          {ep4_sel_q, ep3_sel_q, ep2_sel_q, ep1_sel_q, ep0_sel_q} <= {ep4_en, 4'b0000};
        end

        default: begin
          {ep4_sel_q, ep3_sel_q, ep2_sel_q, ep1_sel_q, ep0_sel_q} <= 5'b00000;
        end
      endcase
    end
  end

  always @(posedge clock) begin
    if (end_q) begin
      {ep4_ack_q, ep3_ack_q, ep2_ack_q, ep1_ack_q} <= 4'b0000;
    end else begin
      ep1_ack_q <= ep1_sel_q && ((USE_EP1_OUT && hsk_sent_i) || (USE_EP1_IN && hsk_recv_i));
      ep2_ack_q <= ep2_sel_q && ((USE_EP2_OUT && hsk_sent_i) || (USE_EP2_IN && hsk_recv_i));
      ep3_ack_q <= ep3_sel_q && ((USE_EP3_OUT && hsk_sent_i) || (USE_EP3_IN && hsk_recv_i));
      ep4_ack_q <= ep4_sel_q && ((USE_EP4_OUT && hsk_sent_i) || (USE_EP4_IN && hsk_recv_i));
    end
  end

  //
  // Todo:
  //  - NYET responses for PING protocol:
  //     + generate when EP ready deasserts, during DATAx Tx/Rx;
  //     + track whether we have been 'PING'ed, so that we can generate 'NYET'
  //       responses, when required;
  //  - MUX-select for 'IN' transactions;
  //  - if a packet arrives that is not valid for the state we are in, then
  //    terminate transaction and signal/track some kind of error ??
  //
  // Note(s):
  //  - USB spec says to ignore transaction requests if not supported
  //
  wire ep0_out_sel_w = tok_endp_i == 4'h0;

  wire ep1_out_sel_w = ep1_en && USE_EP1_OUT && tok_endp_i == BULK_EP1;
  wire ep1_out_rdy_w = ep1_out_sel_w && !ep1_halted_i && ep1_rx_rdy_i;
  wire ep1_in_sel_w = BULK_EP1 != 0 && USE_EP1_IN && tok_endp_i == BULK_EP1;
  wire ep1_in_rdy_w = ep1_in_sel_w && !ep1_halted_i && ep1_tx_rdy_i;

  wire ep2_out_sel_w = ep2_en && USE_EP2_OUT && tok_endp_i == BULK_EP2;
  wire ep2_out_rdy_w = ep2_out_sel_w && ep2_rx_rdy_i;
  wire ep2_in_sel_w = ep2_en && USE_EP2_IN && tok_endp_i == BULK_EP2;
  wire ep2_in_rdy_w = ep2_in_sel_w && ep2_tx_rdy_i;

  wire ep3_out_sel_w = ep3_en && USE_EP3_OUT && tok_endp_i == BULK_EP3;
  wire ep3_out_rdy_w = ep3_out_sel_w && ep3_rx_rdy_i;
  wire ep3_in_sel_w = ep3_en && USE_EP3_IN && tok_endp_i == BULK_EP3;
  wire ep3_in_rdy_w = ep3_in_sel_w && ep3_tx_rdy_i;

  wire ep4_out_sel_w = ep4_en && USE_EP4_OUT && tok_endp_i == BULK_EP4;
  wire ep4_out_rdy_w = ep4_out_sel_w && ep4_rx_rdy_i;
  wire ep4_in_sel_w = ep4_en && USE_EP4_IN && tok_endp_i == BULK_EP4;
  wire ep4_in_rdy_w = ep4_in_sel_w && ep4_tx_rdy_i;

  wire out_sel_w = ep0_out_sel_w | ep1_out_sel_w | ep2_out_sel_w | ep3_out_sel_w | ep4_out_sel_w;
  wire out_rdy_w = ep1_out_rdy_w | ep2_out_rdy_w | ep3_out_rdy_w | ep4_out_rdy_w;
  wire in_sel_w = ep1_in_sel_w | ep2_in_sel_w | ep3_in_sel_w | ep4_in_sel_w;
  wire in_rdy_w = ep1_in_rdy_w | ep2_in_rdy_w | ep3_in_rdy_w | ep4_in_rdy_w;

  // -- DATAx Parity-Checking for the Sequence Bits -- //

  wire ep0_par_w = ep0_select_i && ep0_parity_i == usb_pid_i[3];
  wire ep1_par_w = ep1_out_sel_w && ep1_parity_i == usb_pid_i[3];
  wire ep2_par_w = ep2_out_sel_w && ep2_parity_i == usb_pid_i[3];
  wire ep3_par_w = ep3_out_sel_w && ep3_parity_i == usb_pid_i[3];
  wire ep4_par_w = ep4_out_sel_w && ep4_parity_i == usb_pid_i[3];

  assign par_w = ep0_par_w | ep1_par_w | ep2_par_w | ep3_par_w | ep4_par_w;
  assign seq_w = tok_endp_i == 0 ? ep0_parity_i :
                 tok_endp_i == BULK_EP1 ? ep1_parity_i :
                 tok_endp_i == BULK_EP2 ? ep2_parity_i :
                 tok_endp_i == BULK_EP3 ? ep3_parity_i :
                 tok_endp_i == BULK_EP4 ? ep4_parity_i : 1'bx ;
  assign pid_w = seq_w ? `USBPID_DATA1 : `USBPID_DATA0;


  // -- FSM -- //

  localparam [5:0] ST_IDLE = 1;
  localparam [5:0] ST_RECV = 2;  // RX data from the ULPI
  localparam [5:0] ST_RESP = 4;  // Send a handshake to USB host
  localparam [5:0] ST_DROP = 8;  // Wait for EOP, and then no response
  localparam [5:0] ST_SEND = 16;  // Route data from EP to ULPI
  localparam [5:0] ST_WAIT = 32;  // Wait for USB host handshake

  always @* begin
    snext = state;
    pid_c = pid_q;

    case (state)

      ST_IDLE: begin
        if (tok_recv_i && tok_addr_i == usb_addr_i) begin
          // Todo:
          //  - for any missing/other end-point, ignore; OR,
          //  - issue 'STALL' for unsupported IN/OUT & EP pairing?
          case (usb_pid_i)
            `USBPID_SETUP: begin
              if (tok_endp_i == 4'h0) begin
                snext = ST_RECV;
              end else begin
                // Indicate that operation is unsupported
                snext = ST_DROP;
                pid_c = `USBPID_STALL;
              end
            end

            `USBPID_OUT:
            if (ep0_select_i) begin
              // EP0 CONTROL transfers always succeed
              snext = ST_RECV;
            end else if (out_sel_w) begin
              if (out_rdy_w) begin
                // We have space, so RX some data
                snext = ST_RECV;
              end else begin
                // No space, so we NAK
                snext = ST_DROP;
                pid_c = `USBPID_NAK;
              end
            end else begin
              snext = ST_DROP;
              pid_c = `USBPID_STALL;
            end

            `USBPID_IN: begin
              pid_c = pid_w;
              if (ep0_select_i) begin
                // Let EP0 sort out this CONTROL transfer
                snext = ST_SEND;
              end else if (in_sel_w) begin
                if (in_rdy_w) begin
                  // We have at least one packet ready to TX
                  snext = ST_SEND;
                end else begin
                  // Selected, but no packet is ready, so NAK
                  snext = ST_RESP;
                  pid_c = `USBPID_NAK;
                end
              end else begin
                snext = ST_WAIT;
              end
            end

            `USBPID_PING: begin
              snext = ST_RESP;
              if (ep0_select_i) begin
                pid_c = `USBPID_ACK;
              end else if (out_sel_w) begin
                pid_c = out_rdy_w ? `USBPID_ACK : `USBPID_NAK;
              end else begin
                pid_c = `USBPID_STALL;
              end
            end

            default: begin
              // Ignore, and impossible to reach here
              snext = 'bx;
              pid_c = 'bx;
            end
          endcase

        end
      end

      // -- OUT and SETUP -- //

      ST_RECV:
      if (usb_recv_i) begin
        // Expecting 'DATAx' PID, after an 'OUT' or 'SETUP'
        // If parity-bits sequence error, we ignore the DATAx, but ACK response,
        // or else receive as usual.
        snext = par_w ? ST_RESP : ST_IDLE;
        pid_c = `USBPID_ACK;
      end else if (timeout_q || crc_error_i || len_error_w) begin
        // OUT token to DATAx packet timeout
        // Ignore on data corruption, and host will retry
        snext = ST_IDLE;
      end

      ST_RESP:
      if (hsk_sent_i || timeout_q) begin
        // Send 'ACK/NAK/NYET/STALL' in response to 'DATAx'
        snext = ST_IDLE;
      end

      // -- IN -- //

      ST_SEND:
      if (usb_sent_i) begin
        // Waiting for endpoint to send 'DATAx', after an 'IN'
        // Todo:
        //  - do we check to see if the TX begins, or timeout !?
        //  - 'NAK' on timeout !?
        snext = ST_WAIT;
      end else if (timeout_q) begin
        // Internal error, as a device end-point timed-out, after it signalled
        // that it was ready, so we 'HALT' the endpoint (after some number of
        // attempts).
        // Todo:
        //  - halt failing end-points ??
        snext = ST_IDLE;
        // snext = ST_RESP;
        // pid_c = `USBPID_STALL;
      end

      ST_WAIT:
      if (hsk_recv_i || timeout_q) begin
        // Waiting for host to send 'ACK', or waiting for bus turnaround timer
        // to elapse, for an unsupported request.
        snext = ST_IDLE;
      end

      // -- Error Handling -- //

      ST_DROP:
      if (eop_recv_i) begin
        // Todo: wait for timeout ??
        snext = ST_IDLE;
      end

      default: begin
        // Todo: is this circuit okay?
        snext = 'bx;  // ST_IDLE;
      end

    endcase
  end

  always @(posedge clock) begin
    if (reset) begin
      state <= ST_IDLE;
      pid_q <= 4'bx;
      mux_q <= 1'b0;
    end else begin
      state <= snext;
      pid_q <= pid_c;

      mux_q <= state == ST_SEND || state == ST_WAIT;
      case (tok_endp_i)
        4'h0:     sel_q <= 3'h0;
        BULK_EP1: sel_q <= 3'h1;
        BULK_EP2: sel_q <= 3'h2;
        BULK_EP3: sel_q <= 3'h3;
        BULK_EP4: sel_q <= 3'h4;
        default:  sel_q <= 3'h7;
      endcase
    end
  end

  // Send a handshake packet, and after either a token, or a DATAx packet has
  // been received
  always @(posedge clock) begin
    if (reset) begin
      hsk_q <= 1'b0;
    end else begin
      case (state)
        ST_IDLE: begin
          hsk_q <= tok_recv_i && tok_addr_i == usb_addr_i && usb_pid_i == `USBPID_PING;
        end

        ST_RECV:
        if (usb_recv_i && par_w) begin
          hsk_q <= 1'b1;
        end

        ST_RESP:
        if (hsk_sent_i) begin
          hsk_q <= 1'b0;
        end

        default: begin
          hsk_q <= 1'b0;
        end
      endcase
    end
  end


  //
  //  USB Protocol Timers
  ///

  // -- Bus Turnaround Timer -- //

  //
  //  If we have sent a packet, then we require a handshake within 816 clocks,
  //  or else the packet failed to be transmitted, or the response failed to
  //  (successfully) arrive.
  //
  localparam [6:0] MAX_TA_TIMER = (816 / 8) - 1;

  reg ta_run_q, ta_err_q;
  reg  [6:0] ta_count;
  wire [7:0] ta_cnext;

  assign ta_cnext = ta_count - 1;

  always @(posedge clock) begin
    if (state == ST_SEND && usb_sent_i) begin
      // Turn-around timer for 'ACK' after sending 'DATAx'
      ta_run_q <= 1'b1;
      ta_err_q <= 1'b0;
      ta_count <= MAX_TA_TIMER;
    end else if (ta_run_q && (ta_cnext[7] || hsk_recv_i)) begin
      // Timer has elapsed, or handshake packet has been received
      ta_run_q <= 1'b0;
      ta_err_q <= ~hsk_recv_i;
      ta_count <= MAX_TA_TIMER;
    end else if (ta_run_q) begin
      // Still waiting ...
      ta_count <= ta_cnext;
    end else begin
      ta_run_q <= 1'b0;
      ta_err_q <= 1'b0;
      ta_count <= MAX_TA_TIMER;
    end
  end

  // -- End-Point Response Timer -- //

  localparam [4:0] MAX_EP_TIMER = (192 / 8) - 1;

  reg ep_run_q, ep_err_q;
  reg  [4:0] ep_count;
  wire [5:0] ep_cnext;

  assign ep_cnext = ep_count - 1;

  always @(posedge clock) begin
    if (state == ST_IDLE && tok_recv_i && tok_addr_i == usb_addr_i) begin
      // End-point-to-DATAx timer for 'DATAx' after receiving 'IN'
      ep_run_q <= usb_pid_i == `USBPID_IN;
      ep_err_q <= 1'b0;
      ep_count <= MAX_EP_TIMER;
    end else if (ep_run_q && (ep_cnext[5] || usb_busy_i)) begin
      // Timer has elapsed, or start-of-packet has been received
      ep_run_q <= 1'b0;
      ep_err_q <= ~usb_busy_i;
      ep_count <= MAX_EP_TIMER;
    end else if (ep_run_q) begin
      // Still waiting ...
      ep_count <= ep_cnext;
    end else begin
      ep_run_q <= 1'b0;
      ep_err_q <= 1'b0;
      ep_count <= MAX_EP_TIMER;
    end
  end

  // -- Token to DATAx Timer -- //

  localparam [4:0] MAX_TD_TIMER = (192 / 8) - 1;

  reg td_run_q, td_err_q;
  reg  [4:0] td_count;
  wire [5:0] td_cnext;

  assign td_cnext = td_count - 1;

  always @(posedge clock) begin
    if (state == ST_IDLE && tok_recv_i && tok_addr_i == usb_addr_i) begin
      // Token-to-DATAx timer for 'DATAx' after receiving 'OUT' or 'SETUP'
      td_run_q <= usb_pid_i == `USBPID_OUT || usb_pid_i == `USBPID_SETUP;
      td_err_q <= 1'b0;
      td_count <= MAX_TD_TIMER;
    end else if (td_run_q && (td_cnext[5] || RxEvent == 2'b01)) begin
      // Timer has elapsed, or start-of-packet has been received
      td_run_q <= 1'b0;
      td_err_q <= RxEvent != 2'b01;
      td_count <= MAX_TD_TIMER;
    end else if (td_run_q) begin
      // Still waiting ...
      td_count <= td_cnext;
    end else begin
      td_run_q <= 1'b0;
      td_err_q <= 1'b0;
      td_count <= MAX_TD_TIMER;
    end
  end

  // -- Time-Out register -- //

  always @(posedge clock) begin
    if (reset) begin
      timeout_q <= 1'b0;
    end else begin
      // timeout_q <= td_err_q | ta_err_q | ep_err_q;
      timeout_q <= 1'b0;
    end
  end


`ifdef __icarus
  //
  //  Simulation Only
  ///

  reg [39:0] dbg_state;
  reg [47:0] dbg_pid;

  always @* begin
    case (state)
      ST_IDLE: dbg_state = "IDLE";
      ST_RECV: dbg_state = "RECV";
      ST_RESP: dbg_state = "RESP";
      ST_DROP: dbg_state = "DROP";
      ST_SEND: dbg_state = "SEND";
      ST_WAIT: dbg_state = "WAIT";
      default: dbg_state = " ?? ";
    endcase
  end

  always @* begin
    case (pid_q)
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

`endif  /* __icarus */


endmodule  /* protocol */
