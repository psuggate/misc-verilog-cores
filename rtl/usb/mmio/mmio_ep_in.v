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
    parameter PACKET_FIFO_WIDTH = 32,
    localparam STROBES = PACKET_FIFO_WIDTH / 8,
    localparam MSB = PACKET_FIFO_WIDTH - 1,
    localparam SSB = STROBES - 1,
    parameter PACKET_FIFO_DEPTH = 512,
    localparam PBITS = $clog2(PACKET_FIFO_DEPTH),
    localparam PSB = PBITS - 1,
    localparam PZERO = {PBITS{1'b0}},
    localparam USB_STREAM_WIDTH = PACKET_FIFO_WIDTH,
    localparam USB = USB_STREAM_WIDTH - 1,
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
    input  mmio_send_i,
    output mmio_sent_o,
    input  mmio_resp_i,
    output mmio_resp_o,
    input  mmio_done_i,
    output mmio_next_o,
    output mmio_redo_o,

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

    // Output data stream (via AXI-S, to ULPI encoder)
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
    input [SSB:0] dat_tkeep_i,
    input dat_tlast_i,
    input [MSB:0] dat_tdata_i
);

  localparam TZERO = {TBITS{1'b0}};
  localparam TONES = {TBITS{1'b1}};

  localparam COUNT_BITS = 16 - CBITS;
  localparam MAX_FRAMES = 1 << COUNT_BITS;

  reg en_q, res_q, clear, stall, ready, parity;
  reg none_q, redo_q, sent_q, next_q;
  wire issued_w;

  // -- AXI/data clock-domain AXIS signals -- //

  reg drdy_m, drdy_r;
  wire p_svalid_w, p_sready_w;
  wire a_tvalid_w, a_tready_w, a_tkeep_w, a_tlast_w;
  wire [7:0] a_tdata_w;

  // -- USB clock-domain AXIS signals -- //

  wire u_tvalid_w, u_tready_w, u_tkeep_w, u_tlast_w;
  wire res_tvalid_w, res_tready_w, res_tkeep_w, res_tlast_w;
  wire ulpi_tvalid_w, ulpi_tready_w, ulpi_tkeep_w, ulpi_tlast_w;
  wire [7:0] u_tdata_w, res_tdata_w, ulpi_tdata_w;

  // -- Top-level USB 'Bulk In' end-point (EP) state-machine -- //

  localparam [3:0] ST_IDLE = 1, ST_SEND = 2, ST_RESP = 4, ST_HALT = 8;
  reg [3:0] stage;

  localparam [4:0] TX_IDLE = 5'h01, TX_SEND = 5'h02, TX_WAIT = 5'h04;
  localparam [4:0] TX_NONE = 5'h08, TX_REDO = 5'h10;
  reg [4:0] phase;

  // -- USB datapath I/O assignments -- //

  assign stalled_o = stall;
  assign ep_ready_o = ready;
  assign parity_o = parity;

  assign usb_tvalid_o = phase == TX_SEND && ulpi_tvalid_w || none_q;
  assign ulpi_tready_w = phase == TX_SEND && usb_tready_i;
  assign usb_tkeep_o = phase == TX_SEND && !zero_q;
  assign usb_tlast_o = phase == TX_SEND && ulpi_tlast_w || none_q;
  assign usb_tdata_o = ulpi_tdata_w;

  // -- AXI-Domain I/O Assignments -- //

  // Todo: use a skid-register?
  assign dat_tready_o = drdy_m && p_sready_w;
  assign p_svalid_w = drdy_m && dat_tvalid_i;

  // -- MMIO control-signal assignments -- //

  assign mmio_sent_o = sent_q;
  assign mmio_resp_o = issued_w;
  assign mmio_next_o = next_q;
  assign mmio_redo_o = redo_q;

  // Pipeline some of the control signals.
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
    if (!en_q || !selected_i) begin
      ready <= 1'b0;
    end else begin
      ready <= phase == TX_SEND;
    end

    // USB end-point parity-bit logic.
    if (clear) begin
      parity <= 1'b0;
    end else if (selected_i && ack_sent_i) begin
      parity <= ~parity;
    end
  end

  // -- Bulk-IN Timeout Handler -- //

  reg  [  TSB:0] ticks;
  wire [TBITS:0] dec_w;

  assign dec_w = ticks - 1'b1;

  // Count the number of wait-states, and timeout if tardy.
  always @(posedge clock) begin
    case (stage)
      ST_SEND: ticks <= usb_tvalid_o ? ticks : dec_w[TSB:0];
      default: ticks <= TONES;
    endcase
  end

  // End-point stall handling, in response to invalid commands.
  always @(posedge clock) begin
    if (clear) begin
      stall <= 1'b0;
    end else if (stage == ST_SEND && ticks == TZERO) begin
      stall <= 1'b1;
    end
  end

  // -- USB-Frame Control Signals -- //

  reg xfer_q, succ_q, last_q, done_q;
  reg load_q, busy_q, zero_q, part_q;
  wire sent_w, last_w, done_w, wrap_w;
  wire smax_w, xfer_w, succ_w;

  assign xfer_w = u_tvalid_w && u_tready_w;
  assign succ_w = xfer_w && u_tlast_w;
  assign sent_w = usb_tvalid_o && usb_tready_i && usb_tlast_o;

  // We have been requested to send the 'RESPONSE' packet.
  always @(posedge clock) begin
    res_q <= mmio_resp_i;
  end

  always @(posedge clock) begin
    case (stage)
      ST_SEND: begin
        redo_q <= phase == TX_REDO;
        next_q <= phase == TX_WAIT && ack_recv_i;
        done_q <= done_w && (!zero_q || part_q);
      end
      default: {done_q, next_q, redo_q} <= 3'd0;
    endcase
  end

  always @(posedge clock) begin
    if (stage == ST_SEND && succ_q && last_w && smax_w) begin
      zero_q <= 1'b1;
    end else if (!selected_i || phase == TX_NONE && ack_recv_i) begin
      zero_q <= 1'b0;
    end

    if (stage == ST_SEND && (succ_q && last_w && smax_w || phase == TX_REDO && zero_q)) begin
      none_q <= 1'b1;
    end else if (!selected_i || sent_w) begin
      none_q <= 1'b0;
    end

    if (stage == ST_SEND && succ_q && last_w && !smax_w) begin
      part_q <= 1'b1;
    end else if (!selected_i || phase == TX_NONE && ack_recv_i) begin
      part_q <= 1'b0;
    end

    if (stage == ST_SEND && phase == TX_SEND && succ_w && last_w) begin
      last_q <= 1'b1;
    end else if (!selected_i || sent_q) begin
      last_q <= 1'b0;
    end
  end

  always @(posedge clock) begin
    if (stage == ST_SEND && ack_recv_i) begin
      case (phase)
        TX_WAIT: sent_q <= done_w && !zero_q;
        TX_NONE: sent_q <= 1'b1;
        default: sent_q <= 1'b0;
      endcase
    end else begin
      sent_q <= 1'b0;
    end
  end

  // -- USB Byte-Data Counter Controls -- //

  // Ticks for each (USB data-)byte send, and each (USB data-)frame sent.
  always @(posedge clock) begin
    if (selected_i) begin
      xfer_q <= xfer_w;  // Valid data sent
      succ_q <= succ_w;  // End-of-data-frame
    end else begin
      xfer_q <= 1'b0;
      succ_q <= 1'b0;
    end
  end

  // -- Counter Logic for USB Data-Frames  -- //

  // Generate a strobe at the start of a transaction to load the number of USB
  // frames into the 'down_counter'.
  always @(posedge clock) begin
    if (selected_i) begin
      {load_q, busy_q} <= {~busy_q, 1'b1};
    end else begin
      {load_q, busy_q} <= 2'b00;
    end
  end

  // -- Top-Level FSMs -- //

  // Top-level of a hierarchical FSM, and just transitions between the phases
  // of parsing a command, transferring data, then sending a response.
  always @(posedge clock) begin
    if (clear) begin
      stage <= ST_IDLE;
    end else if (selected_i) begin
      case (stage)
        ST_IDLE: stage <= mmio_send_i ? ST_SEND : (mmio_resp_i ? ST_RESP : stage);
        ST_SEND: stage <= mmio_resp_i ? ST_RESP : stage;
        ST_RESP: stage <= issued_w ? ST_IDLE : stage;
        ST_HALT: stage <= stage;
      endcase
    end else if (stage != ST_IDLE) begin
      stage <= ST_HALT;
    end
  end

  // FSM for sending each USB frame.
  always @(posedge clock) begin
    if (clear || !en_q || !ENABLED) begin
      phase <= TX_IDLE;
    end else if (selected_i) begin
      case (phase)
        TX_IDLE: phase <= mmio_resp_i || mmio_send_i ? TX_SEND : phase;
        TX_SEND: phase <= sent_w ? TX_WAIT : phase;
        TX_WAIT:
        if (ack_recv_i && stage == ST_SEND) begin
          phase <= done_q ? TX_IDLE : (zero_q ? TX_NONE : TX_SEND);
        end else if (issued_w) begin
          phase <= TX_IDLE;
        end else begin
          phase <= timedout_i ? TX_REDO : phase;
        end
        TX_NONE:
        if (ack_recv_i) begin
          phase <= TX_IDLE;
        end else if (timedout_i) begin
          phase <= TX_REDO;
        end
        TX_REDO: phase <= zero_q ? TX_NONE : TX_SEND;
      endcase
    end
  end

  // -- Cross-Domain Datapath Control Logic -- //

  always @(posedge dat_clk) begin
    {drdy_m, drdy_r} <= {drdy_r, stage == ST_SEND};
  end

  // -- USB Frame -length and -number Counters -- //

  // Count the bytes in the (USB) frame being sent.
  up_counter #(
      .WIDTH(CBITS),
      .CLAMP(0)
  ) UCOUNT1 (
      .clk(clock),
      .en (selected_i),

      .inc_i  (xfer_q),
      .clear_i(clear || wrap_w),
      .store_i(1'b0),
      .limit_o(smax_w),
      .oflow_o(wrap_w),
      .value_i(CZERO),
      .count_o()
  );

  // Count the number of (USB) frames sent.
  down_counter #(
      .WIDTH(COUNT_BITS),
      .CLAMP(0)
  ) DCOUNT1 (
      .clk(clock),
      .en (selected_i),

      .dec_i  (succ_q),
      .clear_i(1'b0),
      .store_i(load_q),
      .limit_o(last_w),
      .uflow_o(done_w),
      .value_i(cmd_len_i[15:CBITS]),
      .count_o()
  );

  // -- USB-Frame Bulk-IN Datapath -- //

  // Narrows the 32-bit AXI stream to an 8-bit stream (for USB).
  axis_adapter #(
      .S_DATA_WIDTH(PACKET_FIFO_WIDTH),
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
      .s_axis_tkeep(dat_tkeep_i),
      .s_axis_tlast(dat_tlast_i),
      .s_axis_tid(1'b0),
      .s_axis_tdest(1'b0),
      .s_axis_tuser(1'b0),
      .s_axis_tdata(dat_tdata_i),  // AXI input

      .m_axis_tvalid(a_tvalid_w),
      .m_axis_tready(a_tready_w),
      .m_axis_tkeep(a_tkeep_w),
      .m_axis_tlast(a_tlast_w),
      .m_axis_tid(),
      .m_axis_tdest(),
      .m_axis_tuser(),
      .m_axis_tdata(a_tdata_w)  // AXI output
  );

  // Cross domains for the fetched AXI data.
  assign u_tkeep_w = u_tvalid_w;

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

      .m_aclk  (clock),
      .m_tvalid(u_tvalid_w),
      .m_tready(u_tready_w),
      .m_tlast (u_tlast_w),
      .m_tdata (u_tdata_w)
  );

  // USB data can be from AXI, APB, ZDP, or "responses."
  axis_mux #(
      .S_COUNT(2),
      .DATA_WIDTH(8),
      .KEEP_ENABLE(0),
      .KEEP_WIDTH(1),
      .ID_ENABLE(0),
      .ID_WIDTH(1),
      .DEST_ENABLE(0),
      .DEST_WIDTH(1),
      .USER_ENABLE(0),
      .USER_WIDTH(1)
  ) U_MUX1 (
      .clk(clock),
      .rst(clear),

      .enable(selected_i),
      .select(stage != ST_RESP),

      .s_axis_tvalid({u_tvalid_w, res_tvalid_w}),
      .s_axis_tready({u_tready_w, res_tready_w}),
      .s_axis_tkeep ({u_tkeep_w, res_tkeep_w}),
      .s_axis_tlast ({u_tlast_w, res_tlast_w}),
      .s_axis_tuser (2'bx),
      .s_axis_tid   (2'bx),
      .s_axis_tdest (2'bx),
      .s_axis_tdata ({u_tdata_w, res_tdata_w}),

      .m_axis_tvalid(ulpi_tvalid_w),
      .m_axis_tready(ulpi_tready_w),
      .m_axis_tkeep (ulpi_tkeep_w),
      .m_axis_tlast (ulpi_tlast_w),
      .m_axis_tuser (),
      .m_axis_tid   (),
      .m_axis_tdest (),
      .m_axis_tdata (ulpi_tdata_w)
  );

  // -- Issue Transaction-Result Frames -- //

  cmd_result URESULT (
      .clock(clock),

      .selected_i(stage == ST_RESP),
      .ack_recv_i(ack_recv_i),
      .timedout_i(timedout_i),
      .result_i  (res_q),
      .issued_o  (issued_w),

      .cmd_tag_i(cmd_tag_i),
      .cmd_res_i(cmd_val_i),

      .usb_tvalid_o(res_tvalid_w),
      .usb_tready_i(res_tready_w),
      .usb_tkeep_o (res_tkeep_w),
      .usb_tlast_o (res_tlast_w),
      .usb_tdata_o (res_tdata_w)
  );

`ifdef __icarus
  //
  //  Simulation Only
  ///
  reg [39:0] dbg_stage, dbg_phase;

  initial begin : i_some_stats
    $display(" >> MAX_PACKET_LENGTH: %3d", MAX_PACKET_LENGTH);
    $display(" >> Up-counter width:   %2d", CBITS);
    $display(" >> Down-counter width: %2d", COUNT_BITS);
  end  // i_some_stats

  always @* begin
    case (phase)
      TX_IDLE: dbg_phase = "idle";
      TX_SEND: dbg_phase = "send";
      TX_WAIT: dbg_phase = "wait";
      TX_NONE: dbg_phase = "none";
      TX_REDO: dbg_phase = "redo";
      default: dbg_phase = " ?? ";
    endcase
    case (stage)
      ST_IDLE: dbg_stage = "IDLE";
      ST_SEND: dbg_stage = "SEND";
      ST_RESP: dbg_stage = "RESP";
      ST_HALT: dbg_stage = "HALT";
      default: dbg_stage = " ?? ";
    endcase
  end

`endif  /* __icarus */

endmodule  /* mmio_ep_in */
