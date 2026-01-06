`timescale 1ns / 100ps
//
// Data and command-responses for USB MMIO logic-core, that presents a Bulk-Only
// Transport (BOT) inspired interface connecting AXI and APB buses to USB.
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

    input           set_conf_i,  // From CONTROL PIPE0
    input           clr_conf_i,  // From CONTROL PIPE0
    input [CBITS:0] max_size_i,  // From CONTROL PIPE0

    input selected_i,  // From USB controller
    input ack_recv_i,  // From USB controller
    input ack_sent_i,  // From USB controller
    input timedout_i,  // From USB controller

    output ep_ready_o,
    output stalled_o,   // If invariants violated
    output parity_o,

    // From MMIO controller
    input  mmio_busy_i,
    input  mmio_recv_i,
    input  mmio_send_i,
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
    input cmd_rdy_i,
    input [15:0] cmd_val_i,

    // Output data stream (via AXI-S, to Bulk-In), and USB data or responses
    output usb_tvalid_o,
    input usb_tready_i,
    output usb_tlast_o,
    output usb_tkeep_o,
    output [7:0] usb_tdata_o
);

  // Todo:
  `define CMD_SUCCESS 4'h0
  `define CMD_FAILURE 4'h1
  `define CMD_INVALID 4'hF

  reg stall, clear, ready, avail, bypass, parity, sent, respd;
  reg cyc, stb, lst, rdy, enb;
  reg save_q, redo_q, next_q;
  wire fifo_tvalid_w, fifo_tready_w, fifo_tkeep_w, fifo_tlast_w;
  wire [7:0] fifo_tdata_w;

  // Top-level states for the high-level control of this end-point (EP).
  localparam [3:0] EP_IDLE = 4'h1, EP_SEND = 4'h2, EP_RESP = 4'h4, EP_HALT = 4'h8;

  assign stalled_o = stall;
  assign ep_ready_o = ready;
  assign parity_o = parity;

  assign mmio_sent_o = sent;
  assign mmio_resp_o = respd;

  // Todo ...
  assign fifo_tvalid_w = bypass ? dat_tvalid_i : vld;
  assign dat_tready_o = bypass ? fifo_tready_w : rdy;
  assign fifo_tkeep_w = 1'b1;
  assign fifo_tlast_w = bypass ? dat_tlast_i : lst;
  assign fifo_tdata_w = bypass ? dat_tdata_i : dat;

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
    if (clear || mmio_done_i) begin
      enb <= 1'b1;
    end else if (state == EP_SEND && bypass) begin
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
        EP_IDLE: state <= vld ? EP_SEND : state;
        EP_SEND: state <= mmio_sent_i || sent ? EP_RESP : state;
        EP_RESP: state <= resp ? EP_IDLE : state;
        EP_HALT: state <= state;
      endcase
    end
  end

  //
  // Todo:
  //  - generate 'SAVE' strobes once enough data for a full USB frame exists in
  //    the packet FIFO;
  //  - issue 'NEXT' strobes when each 'ACK' is received, after a 'DATA IN'
  //    transaction;
  //  - repeat data-transmissions, via 'REDO' strobes, on 'ACK' timeouts;
  //
  always @(posedge clock) begin
    if (clear) begin
      save_q <= 1'b0;
      next_q <= 1'b0;
      redo_q <= 1'b0;
    end else begin
      case (state)
        EP_IDLE: {redo_q, next_q, save_q} <= 3'b000;
        EP_HALT: {redo_q, next_q, save_q} <= 3'b000;
        default: {redo_q, next_q, save_q} <= 3'b000;
      endcase
    end
  end

  /**
   * Compute the "residual" of a transaction, of the value returned by an APB
   * transaction.
   *
   * Todo:
   *  - can be either 16-bit value from APB, or the number of bytes _not_ sent;
   *  - how to handle 0 vs 65536 (as the residual)?
   *  - how to count bytes transferred by other end-point?
   */
  reg [15:0] val_q;
  reg [16:0] val_w;

  assign val_w = state == EP_IDLE ? cmd_len_i + 1 : val_q - 1;

  always @(posedge clock) begin
    if (clear) begin
      val_q <= 16'bx;
    end else begin
      case (state)
        EP_IDLE:
        if (cmd_vld_i && ack_sent_i) begin
          val_q <= val_w[15:0];
        end

        EP_SEND:
        if (dat_tvalid_i && dat_tkeep_i && dat_tready_o) begin
          val_q <= cmd_apb_i ? {dat_tdata_i, val_q[15:8]} : val_w[15:0];
        end

        EP_RESP: val_q <= val_q;

        default: val_q <= 16'bx;
      endcase
    end
  end

  /**
   * Writes the MMIO response, after the data transfer stage(s) have completed.
   */
  reg  [55:0] out_q;
  reg  [ 2:0] sel_q;
  wire [55:0] out_w;
  wire [ 3:0] sel_w;

  assign sel_w = sel_q - 1;
  assign out_w = {cmd_tag_i, `CMD_SUCCESS, val_q, "T", "R", "A", "T"};

  always @(posedge clock) begin
    if (clear) begin
      sel_q <= 3'd0;
      out_q <= 56'bx;
    end else if (state == EP_SEND && mmio_sent_i) begin
      sel_q <= 3'd7;
      out_q <= out_w;
    end else if (fifo_tready_w && sel_q != 3'd0) begin
      sel_q <= sel_w[2:0];
      out_q <= {8'bx, out_q[55:8]};
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

      .drop_i(1'b0),
      .save_i(save_q),
      .redo_i(redo_q),
      .next_i(next_q),

      .s_tvalid(fifo_tvalid_w),
      .s_tready(fifo_tready_w),
      .s_tlast (fifo_tlast_w),
      .s_tkeep (fifo_tkeep_w),
      .s_tdata (fifo_tdata_w),

      .m_tvalid(usb_tvalid_o),
      .m_tready(usb_tready_i),
      .m_tlast (usb_tlast_o),
      .m_tdata (usb_tdata_o)
  );


`ifdef __icarus
  //
  //  Simulation Only
  ///
  reg [39:0] dbg_state;

  always @* begin
    case (state)
      EP_IDLE: dbg_state = "IDLE";
      EP_RECV: dbg_state = "RECV";
      EP_RESP: dbg_state = "RESP";
      EP_HALT: dbg_state = "HALT";
      default: dbg_state = " ?? ";
    endcase
  end

`endif  /* __icarus */

endmodule  /* mmio_ep_in */
