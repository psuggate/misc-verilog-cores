`timescale 1ns / 100ps
/**
 * Parses USB packets to generate DDR3 controller requests, and then sends data,
 * or status responses.
 *
 * Todo:
 *  - read/write the status registers of other endpoints ??
 */
module memreq #(
    parameter FIFO_DEPTH = 512,
    parameter ADDRESS_WIDTH = 28,
    localparam AZERO = {ADDRESS_WIDTH{1'b0}},
    localparam ASB = ADDRESS_WIDTH - 1,
    parameter DATA_WIDTH = 32,
    localparam MSB = DATA_WIDTH - 1,
    parameter STROBES = DATA_WIDTH / 8,
    localparam SSB = STROBES - 1,
    parameter ID_WIDTH = 4,
    localparam ISB = ID_WIDTH - 1
) (
    input mem_clock, // DDR3 controller domain
    input mem_reset,

    input bus_clock, // SPI or USB domain
    input bus_reset,

    // From USB or SPI
    input s_tvalid,
    output s_tready,
    input s_tkeep,
    input s_tlast,
    input [7:0] s_tuser,

    // To USB or SPI
    output m_tvalid,
    input m_tready,
    output m_tkeep,
    output m_tlast,
    output [7:0] m_tdata,

    // Write -address, -data, & -response ports, to/from DDR3 controller
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

    // Read -address & -data ports, to/from the DDR3 controller
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

  `include "axi_defs.vh"

  // -- Datapath Signals -- //

  wire mux_enable_w, mux_select_w;

  wire x_tvalid, x_tready, x_tlast, y_tvalid, y_tready, y_tkeep, y_tlast;
  wire a_tvalid, a_tready, a_tkeep, a_tlast, b_tvalid, b_tready, b_tlast;
  wire z_tvalid, z_tready, z_tkeep, z_tlast;
  wire [7:0] y_tdata, b_tdata, z_tdata;
  wire [MSB:0] x_tdata, a_tdata;
  wire [ISB:0] y_tid, b_tid;

  // Write-buffer (FIFO) assignments, to the DDR3 controller
  assign wvalid_o = x_tvalid;
  assign x_tready = wready_i;
  assign wlast_o  = x_tlast;
  assign wstrb_o  = {STROBES{x_tvalid}};
  assign wdata_o  = x_tdata;

  // -- Finite State Machine (FSM) for Memory Requests -- //

  localparam ST_IDLE = 1;
  localparam ST_WADR = 2;
  localparam ST_WDAT = 4;
  localparam ST_RESP = 8;
  localparam ST_RADR = 16;
  localparam ST_RDAT = 32;
  localparam ST_SEND = 64;

  reg [6:0] state, snext;

  // -- Parser for Control Transfer Parameters -- //

  reg cyc_q, stb_q, req_q;
  reg [2:0] ptr_q;
  wire tkeep_w, end_w;

  assign req_done_w = end_w;  // Todo ...

  reg req_start_q, req_cycle_q;
  reg [ASB:0] req_addr_q;
  reg [ISB:0] req_id_q;
  reg [7:0] req_len_q;

  // Todo:
  //  - if there is more data after the 8th byte, then forward that out (via
  //    an AXI4-Stream skid-register) !?
  always @(posedge clock) begin
    if (!cyc_q) begin
      ptr_q <= 3'b000;
      req_len_q <= 0;
      req_start_q <= 1'b0;
      req_cycle_q <= 1'b0;
    end else if (req_q && s_tvalid && s_tkeep && s_tready) begin
      if (ptr_q == 7) begin
        if (!req_cycle_q) begin
          req_start_q <= 1'b1;
          req_cycle_q <= 1'b1;
        end
      end else begin
        ptr_q <= ptr_q + 1;
      end
    end else begin
      req_start_q <= 1'b0;
      req_cycle_q <= req_done_w ? 1'b0 : req_cycle_q;
    end
  end

  // -- Write Datapath -- //

  assign tkeep_w = state == ST_WDAT;

  axis_adapter #(
      .S_DATA_WIDTH(8),
      .S_KEEP_ENABLE(1),
      .S_KEEP_WIDTH(1),
      .M_DATA_WIDTH(DATA_WIDTH),
      .M_KEEP_ENABLE(1),
      .M_KEEP_WIDTH(STROBES),
      .ID_ENABLE(0),
      .ID_WIDTH(1),
      .DEST_ENABLE(0),
      .DEST_WIDTH(1),
      .USER_ENABLE(0),
      .USER_WIDTH(1)
  ) U_ADAPT1 (
      .clk(clock),
      .rst(reset),

      .s_axis_tvalid(s_tvalid),
      .s_axis_tready(s_tready),
      .s_axis_tkeep(tkeep_w),
      .s_axis_tlast(s_tlast),
      .s_axis_tid(1'b0),
      .s_axis_tdest(1'b0),
      .s_axis_tuser(1'b0),
      .s_axis_tdata(s_tdata),  // AXI input

      .m_axis_tvalid(a_tvalid),
      .m_axis_tready(a_tready),
      .m_axis_tkeep(a_tkeep),
      .m_axis_tlast(a_tlast),
      .m_axis_tid(),
      .m_axis_tdest(),
      .m_axis_tuser(),
      .m_axis_tdata(a_tdata)  // AXI output
  );

  axis_async_fifo #(
      .DEPTH(FIFO_DEPTH),
      .DATA_WIDTH(DATA_WIDTH),
      .KEEP_ENABLE(0),
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
      .FRAME_FIFO(0),
      .USER_BAD_FRAME_VALUE(0),
      .USER_BAD_FRAME_MASK(0),
      .DROP_BAD_FRAME(0),
      .DROP_WHEN_FULL(0)
  ) U_WRFIFO1 (
      .s_clk(bus_clock),
      .s_rst(bus_reset),

      .s_axis_tvalid(a_tvalid),
      .s_axis_tready(a_tready),
      .s_axis_tkeep(a_tkeep),
      .s_axis_tlast(a_tlast),
      .s_axis_tdata(a_tdata),  // AXI input
      .s_axis_tid(1'b0),
      .s_axis_tdest(1'b0),
      .s_axis_tuser(1'b0),

      .m_clk(mem_clock),
      .m_rst(mem_reset),

      .m_axis_tvalid(x_tvalid),
      .m_axis_tready(x_tready),
      .m_axis_tkeep(x_tkeep),
      .m_axis_tlast(x_tlast),
      .m_axis_tdata(x_tdata),  // AXI output
      .m_axis_tid(),
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

  // -- Read Datapath -- //

  axis_async_fifo #(
      .DEPTH(FIFO_DEPTH),
      .DATA_WIDTH(DATA_WIDTH),
      .KEEP_ENABLE(0),
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
      .FRAME_FIFO(1),
      .USER_BAD_FRAME_VALUE(0),
      .USER_BAD_FRAME_MASK(0),
      .DROP_BAD_FRAME(0),
      .DROP_WHEN_FULL(0)
  ) U_RDFIFO1 (
      .s_clk(mem_clock),
      .s_rst(mem_reset),

      .s_axis_tvalid(rvalid_i),
      .s_axis_tready(rready_o),
      .s_axis_tkeep({STROBES{rvalid_i}}),
      .s_axis_tlast(rlast_i),
      .s_axis_tdata(rdata_i),  // AXI input
      .s_axis_tid(rid_i),
      .s_axis_tdest(1'b0),
      .s_axis_tuser(1'b0),

      .m_clk(bus_clock),
      .m_rst(bus_reset),

      .m_axis_tvalid(b_tvalid),
      .m_axis_tready(b_tready),
      .m_axis_tkeep(b_tkeep),
      .m_axis_tlast(b_tlast),
      .m_axis_tid(b_tid),
      .m_axis_tdest(),
      .m_axis_tuser(),
      .m_axis_tdata(b_tdata),  // AXI output

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

  axis_adapter #(
      .S_DATA_WIDTH(DATA_WIDTH),
      .S_KEEP_ENABLE(1),
      .S_KEEP_WIDTH(STROBES),
      .M_DATA_WIDTH(8),
      .M_KEEP_ENABLE(1),
      .M_KEEP_WIDTH(1),
      .ID_ENABLE(0),
      .ID_WIDTH(ID_WIDTH),
      .DEST_ENABLE(0),
      .DEST_WIDTH(1),
      .USER_ENABLE(0),
      .USER_WIDTH(1)
  ) U_ADAPT2 (
      .clk(bus_clock),
      .rst(bus_reset),

      .s_axis_tvalid(b_tvalid),  // AXI input
      .s_axis_tready(b_tready),
      .s_axis_tkeep({STROBES{b_tvalid}}),
      .s_axis_tlast(b_tlast),
      .s_axis_tdata(b_tdata),
      .s_axis_tid(b_tid),
      .s_axis_tdest(1'b0),
      .s_axis_tuser(1'b0),

      .m_axis_tvalid(y_tvalid),  // AXI output
      .m_axis_tready(y_tready),
      .m_axis_tkeep(y_tkeep),
      .m_axis_tlast(y_tlast),
      .m_axis_tid(y_tid),
      .m_axis_tdest(),
      .m_axis_tuser(),
      .m_axis_tdata(y_tdata)
  );

  // -- Multiplexor to the SPI or USB Encoder -- //

  //
  // Todo:
  //  - 3x sources: Write Response, Read Data, Read Response ??
  //

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
      .clk(bus_clock),
      .rst(bus_reset),

      .enable(mux_enable_w),
      .select(mux_select_w),

      .s_axis_tvalid({z_tvalid, y_tvalid}),
      .s_axis_tready({z_tready, y_tready}),
      .s_axis_tkeep ({z_tkeep, y_tkeep}),
      .s_axis_tlast ({z_tlast, y_tlast}),
      .s_axis_tuser (2'bx),
      .s_axis_tid   (2'bx),
      .s_axis_tdest (2'bx),
      .s_axis_tdata ({z_tdata, y_tdata}),

      .m_axis_tvalid(m_tvalid),
      .m_axis_tready(m_tready),
      .m_axis_tkeep (m_tkeep),
      .m_axis_tlast (m_tlast),
      .m_axis_tuser (),
      .m_axis_tid   (),
      .m_axis_tdest (),
      .m_axis_tdata (m_tdata)
  );


endmodule  /* memreq */
