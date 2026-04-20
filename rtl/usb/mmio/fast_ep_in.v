`timescale 1ns / 100ps
//
// Data and command-responses for USB MMIO logic-core, that presents a Bulk-Only
// Transport (BOT) inspired interface connecting AXI and APB buses to USB.
//
// Note(s):
//  - Some errors may 'STALL' this end-point, which will require using the
//    control-pipe to reset/re-enable the end-point.
//
module fast_ep_in #(
    parameter integer TIMEOUT = 256,
    localparam integer TBITS = $clog2(256),
    localparam integer TSB = TBITS - 1,
    parameter MAX_PACKET_LENGTH = 512,  // For HS-mode
    localparam CBITS = $clog2(MAX_PACKET_LENGTH),
    localparam CSB = CBITS - 1,
    localparam CZERO = {CBITS{1'b0}},
    localparam CMAX = {CBITS{1'b1}},
    parameter PACKET_FIFO_WIDTH = 32,
    localparam MSB = PACKET_FIFO_WIDTH - 1,
    parameter PACKET_FIFO_DEPTH = 512,
    localparam PBITS = $clog2(PACKET_FIFO_DEPTH),
    localparam PSB = PBITS - 1,
    localparam PZERO = {PBITS{1'b0}},
    // localparam USB_STREAM_WIDTH = PACKET_FIFO_WIDTH,
    // localparam USB = USB_STREAM_WIDTH - 1,
    parameter [31:0] MAGIC = "TART",
    parameter ENABLED = 1  // Todo
) (
    input aresetn,  // Global, asynchronous reset

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
    output mmio_next_o,

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
    output [7:0] usb_tdata_o,

    // Bulk-In domain clock & reset signals
    input dat_clk,
    input dat_rst,

    // From Bulk-In data source (AXI, via AXI-S)
    input dat_tvalid_i,
    output dat_tready_o,
    input dat_tkeep_i,
    input dat_tlast_i,
    input [MSB:0] dat_tdata_i
);

  // Todo:
  `define CMD_SUCCESS 4'h0
  `define CMD_FAILURE 4'h1
  `define CMD_INVALID 4'hF

  // -- AXI/data clock-domain AXIS signals -- //

  wire p_svalid_w, p_sready_w, p_skeep_w, p_slast_w;
  wire [USB:0] p_sdata_w;

  wire a_tvalid_w, a_tready_w, a_tkeep_w, a_tlast_w;
  wire [7:0] a_tdata_w;

  // -- USB clock-domain AXIS signals -- //

  wire u_tvalid_w, u_tready_w, u_tkeep_w, u_tlast_w;
  wire r_tvalid_w, r_tready_w, r_tkeep_w, r_tlast_w;
  wire ulpi_tvalid_w, ulpi_tready_w, ulpi_tkeep_w, ulpi_tlast_w;
  wire [7:0] u_tdata_w, r_tdata_w, ulpi_tdata_w;

  // -- Top-level USB 'Bulk In' end-point (EP) state-machine -- //

  reg [4:0] xmit, snxt;
  localparam [4:0] TX_IDLE = 5'h01, TX_SEND = 5'h02, TX_WAIT = 5'h04;
  localparam [4:0] TX_NONE = 5'h08, TX_REDO = 5'h10;

  // -- USB datapath I/O assignments -- //

  assign usb_tvalid_o  = xmit == TX_SEND && ulpi_tvalid_w || xmit == TX_NONE;
  assign ulpi_tready_w = xmit == TX_SEND && usb_tready_i;
  assign usb_tkeep_o   = xmit == TX_SEND;
  assign usb_tlast_o   = xmit == TX_SEND && ulpi_tlast_w || xmit == TX_NONE;
  assign usb_tdata_o   = ulpi_tdata_w;

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
      ready <= ulpi_tvalid_w || xmit == TX_NONE;
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
    if (clear || sent || mmio_done_i) begin
      // if (clear || mmio_done_i) begin
      enb_q <= 1'b1;
    end else if (mmio_send_i || mmio_recv_i) begin
      enb_q <= 1'b0;
    end
  end

  /**
   * Strobe `resp=HIGH` when we have successfully sent a reponse-frame.
   */
  always @(posedge clock) begin
    if (!clear && state == EP_RESP && idx_q == 0 && ack_recv_i) begin
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
  reg end_q;
  reg [15:0] val_q;
  wire [16:0] val_w;

  assign val_w = state == EP_IDLE ? cmd_len_i + 1 : val_q - 1;

  always @(posedge clock) begin
    if (clear) begin
      end_q <= 1'b0;
      val_q <= 16'bx;
    end else if (cmd_vld_i) begin
      case (state)
        EP_IDLE:
        if (cmd_rdy_i) begin
          val_q <= cmd_dir_i ? cmd_val_i : cmd_len_i;
        end else if (ack_sent_i) begin
          val_q <= val_w[15:0];
        end

        EP_SEND:  // Todo: 'val_q'??
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
        EP_SEND: state <= next ? EP_IDLE : state;
        EP_RESP: state <= resp ? EP_IDLE : state;
        EP_HALT: state <= state;
      endcase
    end
  end

  /**
   * Narrows the 32-bit AXI stream to an 8-bit stream (for USB).
   */
  axis_adapter #(
      .S_DATA_WIDTH(DATA_WIDTH),
      .S_KEEP_ENABLE(1),
      .S_KEEP_WIDTH(STROBES),
      .M_DATA_WIDTH(8),
      .M_KEEP_ENABLE(1),
      .M_KEEP_WIDTH(1),
      .ID_ENABLE(0),
      .ID_WIDTH(1),
      .DEST_ENABLE(0),
      .DEST_WIDTH(1),
      .USER_ENABLE(0),
      .USER_WIDTH(1)
  ) U_ADAPT1 (
      .clk(dat_clk),
      .rst(dat_rst),

      .s_axis_tvalid(p_svalid_w),
      .s_axis_tready(p_sready_w),
      .s_axis_tkeep(p_skeep_w),
      .s_axis_tlast(p_slast_w),
      .s_axis_tid(1'b0),
      .s_axis_tdest(1'b0),
      .s_axis_tuser(1'b0),
      .s_axis_tdata(p_sdata_w),  // AXI input

      .m_axis_tvalid(a_tvalid_w),
      .m_axis_tready(a_tready_w),
      .m_axis_tkeep(a_tkeep_w),
      .m_axis_tlast(a_tlast_w),
      .m_axis_tid(),
      .m_axis_tdest(),
      .m_axis_tuser(),
      .m_axis_tdata(a_tdata_w)  // AXI output
  );

  /**
   * Cross domains for the fetched AXI data.
   */
  axis_afifo #(
      .WIDTH(8),
      .TLAST(1),
      .ABITS(4)
  ) U_AFIFO1 (
      .aresetn(aresetn),

      .s_aclk  (dat_clk),
      .s_tvalid(a_tvalid_w),
      .s_tready(a_tready_w),
      .s_tlast (a_tlast_w),
      .s_tdata (a_tdata_w),

      .m_aclk  (cmd_clk),
      .m_tvalid(u_tvalid_w),
      .m_tready(u_tready_w),
      .m_tlast (u_tlast_w),
      .m_tdata (u_tdata_w)
  );

  //
  //  USB Datapath Multiplexor
  ///

  axis_mux #(
      .S_COUNT(2),
      .DATA_WIDTH(8),
      .KEEP_ENABLE(1),
      .KEEP_WIDTH(1),
      .ID_ENABLE(0),
      .ID_WIDTH(1),
      .DEST_ENABLE(0),
      .DEST_WIDTH(1),
      .USER_ENABLE(0),
      .USER_WIDTH(1)
  ) U_MUX1 (
      .clk(cmd_clk),
      .rst(cmd_rst),

      .enable(mux_en_w),
      .select(mux_sel_w),

      .s_axis_tvalid({u_tvalid_w, r_tvalid_w}),
      .s_axis_tready({u_tready_w, r_tready_w}),
      .s_axis_tkeep ({u_tkeep_w, r_tkeep_w}),
      .s_axis_tlast ({u_tlast_w, r_tlast_w}),
      .s_axis_tuser (2'bx),
      .s_axis_tid   (2'bx),
      .s_axis_tdest (2'bx),
      .s_axis_tdata ({u_tdata_w, r_tdata_w}),

      .m_axis_tvalid(ulpi_tvalid_w),
      .m_axis_tready(ulpi_tready_w),
      .m_axis_tkeep (ulpi_tkeep_w),
      .m_axis_tlast (ulpi_tlast_w),
      .m_axis_tuser (),
      .m_axis_tid   (),
      .m_axis_tdest (),
      .m_axis_tdata (ulpi_tdata_w)
  );

endmodule  /* fast_ep_in */
