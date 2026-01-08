`timescale 1ns / 100ps
//
// Command parser-, and Bulk-Out data-, end-point for the USB MMIO logic-core,
// that presents a Bulk-Only Transport (BOT) inspired interface connecting AXI
// and APB buses to USB.
//
// Note(s):
//  - Some errors may 'STALL' this end-point, which will require using the
//    control-pipe to reset/re-enable the end-point.
//
module mmio_ep_out #(
    parameter MAX_PACKET_LENGTH = 512,  // For HS-mode
    localparam CBITS = $clog2(MAX_PACKET_LENGTH),
    localparam CSB = CBITS - 1,
    localparam CZERO = {CBITS{1'b0}},
    localparam CMAX = {CBITS{1'b1}},
    parameter PACKET_FIFO_DEPTH = 2048,
    localparam PBITS = $clog2(PACKET_FIFO_DEPTH),
    localparam PSB = PBITS - 1,
    // Icarus/Verilog seems to use wrong-endian by default?
    parameter [7:0] MAGIC0 = "T",
    parameter [7:0] MAGIC1 = "A",
    parameter [7:0] MAGIC2 = "R",
    parameter [7:0] MAGIC3 = "T",
    localparam [31:0] MAGIC = {MAGIC3, MAGIC2, MAGIC1, MAGIC0},
    // parameter [31:0] MAGIC = "TART",
    parameter ENABLED = 1
) (
    input clock,
    input reset,

    input           set_conf_i,  // From CONTROL PIPE0
    input           clr_conf_i,  // From CONTROL PIPE0
    input [CBITS:0] max_size_i,  // From CONTROL PIPE0

    input selected_i,  // From USB controller
    input rx_error_i,  // Timed-out or CRC16 error
    input ack_sent_i,

    output ep_ready_o,
    output stalled_o,   // If invariants violated
    output parity_o,

    // From MMIO controller
    input  mmio_busy_i,  // Todo: what do I want?
    output mmio_recv_o,
    input  mmio_sent_i,
    input  mmio_resp_i,
    input  mmio_done_i,

    // USB command, and WRITE, packet stream (Bulk-In pipe, AXI-S)
    input usb_tvalid_i,
    output usb_tready_o,
    input usb_tkeep_i,
    input usb_tlast_i,
    input [7:0] usb_tdata_i,

    // Decoded command (APB, or AXI)
    output cmd_vld_o,
    input cmd_ack_i,
    output cmd_dir_o,
    output cmd_apb_o,
    output [1:0] cmd_cmd_o,
    output [3:0] cmd_tag_o,
    output [15:0] cmd_len_o,
    output [3:0] cmd_lun_o,
    output [27:0] cmd_adr_o,

    // Pass-through data stream, from USB (Bulk-Out, via AXI-S)
    output dat_tvalid_o,
    input dat_tready_i,
    output dat_tkeep_o,
    output dat_tlast_o,
    output [7:0] dat_tdata_o
);

  reg stall, clear, en_q, ready, avail, bypass, parity, rxd_q, recvd;
  reg cyc, stb, lst, rdy;
  reg vld, dir, enb, apb;
  reg drop_q, save_q, recv_q;
  reg [ 1:0] cmd;
  reg [27:0] adr;
  reg [15:0] len;
  reg [3:0] tag, lun;
  wire fifo_tready_w;

  // MMIO command parser states.
  localparam [5:0] MM_IDLE = 6'h01, MM_ADDR = 6'h02, MM_WORD = 6'h04, MM_IDOP = 6'h08;
  localparam [5:0] MM_BUSY = 6'h10, MM_HALT = 6'h20;

  // Top-level states for the high-level control of this end-point (EP).
  localparam [3:0] EP_IDLE = 4'h1, EP_RECV = 4'h2, EP_RESP = 4'h4, EP_HALT = 4'h8;

  assign stalled_o = stall;
  assign ep_ready_o = ready;
  assign parity_o = parity;
  assign mmio_recv_o = recvd;
  assign usb_tready_o = bypass ? fifo_tready_w : rdy;
  assign dat_tkeep_o = dat_tvalid_o;

  assign cmd_vld_o = vld;
  assign cmd_cmd_o = cmd;
  assign cmd_dir_o = dir;  // 1: Bulk-In (device to host)
  assign cmd_apb_o = apb;  // 1: send/recieve 16-bit value, via APB
  assign cmd_tag_o = tag;  // Identifier for the transaction
  assign cmd_len_o = len;
  assign cmd_lun_o = lun;
  assign cmd_adr_o = adr;

  /**
   * Pipeline some of the control signals.
   */
  wire avail_w;
  wire [PSB:0] level_w, space_w;

  assign space_w = PACKET_FIFO_DEPTH - level_w;
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
      ready <= avail_w;
    end

    // USB end-point parity-bit logic.
    if (clear) begin
      parity <= 1'b0;
    end else if (selected_i && ack_sent_i) begin
      parity <= ~parity;
    end
  end


  //
  // MMIO command parser.
  //
  // Note(s):
  //  - A valid command is exactly 11 bytes long.
  //  - Format: "TART" (4B), address (4B), length/value (2B), command+tag (1B).
  //  - Must terminate with 'tlast=1'; i.e., one command in a USB frame, and the
  //    payload must be 11 bytes, only.
  //
  reg [5:0] parse;

  /**
   * Pipeline the incoming, streamed, USB data (and handshaking signals).
   */
  always @(posedge clock) begin
    if (clear || mmio_busy_i || !selected_i) begin
      cyc <= 1'b0;
      stb <= 1'b0;
      lst <= 1'b0;
    end else if (!cyc && usb_tvalid_i && usb_tready_o) begin
      cyc <= 1'b1;
      stb <= usb_tkeep_i;
      lst <= usb_tlast_i;
    end else if (cyc && stb && lst) begin
      cyc <= 1'b0;
      stb <= 1'b0;
      lst <= 1'b0;
    end else begin
      stb <= usb_tvalid_i & usb_tready_o;
      lst <= usb_tvalid_i & usb_tready_o & usb_tlast_i;
    end
  end

  always @(posedge clock) begin
    if (clear || mmio_busy_i || !selected_i) begin
      rdy <= 1'b0;
    end else if (parse == MM_IDLE) begin
      rdy <= 1'b1;
    end else if (usb_tvalid_i && usb_tready_o && usb_tlast_i) begin
      rdy <= 1'b0;
    end
  end

  /**
   * Demultiplex the incoming byte data, to 32-bit (d)words.
   */
  reg  [31:0] dat32;
  reg  [ 1:0] sel;
  wire [ 2:0] sel_w = sel + 1;

  always @(posedge clock) begin
    if (clear || mmio_busy_i || !selected_i) begin
      dat32 <= 32'bx;
      sel   <= 2'd0;
    end else if (usb_tvalid_i && usb_tready_o) begin
      dat32 <= {usb_tdata_i, dat32[31:8]};
      sel   <= usb_tlast_i ? 2'd0 : sel_w[1:0];
    end
  end

  /**
   * Capture the address (and LUN), length/value (word), tag, and op.
   */
  always @(posedge clock) begin
    if (cyc && stb) begin
      case (parse)
        MM_ADDR: if (sel == 2'd0) {lun, adr} <= dat32;
        MM_WORD: if (sel == 2'd2) len <= dat32[31:16];
        MM_IDOP: if (lst) {tag, dir, apb, cmd} <= dat32[31:24];
      endcase
    end
  end

  /**
   * Command validation and dispatch.
   */
  always @(posedge clock) begin
    if (clear || stall || cmd_ack_i || mmio_done_i || mmio_resp_i) begin
      vld <= 1'b0;
    end else if (parse == MM_IDOP && cyc && stb && lst) begin
      vld <= 1'b1;
    end
  end

  /**
   * Parser FSM for MMIO commands, and after a transaction starts, waits as
   * data is passed through to other functional-units (if a SET or STORE) has
   * been requested.
   * 
   * Note(s):
   *  - Data transfer phase is terminated by receiving either: a ZDP; or a USB
   *    frame that is smaller than the max. frame-length.
   *  - If any invalid sequences are received, then wait for recovery.
   * 
   */
  always @(posedge clock) begin
    if (clear) begin
      parse <= MM_IDLE;
    end else if (bypass) begin
      parse <= MM_BUSY;
    end else if (selected_i) begin
      case (parse)
        // If the first four bytes match "TART", then parse a command packet.
        MM_IDLE:
        if (cyc && stb && sel == 2'd0 && dat32 == MAGIC) parse <= MM_ADDR;
        else if (!cyc && sel != 2'd0) parse <= MM_HALT;

        // Extract the 32-bit address from the packet.
        MM_ADDR:
        if (!cyc) parse <= MM_HALT;
        else if (stb && sel == 2'd0) parse <= MM_WORD;

        // Then 16-bits which is either a length, or a word to send over APB.
        MM_WORD:
        if (!cyc) parse <= MM_HALT;
        else if (stb && sel == 2'd2) parse <= MM_IDOP;

        // Last byte is 4-bit tag, and 4-bit command/op.
        MM_IDOP:
        if (!cyc || stb && !lst) parse <= MM_HALT;
        else if (stb) parse <= MM_BUSY;

        // Wait for transaction to complete.
        MM_BUSY: parse <= parse;

        // Wait for end-point to be reset.
        MM_HALT: parse <= parse;
      endcase
    end
  end


  //
  // Detect the end of the data-transfer phase by counting bytes per USB frame,
  // or arrival of a ZDP (Zero-Data Packet).
  //
  reg  [  CSB:0] count;
  wire [CBITS:0] cprev_w;
  wire czero_w, cfull_w, zdp_w, end_w;

  assign cprev_w = count - 1;
  assign czero_w = count == CZERO;
  assign cfull_w = count == CMAX;

  assign zdp_w   = cyc && !stb && lst && cfull_w;
  assign end_w   = cyc && stb && lst && !czero_w;

  always @(posedge clock) begin
    if (clear || state != EP_RECV) begin
      count <= CMAX;
      rxd_q <= 1'b0;
    end else if (bypass && cyc) begin
      count <= stb ? cprev_w[CSB:0] : count;
      rxd_q <= lst && (stb && !czero_w || !stb && cfull_w);
    end else begin
      count <= count;
      rxd_q <= rxd_q;
    end

    if (ack_sent_i && rxd_q) begin
      recvd <= 1'b1;
    end else begin
      recvd <= 1'b0;
    end
  end

  /**
   * Set the AXI-stream to bypass USB frames, until the Bulk-Out phase has been
   * completed.
   */
  always @(posedge clock) begin
    if (clear || stall) begin
      bypass <= 1'b0;
    end else begin
      case (parse)
        MM_IDOP:
        if (cyc && stb && lst && dat32[27:26] == 2'b00) bypass <= 1'b1;
        else bypass <= 1'b0;

        MM_BUSY:
        if (bypass && cyc && lst && (!stb || stb && !czero_w)) bypass <= 1'b0;
        else bypass <= bypass;

        default: bypass <= 1'b0;
      endcase
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
    end else if (parse == MM_HALT) begin
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
    end else if (state == EP_RECV && bypass) begin
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
        EP_IDLE: state <= vld ? EP_RECV : state;
        EP_RECV: state <= mmio_sent_i || recvd ? EP_RESP : state;
        EP_RESP: state <= mmio_resp_i ? EP_IDLE : state;
        EP_HALT: state <= state;
      endcase
    end
  end

  /**
   * When we are performing a 'STORE', we need to save each packet (fragment) to
   * the packet-FIFO, so that it can be transferred out. And if there was any
   * problem receiving, then we have to drop that packet (fragment).
   */
  always @(posedge clock) begin
    if (clear || rx_error_i || ack_sent_i || state != EP_RECV) begin
      recv_q <= 1'b0;
    end else if (usb_tvalid_i && usb_tready_o && usb_tlast_i) begin
      recv_q <= 1'b1;
    end

    drop_q <= recv_q && rx_error_i;
    save_q <= recv_q && ack_sent_i;
  end


  //
  // Output packet FIFO, for (STORE) data passed-through from the USB Bulk-Out
  // pipe, and with drop-packet-on-failure.
  //
  packet_fifo #(
      .WIDTH(8),
      .DEPTH(PACKET_FIFO_DEPTH),
      .STORE_LASTS(1),
      .SAVE_ON_LAST(0),  // save only after CRC16 checking
      .LAST_ON_SAVE(1),  // delayed 'tlast', after CRC16-valid
      .NEXT_ON_LAST(1),
      .USE_LENGTH(0),
      .MAX_LENGTH(MAX_PACKET_LENGTH),
      .OUTREG(2)
  ) U_FIFO0 (
      .clock(clock),
      .reset(enb),

      .level_o(level_w),

      .drop_i(drop_q),
      .save_i(save_q),
      .redo_i(1'b0),
      .next_i(1'b0),

      .s_tvalid(usb_tvalid_i),
      .s_tready(fifo_tready_w),
      .s_tkeep (usb_tkeep_i),
      .s_tlast (usb_tlast_i),
      .s_tdata (usb_tdata_i),

      .m_tvalid(dat_tvalid_o),
      .m_tready(dat_tready_i),
      .m_tlast (dat_tlast_o),
      .m_tdata (dat_tdata_o)
  );


`ifdef __icarus
  //
  //  Simulation Only
  ///
  reg [39:0] dbg_state, dbg_parse;

  always @* begin
    case (parse)
      MM_IDLE: dbg_parse = "IDLE";
      MM_ADDR: dbg_parse = "ADDR";
      MM_WORD: dbg_parse = "WORD";
      MM_IDOP: dbg_parse = "IDOP";
      MM_BUSY: dbg_parse = "BUSY";
      MM_HALT: dbg_parse = "HALT";
      default: dbg_parse = " ?? ";
    endcase
    case (state)
      EP_IDLE: dbg_state = "IDLE";
      EP_RECV: dbg_state = "RECV";
      EP_RESP: dbg_state = "RESP";
      EP_HALT: dbg_state = "HALT";
      default: dbg_state = " ?? ";
    endcase
  end

`endif  /* __icarus */

endmodule  /* mmio_ep_out */
