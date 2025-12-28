`timescale 1ns / 100ps
//
// Parser for USB Bulk-Only Transport (BOT) Command Block Wrapper (CBW) frames.
//
// Note(s):
//  - Some errors may 'STALL' this end-point, which will require using the
//    control-pipe to reset/re-enable the end-point.
//
module mmio_ep_in #(
    parameter MAX_PACKET_LENGTH = 512,  // For HS-mode
    localparam CBITS = $clog2(MAX_PACKET_LENGTH),
    localparam CSB = CBITS - 1,
    localparam CZERO = {CBITS{1'b0}},
    localparam CMAX = {CBITS{1'b1}},
    parameter PACKET_FIFO_DEPTH = 2048,
    localparam PBITS = $clog2(PACKET_FIFO_DEPTH),
    localparam PSB = PBITS - 1,
    parameter [31:0] MAGIC = "TART",
    parameter ENABLED = 1
) (
    input clock,
    input reset,

    input         set_conf_i,  // From CONTROL PIPE0
    input         clr_conf_i,  // From CONTROL PIPE0
    input [CSB:0] max_size_i,  // From CONTROL PIPE0

    input selected_i,  // From USB controller
    input ack_recv_i,  // From USB controller
    input timedout_i,  // From USB controller

    output ep_ready_o,
    output stalled_o,   // If invariants violated
    output parity_o,

    // From MMIO controller
    input  mmio_busy_i,
    input mmio_recv_i,
    output mmio_sent_o,
    output mmio_resp_o,
    input  mmio_done_i,

    // From Bulk-In data source (AXI or APB, via AXI-S)
    input dat_tvalid_i,
    output dat_tready_o,
    input dat_tkeep_i,
    input dat_tlast_i,
    input [7:0] dat_tdata_i,

    // Decoded command (APB, or AXI)
    input cmd_vld_i,
    input cmd_ack_i,
    input cmd_dir_i,
    input cmd_apb_i,
    input [1:0] cmd_cmd_i,
    input [3:0] cmd_tag_i,
    input [15:0] cmd_len_i,
    input [3:0] cmd_lun_i,

    // Output data stream (via AXI-S, to Bulk-In), and USB data or responses
    output usb_tvalid_o,
    input usb_tready_i,
    output usb_tlast_o,
    output usb_tkeep_o,
    output [7:0] usb_tdata_o
);

  reg stall, clear, ready, avail, bypass, parity, sent, respd;
  reg cyc, stb, lst, rdy, enb;
  wire fifo_tready_w;
  wire save_w, redo_w, next_w;

  // Top-level states for the high-level control of this end-point (EP).
  localparam [3:0] EP_IDLE = 4'h1, EP_XFER = 4'h2, EP_RESP = 4'h4, EP_HALT = 4'h8;

  assign stalled_o = stall;
  assign ep_ready_o = ready;
  assign parity_o = parity;
  assign mmio_sent_o = sent;
  assign mmio_resp_o = respd;
  assign usb_tready_o = bypass ? fifo_tready_w : rdy;

  /**
   * Pipeline some of the control signals.
   */
  wire avail_w;
  wire [PSB:0] level_w, space_w;

  assign space_w = MAX_PACKET_LENGTH - level_w;
  assign avail_w = space_w > MAX_PACKET_LENGTH;

  always @(posedge clock) begin
    // Clear state values, as required.
    if (reset || set_conf_i || clr_conf_i) begin
      clear <= 1'b1;
    end else begin
      clear <= 1'b0;
    end

    // End-point enablement.
    if (reset || clr_conf_i || stall) begin
      en_q <= 1'b0;
    end else if (set_conf_i) begin
      en_q <= 1'b1;
    end

    // End-point ready for data/transactions.
    if (clear || stall) begin
      ready <= 1'b0;
    end else if (en_q) begin
      ready <= avail;
    end

    // USB end-point parity-bit logic.
    if (clear) begin
      parity <= 1'b0;
    end else if (selected_i && ack_sent_i) begin
      parity <= ~parity;
    end
  end


  //
  // Top-level FSM.
  //
  reg [3:0] state;

  /**
   * End-point stall handling, in response to invalid commands.
   */
  always @(posedge clock) begin
    if (clear) begin
      stall <= 1'b0;
    end else if (parse == MM_FAIL) begin
      stall <= 1'b1;
    end
  end

  /**
   * Enable the packet-FIFO, if we are bypassing (USB) Bulk-Out data to AXI, and
   * then deassert once we have sent the response back to the USB host.
   */
  always @(posedge clock) begin
    if (clear || mmio_resp_i) begin
      enb <= 1'b1;
    end else if (state == EP_XFER && bypass) begin
      enb <= 1'b0;
    end
  end

  /**
   * Top-level of a hierarchical FSM, and just transitions between the phases
   * of parsing a command, transferring data, then sending a response.
   */
  always @(posedge clock) begin
    if (clear) begin
      state <= EP_IDLE;
    end else if (stall) begin
      state <= EP_HALT;
    end else begin
      case (state)
        EP_IDLE: state <= vld ? EP_XFER : state;
        EP_XFER: state <= mmio_recv_i || sent ? EP_RESP : state;
        EP_RESP: state <= resp ? EP_IDLE : state;
        EP_HALT: state <= state;
      endcase
    end
  end


  //
  // Output packet FIFO, for command responses, or (FETCH or GET) data passed-
  // through to the USB host (via Bulk-In pipe), and with with Repeat-Last
  // Packet, on timeout (while waiting for ACK).
  //
  packet_fifo #(
      .WIDTH(8),
      .DEPTH(PACKET_FIFO_DEPTH),
      .STORE_LASTS(1),
      .SAVE_ON_LAST(1),
      .LAST_ON_SAVE(1),
      .NEXT_ON_LAST(0),
      .USE_LENGTH(1),
      .MAX_LENGTH(MAX_PACKET_LENGTH),
      .OUTREG(2)
  ) U_FIFO0 (
      .clock(clock),
      .reset(clear),

      .level_o(level_w),

      .drop_i (1'b0),
      .save_i (save_w),
      .redo_i (redo_w),
      .next_i (next_w),

      .s_tvalid(s_tvalid),
      .s_tready(fifo_tready_w),
      .s_tlast (s_tlast),
      .s_tkeep (s_tvalid),
      .s_tdata (s_tdata),

      .m_tvalid(tvalid_r),
      .m_tready(tready_r),
      .m_tlast (tlast_r),
      .m_tdata (m_tdata)
  );


endmodule  /* mmio_ep_in */
