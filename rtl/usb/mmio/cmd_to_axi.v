`timescale 1ns / 100ps
module cmd_to_axi #(
    parameter FIFO_DEPTH = 512,
    parameter DATA_WIDTH = 32,
    localparam MSB = DATA_WIDTH - 1,
    localparam STROBES = DATA_WIDTH / 8,
    localparam SSB = STROBES - 1,
    localparam ADDRESS_WIDTH = 32,
    localparam AZERO = {ADDRESS_WIDTH{1'b0}},
    localparam ASB = ADDRESS_WIDTH - 1,
    parameter USB_DWORDS = 128,
    localparam USB_WIDTH = DATA_WIDTH,
    localparam ID_WIDTH = 4,
    localparam ISB = ID_WIDTH - 1,
    parameter WR_FRAME_FIFO = 1,  // Avoid "starvation," if slow upstream source
    localparam RD_FRAME_FIFO = 1  // Todo: Not useful ??
) (  // USB bus (command) clock-domain
    input cmd_clk,
    input cmd_rst,

    // Decoded command (APB, or AXI)
    input cmd_vld_i,
    input cmd_ack_i,
    input cmd_dir_i,
    input [1:0] cmd_cmd_i,
    input [3:0] cmd_tag_i,
    input [15:0] cmd_len_i,
    input [3:0] cmd_lun_i,
    input [27:0] cmd_adr_i,
    output cmd_rdy_o,
    output cmd_err_o,
    output [15:0] cmd_res_o,

    output usb_send_o,
    input  usb_save_i,
    input  usb_drop_i,
    input  usb_next_i,
    input  usb_redo_i,
    input  usb_sent_i,

    // Pass-through data stream, from USB (Bulk-Out, via AXI-S)
    input dat_tvalid_i,
    output dat_tready_o,
    input [SSB:0] dat_tkeep_i,
    input dat_tlast_i,
    input [MSB:0] dat_tdata_i,

    // Pass-through data stream, to USB (Bulk-In, via AXI-S)
    output dat_tvalid_o,
    input dat_tready_i,
    output [SSB:0] dat_tkeep_o,
    output dat_tlast_o,
    output [MSB:0] dat_tdata_o,

    // AXI clock-domain
    input aclk,
    input aresetn,

    // AXI4 Interface
    output awvalid_o,
    input awready_i,
    output [ASB:0] awaddr_o,
    output [ISB:0] awid_o,
    output [7:0] awlen_o,
    output [1:0] awburst_o,

    output wvalid_o,
    input wready_i,
    output wlast_o,
    output [SSB:0] wstrb_o,
    output [MSB:0] wdata_o,

    input bvalid_i,
    output bready_o,
    input [1:0] bresp_i,
    input [ISB:0] bid_i,

    output arvalid_o,
    input arready_i,
    output [ASB:0] araddr_o,
    output [ISB:0] arid_o,
    output [7:0] arlen_o,
    output [1:0] arburst_o,

    input rvalid_i,
    output rready_o,
    input rlast_i,
    input [1:0] rresp_i,
    input [ISB:0] rid_i,
    input [MSB:0] rdata_i
);

  // -- Constants -- //

  `include "axi_defs.vh"

  localparam CMD_FIFO_WIDTH = ID_WIDTH + ADDRESS_WIDTH + 8 + 1;
  localparam CSB = CMD_FIFO_WIDTH - 1;

  localparam DBITS = $clog2(FIFO_DEPTH);
  localparam DSB = DBITS - 1;

  localparam USB_LEN_BITS = $clog2(USB_DWORDS) + 2;
  localparam AXI_ADR_BITS = 12 - USB_LEN_BITS;
  localparam AXI_LEN_BITS = 16 - USB_LEN_BITS;

  localparam [6:0] ST_IDLE = 1, ST_RECV = 2, ST_WRIT = 4, ST_READ = 8;
  localparam [6:0] ST_SEND = 16, ST_DONE = 32, ST_FAIL = 64;
  reg [6:0] state;

  localparam [3:0] WR_IDLE = 1, WR_ADDR = 2, WR_DATA = 4, WR_RESP = 8;
  localparam [3:0] RD_IDLE = 1, RD_ADDR = 2, RD_DATA = 4, RD_SEND = 8;
  reg [3:0] wr, rd;

  //
  //  Module-wide registers and signals.
  //

  // -- Command (USB) clock-domain signals and state -- //

  reg cmd_rdy_q, cmd_vld_q, cmd_err_q, cmd_ack_q, axi_vld_q, usb_send_q;
  reg cvalid_q;
  reg [15:0] res_q;
  wire svalid_w, sready_w, cready_w;
  wire tkeep_w, tlast_w, rvalid_w, rready_w, rokay_w;
  wire [ISB:0] rid_w;
  wire [CSB:0] cdata_w;

  assign cmd_rdy_o = cmd_rdy_q;
  assign cmd_err_o = cmd_err_q;
  assign cmd_res_o = cmd_len_i;

  assign usb_send_o = usb_send_q;

  assign dat_tready_o = state == ST_RECV && sready_w;
  assign dat_tkeep_o = {STROBES{dat_tvalid_o}};

  // -- AXI clock-domain signals and state -- //

  reg cmd_m, rd_m;
  reg [  7:0] len_m;
  reg [ISB:0] tid_m;
  reg [ASB:0] adr_m;
  wire fready_w, fvalid_w, rd_mid_w, bokay_w;
  wire cmd_w, ack_w, rd_w;
  wire wr_cmd_w, wr_ack_w, wr_end_w, rd_cmd_w, rd_ack_w, rd_end_w;
  wire [ISB:0] a_tid, b_tid;
  wire a_tvalid, a_tready, a_tlast, b_tvalid, b_tready, b_tlast;
  wire [SSB:0] a_tkeep, b_tkeep;
  wire [1:0] b_tuser;
  wire [MSB:0] b_tdata, a_tdata;
  wire x_tvalid, x_tready, x_tlast;
  wire [DSB:0] axi_rd_level_w, axi_wr_level_w;
  wire [ASB:0] adr_w;
  wire [ISB:0] x_tid, y_tid, tid_w;
  wire [MSB:0] x_tdata;

  // Todo ...
  assign awvalid_o = cmd_m && !rd_m;
  assign awburst_o = BURST_TYPE_INCR;
  assign awlen_o   = len_m;
  assign awid_o    = tid_m;
  assign awaddr_o  = adr_m;

  // Write-buffer (FIFO) assignments, to the DDR3 controller
  assign wvalid_o = wr == WR_DATA && x_tvalid;
  assign wlast_o  = wr == WR_DATA && x_tlast;
  assign wstrb_o  = {STROBES{x_tvalid}};
  assign wdata_o  = x_tdata;

  // Read-address assignments, to the DDR3 controller
  assign arvalid_o = cmd_m && rd_m;
  assign arburst_o = BURST_TYPE_INCR;
  assign arlen_o   = len_m;
  assign arid_o    = tid_m;
  assign araddr_o  = adr_m;

  assign rready_o = rd == RD_DATA && fready_w;

  //
  //  Module-wide control signals.
  //
  reg arst, rst0, rst1;

  always @(posedge aclk or negedge aresetn)
    if (!aresetn) begin
      rst0 <= 1'b1;
      rst1 <= 1'b1;
    end else begin
      rst0 <= 1'b0;
      rst1 <= rst0;
    end

  always @(posedge aclk) begin
    arst <= rst1;
  end

  /**
   * Generates AXI(4) requests in response to commands from the USB interface.
   * The `axi_*` outputs are to be fed into async. FIFOs, and data is handled
   * external to this module.
   */
  reg [ 9:0] beat_num_q;
  reg [ 7:0] axi_len_q;
  reg [31:0] axi_adr_q;

  wire cmd_err_w, beat_err_w;
  wire [10:0] beat_nxt_w;
  wire [ 7:0] len_nxt_w;
  wire [31:0] axi_adr_w, nxt_adr_w;
  wire [AXI_LEN_BITS-1:0] cnt_left_w;

  assign axi_adr_w = {cmd_lun_i, cmd_adr_i};
  assign cdata_w   = {cmd_dir_i, cmd_tag_i, axi_len_q, axi_adr_w};
  assign svalid_w  = dat_tvalid_i && !cmd_dir_i;
  assign rready_w  = cmd_vld_q;

  always @(posedge cmd_clk) begin
    if (cmd_rst) begin
      cmd_vld_q <= 1'b0;
    end else if (cready_w && cmd_vld_i && !cmd_err_w) begin
      cmd_vld_q <= 1'b1;
    end else if (!cmd_vld_i) begin
      cmd_vld_q <= 1'b0;
    end

    cmd_ack_q <= cmd_ack_i && !cmd_rst;

    if (cmd_rst) begin
      axi_vld_q <= 1'b0;
    end else if (cmd_vld_q) begin
      axi_vld_q <= cvalid_q && cready_w;
    end
  end

  // Signal the USB controller to send a USB 'Bulk IN' frame.
  always @(posedge cmd_clk) begin
    case (state)
      ST_READ: usb_send_q <= rd_rdy_q;
      ST_SEND:
      if (dat_tvalid_o && dat_tready_i) begin
        usb_send_q <= 1'b0;
      end
      default: usb_send_q <= 1'b0;
    endcase
  end

  // -- AXI Transaction Control Signals -- //

  reg read_q, read_p, read_r;
  reg wr_rdy_q, rd_rdy_q;
  reg cnt_load_q, cnt_next_q;
  wire cnt_done_w;

  // Todo: can this assert too early (before packet FIFO is ready)?
  wire read_a = read_p & ~read_q;

  always @(posedge cmd_clk) begin
    cnt_next_q <= cvalid_q && cready_w;
    cnt_load_q <= state == ST_IDLE && cmd_vld_i;
  end

  always @(posedge cmd_clk) begin
    case (state)
      ST_RECV: wr_rdy_q <= usb_save_i ? 1'b1 : wr_rdy_q;
      ST_WRIT: wr_rdy_q <= axi_vld_q ? 1'b0 : wr_rdy_q;
      ST_READ: rd_rdy_q <= read_a ? 1'b1 : rd_rdy_q;
      ST_SEND: rd_rdy_q <= axi_vld_q ? 1'b0 : rd_rdy_q;
      default: {wr_rdy_q, rd_rdy_q} <= 2'h0;
    endcase
  end

  always @(posedge cmd_clk) begin
    case (state)
      ST_WRIT: cmd_rdy_q <= cnt_done_w && rvalid_w;
      ST_SEND: cmd_rdy_q <= cnt_done_w && usb_sent_i;
      default: cmd_rdy_q <= 1'b0;
    endcase
  end

  // -- Data Transfer Counting and Address Calculation -- //

  // Compute the total number of AXI transaction beats.
  assign beat_err_w = cmd_len_i[15:12] != 4'd0;
  assign beat_nxt_w = beat_num_q - USB_DWORDS;
  assign len_nxt_w  = cnt_left_w > 0 ? USB_DWORDS - 1 : beat_num_q[7:0];

  always @(posedge cmd_clk) begin
    if (cmd_rst) begin
      beat_num_q <= 'bx;
      axi_len_q  <= 'bx;
      axi_adr_q  <= 'bx;
    end else begin
      case (state)
        ST_IDLE: begin
          beat_num_q <= cmd_len_i[11:2];
          axi_len_q  <= cmd_len_i[11:2] >= USB_DWORDS ? USB_DWORDS - 1 : cmd_len_i[9:2];
          axi_adr_q  <= cmd_adr_i;
        end
        default: begin
          beat_num_q <= cnt_next_q ? beat_nxt_w[9:0] : beat_num_q;
          axi_len_q  <= cnt_next_q ? len_nxt_w : axi_len_q;
          axi_adr_q  <= cnt_next_q ? nxt_adr_w : axi_adr_q;
        end
      endcase
    end
  end

  always @(posedge cmd_clk) begin
    case (state)
      ST_IDLE: cvalid_q <= cmd_vld_i && cmd_dir_i && !cmd_err_w;
      ST_RECV: cvalid_q <= wr_rdy_q;
      ST_SEND: cvalid_q <= usb_next_i && !cnt_done_w;
      default: cvalid_q <= 1'b0;
    endcase
  end

  // Todo: throw errors when crossing 4kB page-boundaries, also.
  wire cmd_err_adr_w = cmd_adr_i[1:0] != 2'b00;
  wire cmd_err_len_w = cmd_len_i[1:0] != 2'b11;

  assign cmd_err_w = cmd_err_adr_w || cmd_err_len_w || beat_err_w;

  always @(posedge cmd_clk) begin
    if (cmd_rst) begin
      cmd_err_q <= 1'b0;
    end else if (cmd_vld_i && cmd_err_w) begin
      cmd_err_q <= cmd_err_w;
      if (cmd_err_adr_w) $error("%11t: Invalid command, address alignment", $time);
      if (cmd_err_len_w) $error("%11t: Invalid command, length error", $time);
    end
  end

  // -- Main AXI-Framing State Machine -- //

  always @(posedge cmd_clk) begin
    if (cmd_rst) begin
      state <= ST_IDLE;
    end else if (cmd_err_q) begin
      state <= ST_FAIL;
    end else begin
      case (state)
        ST_IDLE:
        if (!cmd_vld_i) begin
          state <= state;
        end else begin
          $display("%11t: Command received: RD = %d, ADR = 0x%x", $time, cmd_dir_i, cmd_adr_i);
          state <= cmd_dir_i ? ST_READ : ST_RECV;
        end

        ST_RECV: state <= wr_rdy_q ? ST_WRIT : state;
        ST_WRIT:
        if (rvalid_w) begin
          state <= cnt_done_w ? ST_DONE : ST_RECV;
        end

        ST_READ: state <= rd_rdy_q ? ST_SEND : state;
        ST_SEND:
        if (usb_next_i && !cnt_done_w) begin
          state <= ST_READ;
        end else if (usb_sent_i) begin
          state <= ST_DONE;
        end

        // Wait for parent module to issue success/error response.
        ST_DONE: state <= cmd_ack_i ? ST_IDLE : state;
        ST_FAIL: state <= cmd_ack_i ? ST_IDLE : state;

        default: begin
          state <= ST_IDLE;
          #10 if (state != ST_IDLE) $fatal;
        end
      endcase
    end
  end

  // Increment the AXI address, for each USB frame sent/received.
  assign nxt_adr_w[31:12] = axi_adr_w[31:12];
  assign nxt_adr_w[USB_LEN_BITS-1:0] = axi_adr_w[USB_LEN_BITS-1:0];

  up_counter #(
      .WIDTH(AXI_ADR_BITS),
      .CLAMP(0)
  ) UCOUNT1 (
      .clk(cmd_clk),
      .en (state != ST_IDLE),

      .inc_i  (cnt_next_q),
      .clear_i(1'b0),
      .store_i(cnt_load_q),
      .limit_o(),
      .oflow_o(),
      .value_i(cmd_adr_i[11:USB_LEN_BITS]),
      .count_o(nxt_adr_w[11:USB_LEN_BITS])
  );

  // Count the number of AXI beats.
  down_counter #(
      .WIDTH(AXI_LEN_BITS),
      .CLAMP(0)
  ) DCOUNT1 (
      .clk(cmd_clk),
      .en (state != ST_IDLE),

      .dec_i  (cnt_next_q),
      .clear_i(1'b0),
      .store_i(cnt_load_q),
      .limit_o(),
      .uflow_o(cnt_done_w),
      .value_i(cmd_len_i[15:USB_LEN_BITS]),
      .count_o(cnt_left_w)
  );

  //
  //  AXI clock-domain FSMs for read- & write- transactions.
  //

  // -- Memory-Domain Command & Address Synchronisation -- //

  reg rd_end_m;
  reg a_vld, a_ack;
  wire [7:0] len_w;

  // Todo: async-reset not required?
  always @(posedge aclk or negedge aresetn) begin
    if (!aresetn || wr_ack_w || rd_ack_w) begin
      a_vld <= 1'b0;
      a_ack <= 1'b0;
    end else if (cmd_w && !a_vld && rd == RD_IDLE && wr == WR_IDLE) begin
      if (rd_w && fready_w) begin
        a_vld <= 1'b1;
        a_ack <= 1'b0;
      end else if (!rd_w && x_tvalid) begin
        a_vld <= 1'b1;
        a_ack <= 1'b0;
      end
    end else if (a_vld && !a_ack && (rd != RD_IDLE || wr != WR_IDLE)) begin
      a_vld <= 1'b0;
      a_ack <= 1'b1;
    end else begin
      a_vld <= a_vld;
      a_ack <= 1'b0;
    end
  end

  // Note: According to the AXI spec., not supposed to have combinational logic
  //   between 'valid' and 'ready' ports, which is why these signals are laid-
  //   out this way.
  assign ack_w = a_ack;

  assign wr_cmd_w = rd_w == 1'b0 && cmd_w && a_vld;
  assign wr_ack_w = awvalid_o && awready_i;
  assign wr_end_w = x_tvalid && x_tready && x_tlast;

  assign rd_cmd_w = rd_w == 1'b1 && cmd_w && a_vld;
  assign rd_ack_w = arvalid_o && arready_i;
  assign rd_end_w = fvalid_w && fready_w && rlast_i;

  always @(posedge aclk or negedge aresetn) begin
    if (!aresetn || wr_ack_w || rd_ack_w) begin
      cmd_m <= 1'b0;
      {rd_m, tid_m, len_m, adr_m} <= {CMD_FIFO_WIDTH{1'bx}};
    end else if (cmd_w && ack_w) begin
      cmd_m <= 1'b1;
      rd_m  <= rd_w;
      tid_m <= tid_w;
      len_m <= len_w;
      adr_m <= adr_w;
    end
  end

  // Latch the FETCH response.
  always @(posedge aclk) begin
    rd_end_m <= rd_end_w && rresp_i == RESP_OKAY;
  end

  // Signal that the AXI FETCH result across to the USB domain.
  always @(posedge cmd_clk or posedge rd_end_m) begin
    if (rd_end_m) begin
      read_r <= 1'b1;
    end else if (cmd_rst || read_p) begin
      read_r <= 1'b0;
    end
  end

  // Latch the read-response.
  always @(posedge cmd_clk) begin
    {read_q, read_p} <= {read_p, read_r};
  end

  // -- Write-Port, AXI-Domain FSM -- //

  assign x_tready = wr == WR_DATA ? wready_i : 1'b0;
  assign bokay_w  = bresp_i == RESP_OKAY;

  always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      wr <= WR_IDLE;
    end else begin
      case (wr)
        WR_IDLE: wr <= wr_cmd_w ? WR_ADDR : wr;
        WR_ADDR: wr <= wr_ack_w ? WR_DATA : wr;
        WR_DATA: wr <= wr_end_w ? WR_RESP : wr;
        WR_RESP:
        if (bvalid_i && bready_o) begin
          wr <= WR_IDLE;
        end
        default: wr <= 'bx;
      endcase
    end
  end

  // -- Read-Port, AXI-Domain FSM -- //

  assign fvalid_w = rd == RD_DATA && rvalid_i;
  assign rd_mid_w = axi_rd_level_w[DSB];

  always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      rd <= RD_IDLE;
    end else begin
      case (rd)
        RD_IDLE: rd <= rd_cmd_w ? RD_ADDR : rd;
        RD_ADDR: rd <= rd_ack_w ? RD_DATA : rd;
        RD_DATA: rd <= rd_end_w ? RD_SEND : rd;
        RD_SEND: rd <= rd_mid_w ? rd : RD_IDLE;
        default: rd <= 'bx;
      endcase
    end
  end

  //  AXI transaction request clock-domain crossing.
  axis_afifo #(
      .WIDTH(CMD_FIFO_WIDTH),
      .TLAST(0),
      .ABITS(4)
  ) U_CFIFO1 (
      .aresetn(aresetn),

      .s_aclk  (cmd_clk),
      .s_tvalid(cvalid_q),
      .s_tready(cready_w),
      .s_tlast (1'b1),
      .s_tdata (cdata_w),

      .m_aclk  (aclk),
      .m_tvalid(cmd_w),
      .m_tready(ack_w),
      .m_tlast (),
      .m_tdata ({rd_w, tid_w, len_w, adr_w})
  );

  // AXI write-responses need to cross back to the USB clock-domain.
  axis_afifo #(
      .WIDTH(ID_WIDTH + 1),
      .TLAST(0),
      .ABITS(4)
  ) U_BFIFO1 (
      .aresetn(aresetn),

      .s_aclk  (aclk),
      .s_tvalid(bvalid_i),
      .s_tready(bready_o),
      .s_tlast (1'b1),
      .s_tdata ({bokay_w, bid_i}),

      .m_aclk  (cmd_clk),
      .m_tvalid(rvalid_w),
      .m_tready(rready_w),
      .m_tlast (),
      .m_tdata ({rokay_w, rid_w})
  );

  reg drop_p, drop_q, save_p, save_q;
  reg redo_p, next_p, redo_q, next_q;

  wire drop_a = ~drop_q & drop_p;
  wire save_a = ~save_q & save_p;
  wire redo_a = ~redo_q & redo_p;
  wire next_a = ~next_q & next_p;

  // FIXME: these should be one-shots!!
  always @(posedge aclk) begin
    {save_q, save_p} <= {save_p, usb_save_i};
    {drop_q, drop_p} <= {drop_p, usb_drop_i};
    {next_q, next_p} <= {next_p, usb_next_i};
    {redo_q, redo_p} <= {redo_p, usb_redo_i};
  end

  // Output packet FIFO, for (STORE) data passed-through from the USB Bulk-Out
  // pipe, and with drop-packet-on-failure.
  packet_fifo #(
      .WIDTH(DATA_WIDTH),
      .DEPTH(FIFO_DEPTH),
      .STORE_LASTS(1),
      .SAVE_ON_LAST(0),  // save only after CRC16 checking
      .LAST_ON_SAVE(1),  // delayed 'tlast', after CRC16-valid
      .NEXT_ON_LAST(1),
      .USE_LENGTH(0),
      .MAX_LENGTH(USB_DWORDS),
      .OUTREG(2)
  ) WRFIFO (
      .clock(aclk),
      .reset(arst),

      .level_o(),

      .drop_i(drop_a),  // Todo: cross from USB domain
      .save_i(save_a),  // Todo: cross from USB domain
      .redo_i(1'b0),
      .next_i(1'b0),

      .s_tvalid(svalid_w),
      .s_tready(sready_w),
      .s_tkeep (1'b1),
      .s_tlast (dat_tlast_i),
      .s_tdata (dat_tdata_i),

      .m_tvalid(x_tvalid),
      .m_tready(x_tready),
      .m_tlast (x_tlast),
      .m_tdata (x_tdata)
  );

  // Output packet FIFO, for command responses, or (AXI FETCH) data passed-
  // through to the USB host (via Bulk-In pipe), and with with Repeat-Last
  // Packet, on timeout (while waiting for ACK).
  packet_fifo #(
      .WIDTH(DATA_WIDTH),
      .DEPTH(FIFO_DEPTH),
      .STORE_LASTS(1),
      .SAVE_ON_LAST(1),
      .LAST_ON_SAVE(1),
      .NEXT_ON_LAST(0),
      .USE_LENGTH(1),
      .MAX_LENGTH(USB_DWORDS),
      .OUTREG(2)
  ) RDFIFO (
      .clock(aclk),
      .reset(arst),

      .level_o(axi_rd_level_w),  // Todo: not required?

      .drop_i(1'b0),    // Todo: correct?
      .save_i(1'b0),    // Todo: not required?
      .redo_i(redo_a),
      .next_i(next_a),

      .s_tvalid(fvalid_w),
      .s_tready(fready_w),
      .s_tlast (rlast_i),
      .s_tkeep (rvalid_i),
      .s_tdata (rdata_i),

      .m_tvalid(dat_tvalid_o),
      .m_tready(dat_tready_i),
      .m_tlast (dat_tlast_o),
      .m_tdata (dat_tdata_o)
  );

`ifdef __icarus
  //
  //  Simulation Only
  ///
  reg [39:0] dbg_rd, dbg_wr;
  reg [39:0] dbg_state;

  always @* begin
    case (state)
      ST_IDLE: dbg_state = "IDLE";
      ST_RECV: dbg_state = "RECV";
      ST_WRIT: dbg_state = "WRIT";
      ST_READ: dbg_state = "READ";
      ST_SEND: dbg_state = "SEND";
      ST_DONE: dbg_state = "DONE";
      ST_FAIL: dbg_state = "FAIL";
      default: dbg_state = " ?? ";
    endcase
  end

  always @* begin
    case (wr)
      WR_IDLE: dbg_wr = "IDLE";
      WR_ADDR: dbg_wr = "ADDR";
      WR_DATA: dbg_wr = "DATA";
      WR_RESP: dbg_wr = "RESP";
      default: dbg_wr = " ?? ";
    endcase
  end

  always @* begin
    case (rd)
      RD_IDLE: dbg_rd = "IDLE";
      RD_ADDR: dbg_rd = "ADDR";
      RD_DATA: dbg_rd = "DATA";
      RD_SEND: dbg_rd = "SEND";
      default: dbg_rd = " ?? ";
    endcase
  end

`endif  /* __icarus */

endmodule  /* cmd_to_axi */
