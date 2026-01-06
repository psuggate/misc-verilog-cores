`timescale 1ns / 100ps
module cmd_to_axi (  // USB bus (command) clock-domain
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
    input cmd_rdy_i,
    input [15:0] cmd_val_i,

    // Pass-through data stream, to USB (Bulk-In, via AXI-S)
    output m_tvalid,
    input m_tready,
    output m_tkeep,
    output m_tlast,
    output [7:0] m_tdata,

    // Pass-through data stream, from USB (Bulk-Out, via AXI-S)
    input s_tvalid,
    output s_tready,
    input s_tkeep,
    input s_tlast,
    input [7:0] s_tdata,

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

  localparam ST_IDLE = 1;
  localparam ST_WADR = 2;
  localparam ST_WDAT = 4;
  localparam ST_RESP = 8;
  localparam ST_RADR = 16;
  localparam ST_RDAT = 32;
  localparam ST_SEND = 64;
  localparam ST_DONE = 128;

  localparam [3:0] WR_IDLE = 1;
  localparam [3:0] WR_ADDR = 2;
  localparam [3:0] WR_DATA = 4;
  localparam [3:0] WR_RESP = 8;

  localparam [3:0] RD_IDLE = 1;
  localparam [3:0] RD_ADDR = 2;
  localparam [3:0] RD_DATA = 4;
  localparam [3:0] RD_SEND = 8;

  // -- Datapath Signals -- //

  reg [3:0] wr, rd;
  reg [4:0] ptr_q;
  reg cmd_m, rd_m;
  reg wen_q, stb_q, cyc_q;
  reg mux_q, sel_q, vld_q, lst_q, idx_q;
  reg [  7:0] res_q;
  reg [ISB:0] rid_q;
  reg [7:0] cmd_q, len_q, len_m;
  reg [ISB:0] tid_m;
  reg [ASB:0] adr_m;
  reg [ISB:0] tid_q;  // 4b
  reg [ASB:0] adr_q;  // 28b
  wire mux_enable_w, mux_select_w;
  wire svalid_w, sready_w, fready_w, fvalid_w, rd_mid_w;
  wire [DBITS:0] rd_level_w;
  wire tkeep_w, tlast_w, rvalid_w, cmd_end_w;
  wire bokay_w, wfull_w, rokay_w;
  wire cmd_w, ack_w, rd_w;
  wire wr_cmd_w, wr_ack_w, wr_end_w, rd_cmd_w, rd_ack_w, rd_end_w;
  wire [ISB:0] tid_w, rid_w;
  wire [  7:0] len_w;
  wire [ASB:0] adr_w;
  wire [CSB:0] cdata_w;

  wire x_tvalid, x_tready, x_tlast, y_tvalid, y_tready, y_tkeep, y_tlast;
  wire a_tvalid, a_tready, a_tlast, b_tvalid, b_tready, b_tlast;
  wire z_tvalid, z_tready, z_tkeep, z_tlast, cvalid_w, cready_w;
  wire [SSB:0] a_tkeep, x_tkeep, b_tkeep;
  wire [1:0] b_tuser, y_tuser;
  wire [ISB:0] x_tid, y_tid, a_tid, b_tid;
  wire [7:0] y_tdata, z_tdata;
  wire [MSB:0] x_tdata, b_tdata, a_tdata;

  reg [4:0] state;

  assign s_tready = sready_w && cready_w && cyc_q;

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


  // -- Memory-Domain Command & Address Synchronisation -- //

  assign cvalid_w = stb_q;
  assign cdata_w = {cmd_q[7], tid_q, len_q, adr_q};

  // Note: According to the AXI spec., not supposed to have combinational logic
  //   between 'valid' and 'ready' ports, which is why these signals are laid-
  //   out this way.
  assign ack_w = !cmd_m && wr == WR_IDLE && rd == RD_IDLE && (rd_w ? fready_w : x_tvalid);

  assign wr_cmd_w = rd_w == 1'b0 && cmd_w && ack_w;
  assign wr_ack_w = awvalid_o && awready_i;
  assign wr_end_w = x_tvalid && x_tready && x_tlast;

  assign rd_cmd_w = rd_w == 1'b1 && cmd_w && ack_w;
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


  //
  //  Clock-domain crossing, to the AXI domain.
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
        WR_RESP: begin
          if (bvalid_i && bready_o) begin
            wr <= WR_IDLE;
          end
        end
        default: wr <= 'bx;
      endcase
    end
  end

  // -- Read-Port, AXI-Domain FSM -- //

  assign fvalid_w = rd == RD_DATA && rvalid_i;
  assign rd_mid_w = rd_level_w[DSB];

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

  // -- Multiplexor to the SPI or USB Encoder -- //

  assign z_tvalid = vld_q;
  assign z_tkeep  = vld_q;
  assign z_tlast  = lst_q;
  assign z_tdata  = idx_q ? rid_q : res_q;

  always @(posedge cmd_clk) begin
    if (cmd_rst) begin
      {mux_q, sel_q, idx_q, vld_q, lst_q} <= 5'h00;
      res_q <= 8'bx;
      rid_q <= 8'bx;
    end else begin
      case (state)
        ST_IDLE: begin
          {mux_q, sel_q, idx_q, vld_q, lst_q} <= 5'h00;
        end

        ST_RESP: begin
          if (rvalid_w) begin
            {mux_q, sel_q, idx_q, vld_q, lst_q} <= 5'h1a;
            res_q <= rokay_w ? CMD_WDONE : CMD_WFAIL;
            rid_q <= {{(8 - ID_WIDTH) {1'b0}}, rid_w};
          end
        end

        ST_DONE: begin
          if (z_tready && vld_q && !idx_q) begin
            // Send the 2nd byte of the write-response
            {mux_q, sel_q, idx_q, vld_q, lst_q} <= 5'h1f;
          end else if (z_tready) begin
            {mux_q, sel_q, idx_q, vld_q, lst_q} <= 5'h00;
          end
        end

        ST_RDAT: begin
          if (!idx_q && !vld_q && y_tvalid && y_tready) begin
            {mux_q, sel_q, idx_q, vld_q, lst_q} <= 5'h1a;
            res_q <= b_tuser == RESP_OKAY ? CMD_RDATA : CMD_RFAIL;
            rid_q <= {{(8 - ID_WIDTH) {1'b0}}, y_tid};
          end else if (!idx_q && vld_q) begin
            {mux_q, sel_q, idx_q, vld_q, lst_q} <= 5'h1e;
          end else if (idx_q && vld_q) begin
            {mux_q, sel_q, idx_q, vld_q, lst_q} <= 5'h14;
          end else begin
            // Todo: this is the same as the previous case !?
            {mux_q, sel_q, idx_q, vld_q, lst_q} <= 5'h14;
          end
        end

        ST_SEND: begin
          {sel_q, idx_q, vld_q, lst_q} <= 4'h4;
          if (m_tvalid && m_tready && m_tlast) begin
            mux_q <= 1'b0;
          end else begin
            mux_q <= 1'b1;
          end
        end

        default: begin
          {mux_q, sel_q, idx_q, vld_q, lst_q} <= {mux_q, sel_q, idx_q, vld_q, lst_q};
        end

      endcase
    end
  end

  // -- Write Datapath -- //

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
      .s_axis_tid(tid_q),
      .s_axis_tdest(1'b0),
      .s_axis_tuser(1'b0),
      .s_axis_tdata(s_tdata),  // AXI input

      .m_axis_tvalid(a_tvalid),
      .m_axis_tready(a_tready),
      .m_axis_tkeep(a_tkeep),
      .m_axis_tlast(a_tlast),
      .m_axis_tid(a_tid),
      .m_axis_tdest(),
      .m_axis_tuser(),
      .m_axis_tdata(a_tdata)  // AXI output
  );

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
      .m_rst(aresetn),

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

      .s_status_depth(),  // Status
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

  // Write-responses FIFO
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
      .m_tready(state == ST_RESP),
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
      .s_rst(aresetn),

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
      .m_axis_tready(b_tready),
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

      .s_status_depth(rd_level_w),  // Status
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

      .s_axis_tvalid(b_tvalid),  // AXI input: 32b
      .s_axis_tready(b_tready),
      .s_axis_tkeep({STROBES{b_tvalid}}),
      .s_axis_tlast(b_tlast),
      .s_axis_tdata(b_tdata),
      .s_axis_tid(b_tid),
      .s_axis_tdest(1'b0),
      .s_axis_tuser(b_tuser),

      .m_axis_tvalid(y_tvalid),  // AXI output: 8b
      .m_axis_tready(y_tready),
      .m_axis_tkeep(y_tkeep),
      .m_axis_tlast(y_tlast),
      .m_axis_tid(y_tid),
      .m_axis_tdest(),
      .m_axis_tuser(y_tuser),
      .m_axis_tdata(y_tdata)
  );

  // Multiplexor to the SPI or USB Encoder
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

      .enable(mux_q),
      .select(sel_q),

      .s_axis_tvalid({z_tvalid, y_tvalid}), // AXI input: 2x 8b
      .s_axis_tready({z_tready, y_tready}),
      .s_axis_tkeep ({z_tkeep, y_tkeep}),
      .s_axis_tlast ({z_tlast, y_tlast}),
      .s_axis_tuser (2'bx),
      .s_axis_tid   (2'bx),
      .s_axis_tdest (2'bx),
      .s_axis_tdata ({z_tdata, y_tdata}),

      .m_axis_tvalid(m_tvalid), // AXI output: 8b
      .m_axis_tready(m_tready),
      .m_axis_tkeep (m_tkeep),
      .m_axis_tlast (m_tlast),
      .m_axis_tuser (),
      .m_axis_tid   (),
      .m_axis_tdest (),
      .m_axis_tdata (m_tdata)
  );


endmodule  /* cmd_to_axi */
