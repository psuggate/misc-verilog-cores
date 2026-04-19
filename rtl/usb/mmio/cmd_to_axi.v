`timescale 1ns / 100ps
module cmd_to_axi #(
    parameter USB_DWORDS = 128,
    parameter FIFO_DEPTH = 512,
    localparam DATA_WIDTH = 32,
    localparam MSB = DATA_WIDTH - 1,
    localparam STROBES = DATA_WIDTH / 8,
    localparam SSB = STROBES - 1,
    localparam ADDRESS_WIDTH = 32,
    localparam AZERO = {ADDRESS_WIDTH{1'b0}},
    localparam ASB = ADDRESS_WIDTH - 1,
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
    input  usb_sent_i,

    // Pass-through data stream, from USB (Bulk-Out, via AXI-S)
    input dat_tvalid_i,
    output dat_tready_o,
    input dat_tkeep_i,
    input dat_tlast_i,
    input [7:0] dat_tdata_i,

    // Pass-through data stream, to USB (Bulk-In, via AXI-S)
    output dat_tvalid_o,
    input dat_tready_i,
    output dat_tkeep_o,
    output dat_tlast_o,
    output [7:0] dat_tdata_o,

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

  localparam [3:0] WR_IDLE = 1, WR_ADDR = 2, WR_DATA = 4, WR_RESP = 8;
  localparam [3:0] RD_IDLE = 1, RD_ADDR = 2, RD_DATA = 4, RD_SEND = 8;

  //
  //  Module-wide registers and signals.
  //

  // -- Command (USB) clock-domain signals and state -- //

  reg [15:0] res_q;
  wire [DBITS:0] cmd_wr_level_w, cmd_rd_level_w, com_rd_level_w;
  wire svalid_w, sready_w;
  wire tkeep_w, tlast_w, rvalid_w, rready_w, rokay_w;
  wire [ISB:0] rid_w;
  wire cvalid_w, cready_w;
  wire [CSB:0] cdata_w;

  // -- AXI clock-domain signals and state -- //

  reg [3:0] wr, rd;
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
  wire [DBITS:0] axi_rd_level_w;
  wire [  ASB:0] adr_w;
  wire [  SSB:0] x_tkeep;
  wire [ISB:0] x_tid, y_tid, tid_w;
  wire [MSB:0] x_tdata;

  assign usb_send_o = usb_send_q;

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
  reg cmd_vld_q, cmd_ack_q, axi_vld_q, usb_send_q;
  wire cmd_err_w, cmd_rdy_w, usb_send_w, usb_sent_w;

  wire usb_recv_w, axi_write_w;
  wire [ 7:0] axi_length_w;
  wire [ 3:0] axi_strobe_w;
  wire [31:0] axi_address_w;

  assign cmd_rdy_o = cmd_rdy_w;
  assign cmd_err_o = cmd_err_w;
  assign cmd_res_o = cmd_len_i;

  // Todo: make less combinational ...
  // assign usb_sent_w = dat_tvalid_o && dat_tlast_o && dat_tready_i;
  assign usb_sent_w = usb_sent_i;
  assign cdata_w = {axi_write_w, cmd_tag_i, axi_length_w[7:0], axi_address_w};

  // assign dat_tvalid_o = usb_send_w && sready_w;
  assign dat_tready_o = usb_recv_w && sready_w;
  assign rready_w = cmd_vld_q;

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
      axi_vld_q <= cvalid_w && cready_w;
    end
  end

  // Signal the USB controller to send a USB 'Bulk IN' frame.
  always @(posedge cmd_clk) begin
    if (cmd_rst) begin
      usb_send_q <= 1'b0;
    end else if (usb_send_w && !usb_send_q && dat_tvalid_o && !dat_tready_i && dat_tkeep_o) begin
      usb_send_q <= 1'b1;
    end else if (dat_tready_i) begin
      usb_send_q <= 1'b0;
    end
  end

  reg b_xfer_q;

  always @(posedge cmd_clk) begin
    if (cmd_rst) begin
      b_xfer_q <= 1'b0;
    end else if (usb_send_w && b_tvalid) begin
      b_xfer_q <= 1'b1;
    end else if (!b_tvalid) begin
      b_xfer_q <= 1'b0;
    end
  end

  cmd_to_axi_framer #(
      .USB_DWORDS(USB_DWORDS),
      .FIFO_DEPTH(FIFO_DEPTH)
  ) U_C2AF1 (
      .cmd_clk(cmd_clk),
      .cmd_rst(cmd_rst),

      .cmd_vld_i(cmd_vld_q),
      .cmd_dir_i(cmd_dir_i),
      .cmd_ack_i(cmd_ack_q),
      .cmd_rdy_o(cmd_rdy_w),
      .cmd_err_o(cmd_err_w),
      .cmd_len_i(cmd_len_i),
      .cmd_lun_i(cmd_lun_i),
      .cmd_adr_i(cmd_adr_i),

      .usb_recv_o(usb_recv_w),
      .usb_send_o(usb_send_w),
      .usb_sent_i(usb_sent_w),

      .fifo_rd_level_i(cmd_rd_level_w),
      .fifo_wr_level_i(cmd_wr_level_w),

      .axi_vld_o(cvalid_w),
      .axi_ack_i(axi_vld_q),
      .axi_fin_i(rvalid_w),
      .axi_dir_o(axi_write_w),
      .axi_len_o(axi_length_w),
      .axi_stb_o(axi_strobe_w),
      .axi_adr_o(axi_address_w)
  );

  //
  //  AXI clock-domain FSMs for read- & write- transactions.
  //

  // -- Memory-Domain Command & Address Synchronisation -- //

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
  // assign ack_w = !cmd_m && wr == WR_IDLE && rd == RD_IDLE && (rd_w ? fready_w : x_tvalid);

  assign wr_cmd_w = rd_w == 1'b0 && cmd_w && a_vld;
  // assign wr_cmd_w = rd_w == 1'b0 && cmd_w && ack_w;
  assign wr_ack_w = awvalid_o && awready_i;
  assign wr_end_w = x_tvalid && x_tready && x_tlast;

  assign rd_cmd_w = rd_w == 1'b1 && cmd_w && a_vld;
  // assign rd_cmd_w = rd_w == 1'b1 && cmd_w && ack_w;
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

  //
  //  Clock-domain crossing, for AXI transaction requests, to the AXI domain.
  //
  axis_afifo #(
      .WIDTH(CMD_FIFO_WIDTH),
      .TLAST(0),
      .ABITS(4)
  ) U_CFIFO1 (
      .aresetn(aresetn),

      .s_aclk  (cmd_clk),
      .s_tvalid(cvalid_w),
      .s_tready(cready_w),
      .s_tlast (1'b1),
      .s_tdata (cdata_w),

      .m_aclk  (aclk),
      .m_tvalid(cmd_w),
      .m_tready(ack_w),
      .m_tlast (),
      .m_tdata ({rd_w, tid_w, len_w, adr_w})
  );

  // -- Write Datapath -- //

  assign svalid_w = dat_tvalid_i && !cmd_dir_i;
  assign tkeep_w  = dat_tkeep_i;
  assign tlast_w  = dat_tlast_i;

  /**
   * Widens the 8-bit stream (from USB) to 32-bit for AXI.
   */
  axis_adapter #(
      .S_DATA_WIDTH(8),
      .S_KEEP_ENABLE(1),
      .S_KEEP_WIDTH(1),
      .M_DATA_WIDTH(DATA_WIDTH),
      .M_KEEP_ENABLE(1),
      .M_KEEP_WIDTH(STROBES),
      .ID_ENABLE(1),
      .ID_WIDTH(ID_WIDTH),
      .DEST_ENABLE(0),
      .DEST_WIDTH(1),
      .USER_ENABLE(0),
      .USER_WIDTH(1)
  ) U_ADAPT1 (
      .clk(cmd_clk),
      .rst(cmd_rst),

      .s_axis_tvalid(svalid_w),
      .s_axis_tready(sready_w),
      .s_axis_tkeep(tkeep_w),
      .s_axis_tlast(tlast_w),
      .s_axis_tid(cmd_tag_i),
      .s_axis_tdest(1'b0),
      .s_axis_tuser(1'b0),
      .s_axis_tdata(dat_tdata_i),  // AXI input

      .m_axis_tvalid(a_tvalid),
      .m_axis_tready(a_tready),
      .m_axis_tkeep(a_tkeep),
      .m_axis_tlast(a_tlast),
      .m_axis_tid(a_tid),
      .m_axis_tdest(),
      .m_axis_tuser(),
      .m_axis_tdata(a_tdata)  // AXI output
  );

  /**
   * Clock-domain crossing for the USB data, to the AXI clock-domain.
   *
   * Note(s):
   *  - Because the data-transfer rate for USB data is likely to be less than
   *    that of AXI, we need to store data for an entire AXI transaction.
   */
  axis_async_fifo #(
      .DEPTH(FIFO_DEPTH),
      .DATA_WIDTH(DATA_WIDTH),
      .KEEP_ENABLE(1),
      .KEEP_WIDTH(STROBES),
      .LAST_ENABLE(1),
      .ID_ENABLE(1),
      .ID_WIDTH(ID_WIDTH),
      .DEST_ENABLE(0),
      .DEST_WIDTH(1),
      .USER_ENABLE(0),
      .USER_WIDTH(1),
      .RAM_PIPELINE(1),
      .OUTPUT_FIFO_ENABLE(0),
      .FRAME_FIFO(WR_FRAME_FIFO),
      .USER_BAD_FRAME_VALUE(0),
      .USER_BAD_FRAME_MASK(0),
      .DROP_BAD_FRAME(0),
      .DROP_WHEN_FULL(0)
  ) U_WRFIFO1 (
      .s_clk(cmd_clk),
      .s_rst(cmd_rst),

      .s_axis_tvalid(a_tvalid),
      .s_axis_tready(a_tready),
      .s_axis_tkeep(a_tkeep),
      .s_axis_tlast(a_tlast),
      .s_axis_tdata(a_tdata),  // AXI input
      .s_axis_tid(a_tid),
      .s_axis_tdest(1'b0),
      .s_axis_tuser(1'b0),

      .m_clk(aclk),
      .m_rst(arst),

      .m_axis_tvalid(x_tvalid),
      .m_axis_tready(x_tready),
      .m_axis_tkeep(x_tkeep),
      .m_axis_tlast(x_tlast),
      .m_axis_tdata(x_tdata),  // AXI output
      .m_axis_tid(x_tid),
      .m_axis_tdest(),
      .m_axis_tuser(),

      .s_pause_req(1'b0),
      .s_pause_ack(),
      .m_pause_req(1'b0),
      .m_pause_ack(),

      .s_status_depth(cmd_wr_level_w),  // Status
      .s_status_depth_commit(),
      .s_status_overflow(),
      .s_status_bad_frame(),
      .s_status_good_frame(),
      .m_status_depth(),  // Status
      .m_status_depth_commit(),
      .m_status_overflow(),
      .m_status_bad_frame(),
      .m_status_good_frame()
  );

  /**
   * AXI write-responses need to cross back to the USB clock-domain.
   */
  axis_afifo #(
      .WIDTH(ID_WIDTH + 1),
      .TLAST(0),
      .ABITS(4)
  ) U_BFIFO1 (
      .aresetn (aresetn),
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

  // -- Read Datapath -- //

  axis_async_fifo #(
      .DEPTH(FIFO_DEPTH),
      .DATA_WIDTH(DATA_WIDTH),
      .KEEP_ENABLE(1),
      .KEEP_WIDTH(STROBES),
      .LAST_ENABLE(1),
      .ID_ENABLE(1),
      .ID_WIDTH(ID_WIDTH),
      .DEST_ENABLE(0),
      .DEST_WIDTH(1),
      .USER_ENABLE(1),
      .USER_WIDTH(2),
      .RAM_PIPELINE(1),
      .OUTPUT_FIFO_ENABLE(0),
      .FRAME_FIFO(RD_FRAME_FIFO),
      .USER_BAD_FRAME_VALUE(0),
      .USER_BAD_FRAME_MASK(0),
      .DROP_BAD_FRAME(0),
      .DROP_WHEN_FULL(0)
  ) U_RDFIFO1 (
      .s_clk(aclk),
      .s_rst(arst),

      .s_axis_tvalid(fvalid_w),  // AXI input: 32b, MEM domain
      .s_axis_tready(fready_w),
      .s_axis_tkeep({STROBES{rvalid_i}}),
      .s_axis_tlast(rlast_i),
      .s_axis_tid(rid_i),
      .s_axis_tdest(1'b0),
      .s_axis_tuser(rresp_i),
      .s_axis_tdata(rdata_i),

      .m_clk(cmd_clk),
      .m_rst(cmd_rst),

      .m_axis_tvalid(b_tvalid),  // AXI output: 8b, BUS domain
      .m_axis_tready(b_tready && b_xfer_q),
      .m_axis_tkeep(b_tkeep),
      .m_axis_tlast(b_tlast),
      .m_axis_tid(b_tid),
      .m_axis_tdest(),
      .m_axis_tuser(b_tuser),
      .m_axis_tdata(b_tdata),

      .s_pause_req(1'b0),
      .s_pause_ack(),
      .m_pause_req(1'b0),
      .m_pause_ack(),

      .s_status_depth(axi_rd_level_w),  // Status
      .s_status_depth_commit(),
      .s_status_overflow(),
      .s_status_bad_frame(),
      .s_status_good_frame(),
      .m_status_depth(cmd_rd_level_w),  // Status
      .m_status_depth_commit(com_rd_level_w),
      .m_status_overflow(),
      .m_status_bad_frame(),
      .m_status_good_frame()
  );

  axis_adapter #(
      .S_DATA_WIDTH(DATA_WIDTH),
      .S_KEEP_ENABLE(1),
      .S_KEEP_WIDTH(STROBES),
      .M_DATA_WIDTH(8),
      .M_KEEP_ENABLE(1),
      .M_KEEP_WIDTH(1),
      .ID_ENABLE(1),
      .ID_WIDTH(ID_WIDTH),
      .DEST_ENABLE(0),
      .DEST_WIDTH(1),
      .USER_ENABLE(1),
      .USER_WIDTH(2)
  ) U_ADAPT2 (
      .clk(cmd_clk),
      .rst(cmd_rst),

      .s_axis_tvalid(b_tvalid && b_xfer_q),  // AXI input: 32b
      .s_axis_tready(b_tready),
      .s_axis_tkeep({STROBES{b_tvalid}}),
      .s_axis_tlast(b_tlast),
      .s_axis_tdata(b_tdata),
      .s_axis_tid(b_tid),
      .s_axis_tdest(1'b0),
      .s_axis_tuser(b_tuser),

      .m_axis_tvalid(dat_tvalid_o),  // AXI output: 8b
      .m_axis_tready(dat_tready_i),
      .m_axis_tkeep(dat_tkeep_o),
      .m_axis_tlast(dat_tlast_o),
      .m_axis_tid(),
      .m_axis_tdest(),
      .m_axis_tuser(),
      .m_axis_tdata(dat_tdata_o)
  );


`ifdef __icarus
  //
  //  Simulation Only
  ///
  reg [39:0] dbg_rd, dbg_wr;

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
