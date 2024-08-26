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

    input  ep2_rx_rdy_i,
    input  ep2_tx_rdy_i,
    input  ep2_parity_i,
    input  ep2_halted_i,
    output ep2_select_o,

    input  ep3_rx_rdy_i,
    input  ep3_tx_rdy_i,
    input  ep3_parity_i,
    input  ep3_halted_i,
    output ep3_select_o,

    input  ep4_rx_rdy_i,
    input  ep4_tx_rdy_i,
    input  ep4_parity_i,
    input  ep4_halted_i,
    output ep4_select_o
);

  `include "usb_defs.vh"

  reg ep1_en, ep2_en, ep3_en, ep4_en;
  reg [3:0] pid_c, pid_q;
  reg [5:0] state, snext;
  reg [6:0] bus_timer;
  wire timeout_w, par_w, len_error_w;

  reg mux_q;
  reg [2:0] sel_q;
  wire seq_w;
  wire [3:0] pid_w;

  assign mux_enable_o = mux_q;
  assign mux_select_o = sel_q;
  assign ulpi_tuser_o = pid_q;

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

`ifdef __potato_tomato
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

`else  /* !__potato_tomato */
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

`endif  /* !__potato_tomato */

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
                // snext = ST_DPID;
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
              // snext = ST_DPID;
              snext = ST_RECV;
            end else if (out_sel_w) begin
              if (out_rdy_w) begin
                // We have space, so RX some data
                // snext = ST_DPID;
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
                snext = ST_RESP;
                pid_c = `USBPID_STALL;
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
      end else if (timeout_w || crc_error_i || len_error_w) begin
        // OUT token to DATAx packet timeout
        // Ignore on data corruption, and host will retry
        snext = ST_IDLE;
      end

      ST_RESP:
      if (hsk_sent_i || timeout_w) begin
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
      end else if (timeout_w) begin
        // Internal error, as a device end-point timed-out, after it signalled
        // that it was ready, so we 'HALT' the endpoint (after some number of
        // attempts).
        // Todo:
        //  - halt failing end-points ??
        snext = ST_RESP;
        pid_c = `USBPID_STALL;
      end

      ST_WAIT:
      if (hsk_recv_i || timeout_w) begin
        // Waiting for host to send 'ACK'
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


  //
  //  USB Protocol Timers
  ///

  // -- Bus Turnaround Timer -- //

  //
  //  If we have sent a packet, then we require a handshake within 816 clocks,
  //  or else the packet failed to be transmitted, or the response failed to
  //  (successfully) arrive.
  //
  localparam [6:0] MAX_TIMER = (816 / 8) - 1;

  always @(posedge clock) begin
    if (reset) begin
      bus_timer = MAX_TIMER;
    end else begin
      // Todo ...
    end
  end

  // -- End-Point Response Timer -- //

  // Todo ...

  // -- Token to DATAx Timer -- //

  // Todo ...


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
