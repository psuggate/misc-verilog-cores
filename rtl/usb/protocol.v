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
    parameter DEBUG = 0,
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
    output [2:0] state_o,

    input set_conf_i,
    input clr_conf_i,
    input [6:0] usb_addr_i,

    // Signals from the USB packet decoder (upstream)
    input dec_actv_i,
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
    output ep1_cancel_o,

    input  ep2_rx_rdy_i,
    input  ep2_tx_rdy_i,
    input  ep2_parity_i,
    input  ep2_halted_i,
    output ep2_select_o,
    output ep2_finish_o,
    output ep2_cancel_o,

    input  ep3_rx_rdy_i,
    input  ep3_tx_rdy_i,
    input  ep3_parity_i,
    input  ep3_halted_i,
    output ep3_select_o,
    output ep3_finish_o,
    output ep3_cancel_o,

    input  ep4_rx_rdy_i,
    input  ep4_tx_rdy_i,
    input  ep4_parity_i,
    input  ep4_halted_i,
    output ep4_select_o,
    output ep4_finish_o,
    output ep4_cancel_o
);

  // -- Constants -- //

  `include "usb_defs.vh"

  localparam [5:0] ST_IDLE = 1;
  localparam [5:0] ST_RECV = 2;  // RX data from the ULPI
  localparam [5:0] ST_RESP = 4;  // Send a handshake to USB host
  localparam [5:0] ST_DROP = 8;  // Wait for EOP, and then no response
  localparam [5:0] ST_SEND = 16;  // Route data from EP to ULPI
  localparam [5:0] ST_WAIT = 32;  // Wait for USB host handshake

  localparam EP1_EN = BULK_EP1 != 0 && (USE_EP1_IN || USE_EP1_OUT);
  localparam EP2_EN = BULK_EP2 != 0 && (USE_EP2_IN || USE_EP2_OUT);
  localparam EP3_EN = BULK_EP3 != 0 && (USE_EP3_IN || USE_EP3_OUT);
  localparam EP4_EN = BULK_EP4 != 0 && (USE_EP4_IN || USE_EP4_OUT);

  localparam [3:0] PID_Q = DEBUG ? 4'h0 : 4'hx;

  // -- Module Signals & Registers -- //

  // End-point control registers
  reg ep1_en, ep2_en, ep3_en, ep4_en;
  reg ep0_sel_q, ep1_sel_q, ep2_sel_q, ep3_sel_q, ep4_sel_q;
  reg ep0_ack_q, ep1_ack_q, ep2_ack_q, ep3_ack_q, ep4_ack_q;
  reg epx_err_q, crc_err_q, crc_ack_q;

  // Transaction control registers & signals
  reg ping_q, nyet_q, par_q, seq_q, end_q, tag_q, epg_q;
  reg out_rdy_q;
  reg [3:0] pid_q;
  reg [5:0] state;
  reg timeout_q = 1'b0;
  wire seq_w, par_w;
  reg [2:0] stout;

  // Multiplexor Signals, for DATAx -> Host
  reg mux_q;
  reg [2:0] sel_q;

  // -- Output Signal Assignments -- //

  assign timedout_o = timeout_q;
  assign hsk_send_o = state == ST_RESP;
  assign state_o = stout;

  assign mux_enable_o = mux_q;
  assign mux_select_o = sel_q;
  assign ulpi_tuser_o = pid_q;

  assign ep1_select_o = ep1_sel_q;
  assign ep2_select_o = ep2_sel_q;
  assign ep3_select_o = ep3_sel_q;
  assign ep4_select_o = ep4_sel_q;

  assign ep1_finish_o = ep1_ack_q;
  assign ep2_finish_o = ep2_ack_q;
  assign ep3_finish_o = ep3_ack_q;
  assign ep4_finish_o = ep4_ack_q;

  assign ep1_cancel_o = epx_err_q;
  assign ep2_cancel_o = epx_err_q;
  assign ep3_cancel_o = epx_err_q;
  assign ep4_cancel_o = epx_err_q;

  //
  //  End-Point Control
  ///

  // -- End-Point Enabled/Stalled Registers -- //

  always @(posedge clock) begin
    if (reset || clr_conf_i) begin
      // if (reset || clr_conf_i || ep1_halted_i) begin
      {ep4_en, ep3_en, ep2_en, ep1_en} <= 4'h0;
    end else if (set_conf_i) begin
      // {ep4_en, ep3_en, ep2_en, ep1_en} <= {EP4_EN[0], EP3_EN[0], EP2_EN[0], EP1_EN[0]};
      {ep4_en, ep3_en, ep2_en, ep1_en} <= {EP4_EN, EP3_EN, EP2_EN, EP1_EN};
    end
  end

  // -- CRC-Error One-Shot -- //

  always @(posedge clock) begin
    if (reset || !crc_error_i) begin
      crc_err_q <= 1'b0;
      crc_ack_q <= 1'b0;
    end else begin
      if (!crc_ack_q && crc_error_i) begin
        crc_err_q <= 1'b1;
        crc_ack_q <= 1'b1;
      end else begin
        crc_err_q <= 1'b0;
        crc_ack_q <= crc_ack_q;
      end
    end
  end

  // -- USB Transaction Framing Signals -- //

  // Deselect all of the end-points at the end of each transaction, due to a
  // configuration event, on reset, or on error.
  always @(posedge clock) begin
    if (reset || clr_conf_i || hsk_recv_i || hsk_sent_i || timeout_q || crc_err_q) begin
      end_q <= 1'b1;
    end else begin
      end_q <= 1'b0;
    end
  end

  // -- End-Point Readies & Selects -- //

  // An end-point remains selected from when an appropriate token is received,
  // until the end of the transaction.
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

  // -- End-point State Signals & Response Registers -- //

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

  always @(posedge clock) begin
    if (end_q) begin
      {ep4_ack_q, ep3_ack_q, ep2_ack_q, ep1_ack_q} <= 4'b0000;
      epx_err_q <= 1'b0;
    end else begin
      ep1_ack_q <= ep1_sel_q && ((USE_EP1_OUT && hsk_sent_i) || (USE_EP1_IN && hsk_recv_i));
      ep2_ack_q <= ep2_sel_q && ((USE_EP2_OUT && hsk_sent_i) || (USE_EP2_IN && hsk_recv_i));
      ep3_ack_q <= ep3_sel_q && ((USE_EP3_OUT && hsk_sent_i) || (USE_EP3_IN && hsk_recv_i));
      ep4_ack_q <= ep4_sel_q && ((USE_EP4_OUT && hsk_sent_i) || (USE_EP4_IN && hsk_recv_i));

      epx_err_q <= crc_err_q || timeout_q;  // || set_conf_i; // Todo: !?
    end

    out_rdy_q <= out_rdy_w;  // Pipeline for Fmax
  end

  // -- DATAx Parity-Checking for the Sequence Bits -- //

  wire ep0_par_w = ep0_select_i && ep0_parity_i == usb_pid_i[3];
  wire ep1_par_w = ep1_out_sel_w && ep1_parity_i == usb_pid_i[3];
  wire ep2_par_w = ep2_out_sel_w && ep2_parity_i == usb_pid_i[3];
  wire ep3_par_w = ep3_out_sel_w && ep3_parity_i == usb_pid_i[3];
  wire ep4_par_w = ep4_out_sel_w && ep4_parity_i == usb_pid_i[3];

  assign par_w = ep0_par_w | ep1_par_w | ep2_par_w | ep3_par_w | ep4_par_w;

  always @(posedge clock) begin
    if (dec_actv_i) begin
      par_q <= par_w;
    end

    if (!usb_busy_i) begin
      seq_q <= (ep0_sel_q & ep0_parity_i) |
               (ep1_sel_q & ep1_parity_i) |
               (ep2_sel_q & ep2_parity_i) |
               (ep3_sel_q & ep3_parity_i) |
               (ep4_sel_q & ep4_parity_i) ;
    end
  end

  // -- PING Protocol Logic -- //

  //
  // Todo: if we complete a 'PING'-initiated transaction we need to be able to
  //   send a 'NYET' !?
  //
  always @(posedge clock) begin
    if (set_conf_i) begin
      ping_q <= 1'b0;
      nyet_q <= 1'b0;
    end else begin
      case (state)
        ST_IDLE:
        if (tok_recv_i && tok_addr_i == usb_addr_i) begin
          if (usb_pid_i == `USBPID_PING && out_rdy_q) begin
            ping_q <= 1'b1;
            nyet_q <= 1'b0;
          end else if (usb_pid_i != `USBPID_OUT) begin
            ping_q <= 1'b0;
            nyet_q <= 1'b0;
          end
        end
        ST_RESP:
        if (nyet_q && hsk_sent_i) begin
          ping_q <= 1'b0;
          nyet_q <= 1'b0;
        end
        ST_RECV: {ping_q, nyet_q} <= {ping_q, ~out_rdy_q};
        default: {ping_q, nyet_q} <= 2'h0;
      endcase
    end
  end

  // -- FSM -- //

  always @(posedge clock) begin
    if (reset) begin
      state <= ST_IDLE;
      stout <= 3'd0;
      pid_q <= PID_Q;
      tag_q <= 1'b0;
      epg_q <= 1'b0;
    end else begin
      case (state)

        ST_IDLE:
        if (tok_recv_i && tok_addr_i == usb_addr_i) begin
          // Todo:
          //  - for any missing/other end-point, ignore; OR,
          //  - issue 'STALL' for unsupported IN/OUT & EP pairing?
          case (usb_pid_i)
            `USBPID_SETUP: begin
              pid_q <= PID_Q;
              if (tok_endp_i == 4'h0) begin
                state <= ST_RECV;
                stout <= 3'd1;
                tag_q <= 1'b0;
                epg_q <= 1'b1;
              end else begin
                // Indicate that operation is unsupported (by timing-out)
                state <= ST_WAIT;
                stout <= 3'd5;
                tag_q <= 1'b1;
                epg_q <= 1'b0;
              end
            end

            `USBPID_OUT: begin
              pid_q <= PID_Q;
              if (ep0_select_i || out_rdy_q) begin
                // EP0 CONTROL transfers always succeed; OR,
                // We have space, so RX some data
                state <= ST_RECV;
                stout <= 3'd1;
                tag_q <= 1'b0;
                epg_q <= 1'b1;
              end else if (out_sel_w) begin
                // No space, so we drop then 'NAK'
                state <= ST_DROP;
                stout <= 3'd3;
                tag_q <= 1'b0;
                epg_q <= 1'b0;
              end else begin
                state <= ST_WAIT;
                stout <= 3'd5;
                tag_q <= 1'b1;
                epg_q <= 1'b0;
              end
            end

            `USBPID_IN: begin
              pid_q <= `USBPID_NAK;
              if (ep0_select_i || in_rdy_w) begin
                // Let EP0 sort out this CONTROL transfer; OR,
                // We have at least one packet ready to TX
                state <= ST_SEND;
                stout <= 3'd4;
                tag_q <= 1'b0;
                epg_q <= 1'b1;
              end else if (in_sel_w) begin
                // Selected, but no packet is ready, so NAK
                state <= ST_RESP;
                stout <= 3'd2;
                tag_q <= 1'b0;
                epg_q <= 1'b1;
              end else begin
                // Invalid (or halted) end-point, so wait for timeout
                state <= ST_WAIT;
                stout <= 3'd5;
                tag_q <= 1'b1;
                epg_q <= 1'b0;
              end
            end

            `USBPID_PING: begin
              state <= ST_RESP;
              stout <= 3'd2;
              pid_q <= ep0_select_i || out_rdy_q ? `USBPID_ACK : `USBPID_NAK;
              tag_q <= 1'b0;
              epg_q <= 1'b1;
            end

            // Ignore, and impossible to reach here
            default: begin
              state <= state;
              stout <= 3'd7;
              pid_q <= PID_Q;
              tag_q <= 1'bx;
              epg_q <= 1'bx;
            end
          endcase
        end

        // -- OUT and SETUP -- //

        ST_RECV: begin
          pid_q <= ping_q && !out_rdy_q ? `USBPID_NYET : `USBPID_ACK;
          tag_q <= 1'b0;
          if (usb_recv_i) begin
            // Expecting 'DATAx' PID, after an 'OUT' or 'SETUP'
            // If parity-bits sequence error, we ignore the DATAx, but ACK response,
            // or else receive as usual.
            state <= par_q ? ST_RESP : ST_IDLE;
            stout <= par_q ? 3'd2 : 3'd0;
            epg_q <= par_q;
          end else if (timeout_q || crc_error_i) begin
            // OUT token to DATAx packet timeout
            // Ignore on data corruption, and host will retry
            state <= ST_IDLE;
            stout <= 3'd0;
            epg_q <= 1'b0;
          end
        end

        // -- IN -- //

        ST_SEND: begin
          pid_q <= seq_q ? `USBPID_DATA1 : `USBPID_DATA0;
          epg_q <= 1'b0;
          if (usb_sent_i) begin
            // Waiting for endpoint to send 'DATAx', after an 'IN'
            state <= ST_WAIT;
            stout <= 3'd5;
            tag_q <= 1'b1;
          end else if (timeout_q) begin
            // Internal error, as a device end-point timed-out, after it signalled
            // that it was ready, so we 'HALT' the endpoint (after some number of
            // attempts).
            // Todo:
            //  - halt failing end-points ??
            state <= ST_IDLE;
            stout <= 3'd0;
            tag_q <= 1'b0;
          end
        end

        // -- End-of-Transaction & Error Handling -- //

        ST_RESP: begin
          pid_q <= pid_q;
          tag_q <= 1'b0;
          epg_q <= 1'b0;
          if (hsk_sent_i || timeout_q) begin
            // Sent 'ACK/NAK/NYET/STALL' in response to 'DATAx' & 'PING'
            state <= ST_IDLE;
            stout <= 3'd0;
          end
        end

        ST_WAIT: begin
          pid_q <= PID_Q;
          tag_q <= 1'b0;
          epg_q <= 1'b0;
          if (hsk_recv_i || timeout_q) begin
            // Waiting for host to send 'ACK', or waiting for bus turnaround timer
            // to elapse, for an unsupported request.
            state <= ST_IDLE;
            stout <= 3'd0;
          end
        end

        // ST_DROP: state <= eop_recv_i ? ST_RESP : (timeout_q ? ST_IDLE : ST_DROP);
        ST_DROP: begin
          pid_q <= `USBPID_NAK;
          tag_q <= 1'b0;
          epg_q <= 1'b0;
          if (eop_recv_i) begin
            state <= ST_RESP;
            stout <= 3'd2;
          end else if (timeout_q) begin
            state <= ST_IDLE;
            stout <= 3'd0;
          end
        end

        default: begin
          state <= 6'bx;
          stout <= 3'd6;
          pid_q <= PID_Q;
          tag_q <= 1'bx;
          epg_q <= 1'bx;
        end

      endcase
    end
  end

  //
  // Todo:
  //  - send (& test) NAK & STALL handshake packets !?
  //  - use a 'function' for MUX select-values, for better "packing"
  //
  always @(posedge clock) begin
    if (reset) begin
      mux_q <= 1'b0;
      sel_q <= 8'd0;
    end else begin
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


  //
  //  USB Protocol Timers
  ///

`ifdef __icarus
  localparam [6:0] MAX_TA_TIMER = (816 / 32) - 1;
  localparam [4:0] MAX_EP_TIMER = (192 / 32) - 1;
`else  /* !__icarus */
  localparam [6:0] MAX_TA_TIMER = (816 / 8) - 1;
  localparam [4:0] MAX_EP_TIMER = (192 / 8) - 1;
`endif  /* !__icarus */

  reg ta_run_q, ta_err_q;
  reg ep_run_q, ep_err_q;

  // -- Time-Out register -- //

  always @(posedge clock) begin
    if (reset) begin
      timeout_q <= 1'b0;
    end else begin
      timeout_q <= ta_err_q | ep_err_q;
    end
  end

  // -- Bus Turnaround Timer -- //

  //
  //  If we have sent a packet, then we require a handshake within 816 clocks,
  //  or else the packet failed to be transmitted, or the response failed to
  //  (successfully) arrive.
  //
  reg  [6:0] ta_count;
  wire [7:0] ta_cnext;

  assign ta_cnext = ta_count - 1;

  always @(posedge clock) begin
    if (tag_q) begin
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

  reg  [4:0] ep_count;
  wire [5:0] ep_cnext;

  assign ep_cnext = ep_count - 1;

  always @(posedge clock) begin
    if (epg_q) begin
      ep_run_q <= 1'b1;
      ep_err_q <= 1'b0;
      ep_count <= MAX_EP_TIMER;
    end else if (ep_run_q && (ep_cnext[5] || usb_busy_i || RxEvent == 2'b01)) begin
      // Timer has elapsed, or start-of-packet has been received
      ep_run_q <= 1'b0;
      ep_err_q <= !usb_busy_i && RxEvent != 2'b01;
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
