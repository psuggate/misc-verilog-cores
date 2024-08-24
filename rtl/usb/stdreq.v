`timescale 1ns / 100ps
/**
 * Handles USB CONTROL requests.
 * Todo:
 *  - read/write the status registers of other endpoints ??
 */
module stdreq #(
    parameter integer SERIAL_LENGTH = 8,
    parameter [SERIAL_LENGTH*8-1:0] SERIAL_STRING = "TART0001",

    parameter [15:0] VENDOR_ID = 16'hF4CE,
    parameter integer VENDOR_LENGTH = 19,
    parameter [VENDOR_LENGTH*8-1:0] VENDOR_STRING = "University of Otago",

    parameter [15:0] PRODUCT_ID = 16'h0003,
    parameter integer PRODUCT_LENGTH = 8,
    parameter [PRODUCT_LENGTH*8-1:0] PRODUCT_STRING = "TART USB"
) (
    input clock,
    input reset,

   // USB device current configuration
    output enumerated_o,
    output configured_o,
    output [2:0] conf_num_o,
    output [6:0] address_o,
    output set_conf_o,
    output clr_conf_o,

    // Signals from the USB packet decoder (upstream)
    input tok_recv_i,
    // input tok_ping_i,
    input [6:0] tok_addr_i,
    input [3:0] tok_endp_i,

    input hsk_recv_i,
    input hsk_sent_i,
    input eop_recv_i,
    input usb_recv_i,
    input usb_busy_i,
    input usb_sent_i,

   // From the USB protocol logic
    input  select_i,
    input  start_i,
    output finish_o,
    input  timeout_i,

    // From the packet decoder
    input s_tvalid,
    output s_tready,
    input s_tkeep,
    input s_tlast,
    input [3:0] s_tuser,
    input [7:0] s_tdata,

    // To the packet encoder
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

  // -- Control Pipe SETUP Request FSM -- //

  always @* begin
    snext = state;

    case (state)
      ST_IDLE:
      if (start_i) begin
        snext = ST_SETUP;
      end
      ST_SETUP:
      if (hsk_sent_i) begin
        snext = ST_DATA;
      end
      ST_DATA:
      if (hsk_sent_i || hsk_recv_i) begin
        snext = ST_STATUS;
      end else if (timeout_i) begin
        snext = ST_IDLE;
      end
      ST_STATUS:
      if (hsk_sent_i || hsk_recv_i || timeout_i) begin
        snext = ST_IDLE;
      end
      default: snext = snext;
    endcase

    if (!stdreq_i) begin
      snext = ST_IDLE;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      state = ST_IDLE;
    end else begin
      state = snext;
    end
  end


endmodule  /* stdreq */
