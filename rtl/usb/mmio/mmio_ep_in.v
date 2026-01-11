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
    parameter integer TIMEOUT = 256,
    localparam integer TBITS = $clog2(256),
    localparam integer TSB = TBITS - 1,
    parameter MAX_PACKET_LENGTH = 512,  // For HS-mode
    localparam CBITS = $clog2(MAX_PACKET_LENGTH),
    localparam CSB = CBITS - 1,
    localparam CZERO = {CBITS{1'b0}},
    localparam CMAX = {CBITS{1'b1}},
    parameter PACKET_FIFO_DEPTH = 2048,
    localparam PBITS = $clog2(PACKET_FIFO_DEPTH),
    localparam PSB = PBITS - 1,
    parameter [31:0] MAGIC = "TART",
    parameter ENABLED = 1  // Todo
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
    input cmd_err_i,
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

  reg stall, clear, ready, parity, sent, resp;
  reg vld_q, lst_q, zdp_q, enb_q, en_q, cyc, stb;
  reg save_q, redo_q, next_q;
  wire [7:0] dat_w;
  wire save_w, redo_w, next_w, sent_w;
  wire fifo_tvalid_w, fifo_tready_w, fifo_tkeep_w, fifo_tlast_w;
  wire ulpi_tvalid_w, ulpi_tready_w, ulpi_tkeep_w, ulpi_tlast_w;
  wire [7:0] fifo_tdata_w, ulpi_tdata_w;

  // Top-level states for the high-level control of this end-point (EP).
  reg [3:0] state;
  localparam [3:0] EP_IDLE = 4'h1, EP_SEND = 4'h2, EP_RESP = 4'h4, EP_HALT = 4'h8;

  // Top-level states for the high-level control of this end-point (EP).
  reg [4:0] xmit, snxt;
  localparam [4:0] TX_IDLE = 5'h01, TX_SEND = 5'h02, TX_WAIT = 5'h04;
  localparam [4:0] TX_NONE = 5'h08, TX_REDO = 5'h10;

  assign stalled_o = stall;
  assign ep_ready_o = ready;
  assign parity_o = parity;

  assign mmio_sent_o = sent;
  assign mmio_resp_o = resp;

  // Todo ...
  assign fifo_tvalid_w = state == EP_SEND ? dat_tvalid_i : vld_q;
  assign dat_tready_o = state == EP_SEND ? fifo_tready_w : 1'b0;
  assign fifo_tkeep_w = state == EP_SEND ? dat_tkeep_i : 1'b1;
  assign fifo_tlast_w = state == EP_SEND ? dat_tlast_i : lst_q;
  assign fifo_tdata_w = state == EP_SEND ? dat_tdata_i : dat_w;

  assign usb_tvalid_o = xmit == TX_SEND && ulpi_tvalid_w || xmit == TX_NONE;
  assign ulpi_tready_w = xmit == TX_SEND && usb_tready_i;
  assign usb_tkeep_o = xmit == TX_SEND;
  assign usb_tlast_o = xmit == TX_SEND && ulpi_tlast_w || xmit == TX_NONE;
  assign usb_tdata_o = ulpi_tdata_w;

  /**
   * Pipeline some of the control signals.
   */
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
      ready <= ulpi_tvalid_w || xmit == TX_NONE || zdp_q;
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
  reg  [  TSB:0] ticks;
  wire [TBITS:0] dec_w;

  localparam TZERO = {TBITS{1'b0}};
  localparam TONES = {TBITS{1'b1}};

  assign dec_w = ticks - 1;

  // Count the number of wait-states, and timeout if tardy.
  always @(posedge clock) begin
    case (state)
      EP_SEND: ticks <= usb_tvalid_o ? ticks : dec_w[TSB:0];
      default: ticks <= TONES;
    endcase
  end

  /**
   * End-point stall handling, in response to invalid commands.
   */
  always @(posedge clock) begin
    if (clear) begin
      stall <= 1'b0;
    end else if (state == EP_SEND && ticks == TZERO) begin
      stall <= 1'b1;
    end
  end

  /**
   * Enable the packet-FIFO, if we are bypassing (USB) Bulk-In data to ULPI, and
   * then deassert once we have sent the response back to the USB host.
   */
  always @(posedge clock) begin
    if (clear || mmio_done_i) begin
      enb_q <= 1'b1;
    end else if (mmio_send_i || mmio_recv_i) begin
      enb_q <= 1'b0;
    end
  end

  /**
   * Strobe `resp=HIGH` when we have successfully sent a reponse-frame.
   */
  always @(posedge clock) begin
    if (!clear && state == EP_RESP && ack_recv_i) begin
      resp <= 1'b1;
    end else begin
      resp <= 1'b0;
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
  reg  [15:0] val_q;
  wire [16:0] val_w;

  assign val_w = state == EP_IDLE ? cmd_len_i + 1 : val_q - 1;

  always @(posedge clock) begin
    if (clear) begin
      val_q <= 16'bx;
    end else if (cmd_vld_i) begin
      case (state)
        EP_IDLE:
        if (cmd_rdy_i) begin
          val_q <= cmd_dir_i ? cmd_val_i : cmd_len_i;
        end else if (ack_sent_i) begin
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
  reg  [ 2:0] idx_q;
  wire [55:0] out_w;
  wire [ 3:0] idx_w;

  assign idx_w = idx_q - 1;
  assign out_w = {cmd_tag_i, `CMD_SUCCESS, val_q, "T", "R", "A", "T"};
  assign dat_w = out_q[7:0];

  always @(posedge clock) begin
    if (clear) begin
      vld_q <= 1'b0;
      lst_q <= 1'b0;
      idx_q <= 3'd0;
      out_q <= 56'bx;
    end else begin
      case (state)
        EP_RESP:
        if (idx_q != 3'd0) begin
          vld_q <= !(fifo_tready_w && idx_q == 3'd1);
          if (fifo_tready_w) begin
            lst_q <= idx_q == 3'd2;
            idx_q <= idx_w[2:0];
            out_q <= {8'bx, out_q[55:8]};
          end
        end
        default: begin
          vld_q <= 1'b0;
          lst_q <= 1'b0;
          idx_q <= 3'd7;
          out_q <= out_w;
        end
      endcase
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
        EP_IDLE:
        if (mmio_send_i) begin
          state <= EP_RESP;
        end else if (mmio_recv_i) begin
          state <= EP_SEND;
        end
        EP_SEND: state <= sent ? EP_RESP : state;
        EP_RESP: state <= resp ? EP_IDLE : state;
        EP_HALT: state <= state;
      endcase
    end
  end


  //
  // Chop-up large transfers into the (configured) USB frame-size, and send a
  // ZDP, if transfer ends on a USB frame-boundary.
  //
  reg [CSB:0] rcount, scount;
  wire [CBITS:0] rcnext, scnext;
  wire rmax_w, smax_w;

  /**
   * Receive Counter.
   */
  assign rcnext = fifo_tlast_w ? {1'b0, CZERO} : rcount + 1;

  always @(posedge clock) begin
    if (clear) begin
      rcount <= CZERO;
    end else if (fifo_tvalid_w && fifo_tready_w) begin
      rcount <= rcnext[CSB:0];
    end
  end

  /**
   * Transmit (or, Send) Counter.
   */
  assign scnext = usb_tlast_o ? {1'b0, CZERO} : scount + 1;

  always @(posedge clock) begin
    if (clear) begin
      scount <= CZERO;
    end else if (usb_tvalid_o && usb_tready_i) begin
      scount <= scnext[CSB:0];
    end
  end


  //
  // Logic for sending USB data as USB frames, via the `ulpi_encoder`.
  //
  assign rmax_w = rcount == CMAX;  // Todo
  // assign rmax_w = rcount & max_size_i == max_size_i;
  assign smax_w = scount == CMAX;  // Todo
  // assign smax_w = scount & max_size_i == max_size_i;

  // assign save_w = dat_tvalid_i && dat_tready_o && (dat_tlast_i || rmax_w);
  assign save_w = fifo_tvalid_w && fifo_tready_w && (fifo_tlast_w || rmax_w);
  assign redo_w = xmit == TX_WAIT && selected_i && timedout_i;
  assign next_w = xmit == TX_WAIT && selected_i && ack_recv_i;

  /**
   * Todo:
   *  - generate 'SAVE' strobes once enough data for a full USB frame exists in
   *    the packet FIFO;
   *  - issue 'NEXT' strobes when each 'ACK' is received, after a 'DATA IN'
   *    transaction;
   *  - repeat data-transmissions, via 'REDO' strobes, on 'ACK' timeouts;
   */
  always @(posedge clock) begin
    if (clear) begin
      {next_q, redo_q, save_q} <= 3'b000;
    end else begin
      case (state)
        EP_IDLE: {next_q, redo_q, save_q} <= 3'b000;
        EP_HALT: {next_q, redo_q, save_q} <= 3'b000;
        default: {next_q, redo_q, save_q} <= {next_w, redo_w, save_w};
      endcase
    end
  end

  /**
   * FSM for sending USB frames.
   */
  always @* begin
    snxt = xmit;

    case (xmit)
      TX_IDLE:
      if (mmio_send_i) begin
        snxt = TX_SEND;
      end

      // Transferring data from source to USB encoder (via the packet FIFO).
      TX_SEND:
      if (ulpi_tvalid_w && usb_tready_i && ulpi_tlast_w) begin
        snxt = TX_WAIT;
      end

      // After sending a packet, wait for an ACK/ERR response.
      TX_WAIT:
      if (selected_i && ack_recv_i) begin
        snxt = zdp_q ? TX_NONE : TX_IDLE;
      end else if (selected_i && timedout_i) begin
        snxt = TX_REDO;
      end

      // Rest of packet has already been sent, so transmit a ZDP
      TX_NONE:
      if (usb_tvalid_o && usb_tready_i && usb_tlast_o) begin
        snxt = TX_WAIT;
      end

      // Repeat the previous packet(-chunk), as an 'ACK' was not received.
      TX_REDO:
      if (selected_i) begin
        snxt = zdp_q ? TX_NONE : TX_SEND;  // Todo
      end
    endcase

    if (en_q != 1'b1 || ENABLED != 1) begin
      snxt = TX_IDLE;
    end
  end

  assign sent_w = usb_tvalid_o && usb_tready_i && usb_tlast_o && !smax_w;

  always @(posedge clock) begin
    xmit <= snxt;
    sent <= sent_w;

    // Todo: how to handle time-outs (while waiting for USB 'ACK')?
    if (clear || xmit == TX_WAIT && ack_recv_i) begin
      zdp_q <= 1'b0;
    end else if (smax_w && usb_tvalid_o && usb_tready_i && usb_tlast_o) begin
      zdp_q <= 1'b1;
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
      .reset(enb_q),

      .level_o(),

      .drop_i(1'b0),
      .save_i(save_q),
      .redo_i(redo_q),
      .next_i(next_q),

      .s_tvalid(fifo_tvalid_w),
      .s_tready(fifo_tready_w),
      .s_tlast (fifo_tlast_w),
      .s_tkeep (fifo_tkeep_w),
      .s_tdata (fifo_tdata_w),

      .m_tvalid(ulpi_tvalid_w),
      .m_tready(ulpi_tready_w),
      .m_tlast (ulpi_tlast_w),
      .m_tdata (ulpi_tdata_w)
  );


`ifdef __icarus
  //
  //  Simulation Only
  ///
  reg [39:0] dbg_state, dbg_xmit;

  always @* begin
    case (xmit)
      TX_IDLE: dbg_xmit = "IDLE";
      TX_SEND: dbg_xmit = "SEND";
      TX_WAIT: dbg_xmit = "WAIT";
      TX_NONE: dbg_xmit = "NONE";
      TX_REDO: dbg_xmit = "REDO";
      default: dbg_xmit = " ?? ";
    endcase
    case (state)
      EP_IDLE: dbg_state = "IDLE";
      EP_SEND: dbg_state = "SEND";
      EP_RESP: dbg_state = "RESP";
      EP_HALT: dbg_state = "HALT";
      default: dbg_state = " ?? ";
    endcase
  end

`endif  /* __icarus */

endmodule  /* mmio_ep_in */
