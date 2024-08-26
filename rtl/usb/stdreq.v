`timescale 1ns / 100ps
/**
 * Handles USB CONTROL requests.
 * Todo:
 *  - read/write the status registers of other endpoints ??
 */
module stdreq #(
    parameter EP0_ONLY = 1
) (
    input clock,
    input reset,

    // USB device current configuration
    input enumerated_i,
    input configured_i,
    input [6:0] usb_addr_i,

    // Signals from the USB packet decoder (upstream)
    input tok_recv_i,
    input [6:0] tok_addr_i,
    input [3:0] tok_endp_i,

    input hsk_recv_i,
    input hsk_sent_i,
    input eop_recv_i,
    input usb_recv_i,
    input usb_sent_i,

    // From the USB protocol logic
    input  select_o,
    output parity_o,
    output start_o,
    output finish_o,
    input  timeout_i,

    // To the device control pipe(s)
    output req_start_o,
    output req_cycle_o,
    input req_event_i,
    input req_error_i,
    output [7:0] req_rtype_o,
    output [7:0] req_rargs_o,
    output [15:0] req_value_o,
    output [15:0] req_index_o,
    output [15:0] req_length_o,

    // From the packet decoder
    input s_tvalid,
    output s_tready,
    input s_tkeep,
    input s_tlast,
    input [3:0] s_tuser,
    input [7:0] s_tdata,

    // To the end-point, when 'OUT' std requests include extra data
   // Todo: not implemented, but should it be?
    output m_tvalid,
    input m_tready,
    output m_tkeep,
    output m_tlast,
    output [3:0] m_tuser,
    output [7:0] m_tdata
);

  `include "usb_defs.vh"

  // -- Some More Constants -- //

  localparam ST_IDLE = 1;
  localparam ST_SETUP = 2;
  localparam ST_DATA = 4;
  localparam ST_STATUS = 8;

  // -- Module Signals & Registers -- //

  reg [3:0] state, snext;
  reg cyc_q, end_q, par_q, req_q, sel_q;
  reg [2:0] xcptr;
  wire end_w, req_w, sel_w;

  reg req_start_q, req_cycle_q;
  reg [7:0] req_rtype_q, req_rargs_q;
  reg [7:0] req_valhi_q, req_vallo_q;
  reg [7:0] req_idxhi_q, req_idxlo_q;
  reg [7:0] req_lenhi_q, req_lenlo_q;
  wire req_done_w;

  assign start_o = sel_q;
  assign select_o = cyc_q;
  assign parity_o = par_q;
  assign finish_o = end_q;

  assign s_tready = 1'b1;

  assign req_start_o = req_start_q;
  assign req_cycle_o = req_cycle_q;
  assign req_rtype_o = req_rtype_q;
  assign req_rargs_o = req_rargs_q;
  assign req_value_o = {req_valhi_q, req_vallo_q};
  assign req_index_o = {req_idxhi_q, req_idxlo_q};
  assign req_length_o = {req_lenhi_q, req_lenlo_q};

  // -- Standard-Request Cycle Logic -- //

  assign sel_w = state == ST_IDLE && tok_recv_i && tok_addr_i == usb_addr_i &&
                 s_tuser == `USBPID_SETUP && (!EP0_ONLY || tok_endp_i == 4'h0);
  assign req_w = state == ST_SETUP && s_tuser == `USBPID_DATA0;
  assign end_w = state == ST_STATUS && (hsk_sent_i || hsk_recv_i || timeout_i);

  always @(posedge clock) begin
    if (reset) begin
      sel_q <= 1'b0;
      req_q <= 1'b0;
      par_q <= 1'b0;
      end_q <= 1'b0;
      cyc_q <= 1'b0;
    end else begin
      sel_q <= sel_w;
      req_q <= req_w;
      end_q <= end_w;

      if (sel_w) begin
        cyc_q <= 1'b1;
      end else if (end_w) begin
        cyc_q <= 1'b0;
      end

      case (state)
        ST_IDLE:   par_q <= 1'b0;
        ST_SETUP:  if (hsk_sent_i) par_q <= 1'b1;
        ST_DATA:   if (hsk_sent_i || hsk_recv_i) par_q <= ~par_q;
        ST_STATUS: par_q <= 1'b1;
        default:   par_q <= 1'bx;
      endcase
    end
  end

  // -- Parser for Control Transfer Parameters -- //

  assign req_done_w = end_w;  // Todo ...

  // Todo:
  //  - if there is more data after the 8th byte, then forward that out (via
  //    an AXI4-Stream skid-register) !?
  always @(posedge clock) begin
    if (!cyc_q) begin
      xcptr <= 3'b000;
      req_lenlo_q <= 0;
      req_lenhi_q <= 0;
      req_start_q <= 1'b0;
      req_cycle_q <= 1'b0;
    end else if (req_q && s_tvalid && s_tkeep && s_tready) begin
      req_rtype_q <= xcptr == 3'b000 ? s_tdata : req_rtype_q;
      req_rargs_q <= xcptr == 3'b001 ? s_tdata : req_rargs_q;

      req_vallo_q <= xcptr == 3'b010 ? s_tdata : req_vallo_q;
      req_valhi_q <= xcptr == 3'b011 ? s_tdata : req_valhi_q;

      req_idxlo_q <= xcptr == 3'b100 ? s_tdata : req_idxlo_q;
      req_idxhi_q <= xcptr == 3'b101 ? s_tdata : req_idxhi_q;

      req_lenlo_q <= xcptr == 3'b110 ? s_tdata : req_lenlo_q;
      req_lenhi_q <= xcptr == 3'b111 ? s_tdata : req_lenhi_q;

      if (xcptr == 7) begin
        if (!req_cycle_q) begin
          req_start_q <= 1'b1;
          req_cycle_q <= 1'b1;
        end
      end else begin
        xcptr <= xcptr + 1;
      end
    end else begin
      req_start_q <= 1'b0;
      req_cycle_q <= req_done_w ? 1'b0 : req_cycle_q;
    end
  end

  // -- Control Pipe SETUP Request FSM -- //

  always @* begin
    snext = state;

    case (state)
      ST_IDLE:
      if (sel_q) begin
        snext = ST_SETUP;
      end
      ST_SETUP:
      if (hsk_sent_i) begin
        if (req_lenhi_q == 0 && req_lenlo_q == 0) begin
          snext = ST_STATUS;
        end else begin
          snext = ST_DATA;
        end
      end
      ST_DATA:
      if (hsk_sent_i || hsk_recv_i) begin
        snext = ST_STATUS;
      end else if (timeout_i) begin
        snext = ST_IDLE;
      end
      ST_STATUS:
      if (end_q) begin
        snext = ST_IDLE;
      end
      default: snext = snext;
    endcase

    if (!cyc_q) begin
      snext = ST_IDLE;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      state <= ST_IDLE;
    end else begin
      state <= snext;
    end
  end


`ifdef __icarus
  //
  //  Simulation Only
  ///

  reg [55:0] dbg_state;

  always @* begin
    case (state)
      ST_IDLE:   dbg_state = "IDLE";
      ST_SETUP:  dbg_state = "SETUP";
      ST_DATA:   dbg_state = "DATA";
      ST_STATUS: dbg_state = "STATUS";
      default:   dbg_state = " ?? ";
    endcase
  end

`endif  /* __icarus */


endmodule  /* stdreq */
