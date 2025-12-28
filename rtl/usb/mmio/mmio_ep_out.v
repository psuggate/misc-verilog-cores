`timescale 1ns / 100ps
//
// Parser for USB Bulk-Only Transport (BOT) Command Block Wrapper (CBW) frames.
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
    parameter ENABLED = 1
) (
    input clock,
    input reset,

    input set_conf_i,           // From CONTROL PIPE0
    input clr_conf_i,           // From CONTROL PIPE0
    input [CSB:0] max_size_i,   // From CONTROL PIPE0

    input selected_i,  // From USB controller
    input rx_error_i,  // Timed-out or CRC16 error
    input ack_sent_i,

    output ep_ready_o,
    output stalled_o,   // If invariants violated
    output parity_o,

    // From MMIO controller
    input mmio_busy_i,  // Todo: what do I want?
    input mmio_done_i,

    // USB command, and WRITE, packet stream (Bulk-In pipe, AXI-S)
    input usb_tvalid_i,
    output usb_tready_o,
    input usb_tkeep_i,
    input usb_tlast_i,
    input [7:0] usb_tdata_i,

    // Decoded command (APB, or AXI)
    output cmd_vld_o,
    output cmd_dir_o,
    output cmd_apb_o,
    input cmd_ack_i,
    output [3:0] cmd_tag_o,
    output [15:0] cmd_len_o,
    output [3:0] cmd_lun_o,
    output [27:0] cmd_adr_o,

    // Pass-through data stream, from USB (Bulk-Out, via AXI-S)
    output dat_tvalid_o,
    input dat_tready_i,
    output dat_tlast_o,
    output [7:0] dat_tdata_o
);

  reg stall, bypass;
  reg cyc, stb, lst, rdy;
  reg vld, dir, enb, byp;
  reg apb;
  reg [31:0] adr;
  wire skid_ready_w, vld_w;

  localparam [7:0] MAGIC0 = "T", MAGIC1 = "A", MAGIC2 = "R", MAGIC3 = "T";

  // States for the entire end-point (EP).
  localparam [3:0] EP_IDLE = 4'h1, EP_XFER = 4'h2, EP_RESP = 4'h4, EP_HALT = 4'h8;

  localparam [4:0] ST_IDLE = 5'd0, ST_SIG1 = 5'd1, ST_SIG2 = 5'd2, ST_SIG3 = 5'd3;
  localparam [4:0] ST_TAG0 = 5'd4, ST_TAG1 = 5'd5, ST_TAG2 = 5'd6, ST_TAG3 = 5'd7;
  localparam [4:0] ST_LEN0 = 5'd8, ST_LEN1 = 5'd9, ST_LEN2 = 5'd10, ST_LEN3 = 5'd11;
  localparam [4:0] ST_FLAG = 5'd12, ST_DLUN = 5'd13, ST_BLEN = 5'd14, ST_SEND = 5'd15;
  localparam [4:0] ST_WAIT = 5'd16, ST_DATO = 5'd17, ST_DATI = 5'd18, ST_FAIL = 5'd19;

  assign stalled_o = stall;

  assign usb_tready_o = byp ? skid_ready_w : rdy;

  assign cmd_vld_o = vld;
  assign cmd_dir_o = dir;  // 1: Bulk-In (device to host)
  assign cmd_tag_o = tag;
  assign cmd_len_o = len;
  assign cmd_lun_o = lun;
  assign cmd_adr_o = adr;

  //
  // MMIO command parser.
  //
  // Note(s):
  //  - A valid command is exactly 11 bytes long.
  //  - Format: "TART" (4B), address (4B), length/value (2B), command+tag (1B).
  //  - Must terminate with 'tlast=1'; i.e., one command in a USB frame, and the
  //    payload must be 11 bytes, only.
  //
  reg cmd_valid_q, cmd_error_q, resp_sent_q;
  reg u16_c, u32_c, cmd_c, end_c, byp_c, bad_c;
  reg [5:0] parse;

  // MMIO command parser states.
  localparam [5:0] MM_IDLE = 6'h01, MM_ADDR = 6'h02, MM_WORD = 6'h04, MM_IDOP = 6'h08;
  localparam [5:0] MM_DROP = 6'h10, MM_HALT = 6'h20;

  /**
   * Pipeline the incoming, streamed, USB data (and handshaking signals).
   */
  always @(posedge clock) begin
    if (reset || mmio_busy_i || !selected_i) begin
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
      stb <= 1'b0;
      lst <= 1'b0;
    end
  end

  always @(posedge clock) begin
    if (reset || mmio_busy_i || !selected_i) begin
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
    if (reset || !selected_i || mmio_busy_i) begin
      dat32 <= 32'bx;
      sel   <= 2'd0;
    end else if (usb_tvalid_i && usb_tready_o) begin
      dat32 <= {usb_tdata_i, dat32[31:8]};
      sel   <= usb_tlast_i ? 2'd0 : sel_w[1:0];
    end
  end

  always @* begin
    u16_c = cyc && stb && sel == 2'd2;
    u32_c = cyc && stb && sel == 2'd0;
    cmd_c = u32_c && dat32 == "TART";
    end_c = cyc && stb && lst;
    byp_c = dat32[27:26] == 2'b00;
    bad_c = !cyc || stb && !lst;
  end

  /**
   * Capture the address (and LUN).
   */
  always @(posedge clock) begin
    if (selected_i && !stall) begin
      case (parse)
        MM_ADDR:
          if (cyc && stb && sel == 2'd0) {lun, adr} <= dat32;
          else {lun, adr} <= {lun, adr};
        default: {lun, adr} <= {lun, adr};
      endcase
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
    if (reset || clr_conf_i || set_conf_i) begin
      parse <= MM_IDLE;
    end else if (bypass) begin
      parse <= MM_BUSY;
    end else if (selected_i) begin
      case (parse)
        // If the first four bytes match "TART", then parse a command packet.
        MM_IDLE:
          if (cyc && stb && sel == 2'd0) parse <= MM_ADDR;
          else if (!cyc && sel != 2'd0) parse <= MM_FAIL;

        // Extract the 32-bit address from the packet.
        MM_ADDR:
          if (!cyc) parse <= MM_FAIL;
          else if (stb && sel == 2'd0) parse <= MM_WORD;

        // Then 16-bits which is either a length, or a word to send over APB.
        MM_WORD:
          if (!cyc) parse <= MM_FAIL;
          else if (stb && sel == 2'd2) parse <= MM_IDOP;

        // Last byte is 4-bit tag, and 4-bit command/op.
        MM_IDOP:
          if (!cyc || stb && !lst) parse <= MM_FAIL;
          else if (stb) parse <= MM_BUSY;

        // Wait for transaction to complete.
        MM_BUSY: parse <= parse;

        // Wait for end-point to be reset.
        MM_FAIL: parse <= parse;
      endcase
    end
  end


  //
  // Top-level FSM.
  //
  reg [3:0] state;
  reg [CSB:0] count;
  wire [CBITS:0] cprev_w;
  wire czero_w, zdp_w;

  assign zdp_w = cyc && !stb && lst;
  assign end_w = cyc && stb && lst && !czero_w;

  /**
   * End-point stall handling, in response to invalid commands.
   */
  always @(posedge clock) begin
    if (reset || clr_conf_i) begin
      stall <= 1'b0;
    end else if (parse == MM_FAIL) begin
      stall <= 1'b1;
    end
  end

  /**
   * Set the AXI-stream to bypass USB frames, until the Bulk-Out phase has been
   * completed.
   */
  always @(posedge clock) begin
    if (reset || stall) begin
      bypass <= 1'b0;
    end else begin
      case (parse)
        MM_IDOP:
          if (cyc && stb && lst && dat32[27:26] == 2'b00) bypass <= 1'b1;
          else bypass <= 1'b0;

        MM_BUSY:
          if (bypass && (zdp_w || end_w)) bypass <= 1'b0;
          else bypass <= bypass;

        default:
          bypass <= 1'b0;
      endcase
    end
  end

  /**
   * Detect the end of the data-transfer phase by counting bytes per USB frame,
   * or arrival of a ZDP (Zero-Data Packet).
   */
  assign cprev_w = count - 1;
  assign czero_w = count == CZERO;

  always @(posedge clock) begin
    case (state)
      EP_XFER: begin
        if (bypass && cyc && stb) begin
          count <= cprev[CSB:0];
        end else begin
        end
      end

      default:
        count <= CMAX;
    endcase
  end

  always @(posedge clock) begin
    if (reset || stall) begin
      state <= EP_IDLE;
    end else if (cmd_error_q) begin
      state <= EP_HALT;
    end else begin
      case (state)
        EP_IDLE: state <= cmd_valid_q ? EP_XFER : state;
        EP_XFER: state <= mmio_done_i ? EP_RESP : state;
        EP_RESP: state <= resp_sent_q ? EP_IDLE : state;
        EP_HALT: state <= set_conf_i ? EP_IDLE : state;
      endcase
    end
  end

  //
  // Main state machine.
  //
  always @(posedge clock) begin
    if (reset == 1'b1) begin
      apb   <= 1'bx;
      err   <= 1'b0;
      state <= ST_IDLE;
    end else begin
      case (state)
        ST_IDLE: begin
          apb <= 1'b0;
          err <= 1'b0;
          if (cyc && stb && sel == 2'd0 && dat32 == "TART") begin
            state <= ST_ADDR;
          end
        end

        ST_ADDR:
        if (!cyc) begin
          state <= ST_FAIL;
          err   <= 1'b1;
        end else if (stb && sel == 2'd0) begin
          state <= ST_WORD;
        end

        ST_WORD:
        if (!cyc) begin
          state <= ST_FAIL;
          err   <= 1'b1;
        end else if (stb && sel == 2'd2) begin
          state <= ST_IDOP;
          len   <= dat32[31:16];
        end

        ST_IDOP:
        if (cyc && !stb) begin
          state <= state;
        end else if (!cyc || !lst) begin
          state <= ST_FAIL;
          err   <= 1'b1;
        end else begin
          tag <= dat32[31:28];
          dir <= dat32[27];
          if (dat32[26]) begin
            state <= ST_CTRL;
            apb   <= 1'b1;
            byp   <= 1'b0;
            enb   <= 1'b1;
          end else begin
            state <= ST_DATA;
            apb   <= 1'b0;
            byp   <= ~dat32[27];
            enb   <= dat32[27];
          end
        end

        ST_CTRL: begin
          // Todo: Issue control command, over APB.
          state <= ST_DONE;
        end

        ST_DATA: begin
          // Todo: Issue memory/data command, over AXI.
          if (cmd_ack_i) begin
            state <= ST_BUSY;
          end
        end

        /**
         * Pass through write-data, and only asserting 'tlast' once all data
         * has been received, as indicated by either: a ZDP; or a USB frame
         * that is smaller than the max. frame-length.
         */
        ST_THRU:
        if (!cyc) begin
          state <= ST_BUSY;
        end

        ST_BUSY:
        if (mmio_done_i) begin
          state <= ST_IDLE;
        end

        ST_FAIL:
        if (clr_conf_i) begin
          state <= ST_IDLE;
          err   <= 1'b0;
        end

      endcase
    end
  end

  //
  // Command validation and dispatch.
  //
  always @(posedge clock) begin
    if (reset == 1'b1 || cmd_ack_i == 1'b1) begin
      vld <= 1'b0;
    end else begin
      case (state)
        ST_IDLE: vld <= 1'b0;
        ST_FAIL: vld <= 1'b0;
        ST_BLEN: vld <= usb_tvalid_i && vld_w;
        default:
        if (cmd_ack_i) begin
          vld <= 1'b0;
        end
      endcase
    end
  end

  initial begin
    byp   <= 1'b0;
    enb   <= 1'b1;
    rdy   <= 1'b0;
    dir   <= 1'bx;
    tag <= 4'bx;
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
      .reset(rst_q),

      .level_o(level_w),

      .drop_i(rx_error_i),
      .save_i(ack_sent_i),
      .redo_i(1'b0),
      .next_i(1'b0),

      .s_tvalid(tvalid_w),
      .s_tready(tready_w),
      .s_tkeep (s_tkeep),
      .s_tlast (s_tlast),
      .s_tdata (s_tdata),

      .m_tvalid(dat_tvalid_o),
      .m_tready(dat_tready_i),
      .m_tlast (dat_tlast_o),
      .m_tdata (dat_tdata_o)
  );


endmodule  /* mmio_ep_out */
