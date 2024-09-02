`timescale 1ns / 100ps
/**
 * Captures circuit values when change-detection events occur.
 */
module axis_logger #(
    parameter SRAM_BYTES = 2048,

    parameter FIFO_WIDTH = 32,
    localparam MSB = FIFO_WIDTH - 1,

    parameter FIFO_DEPTH = SRAM_BYTES / (FIFO_WIDTH >> 3),
    localparam FBITS = $clog2(FIFO_DEPTH),
    localparam FSB = FBITS - 1,

    parameter KEEP_ENABLE = 1,
    parameter KEEP_WIDTH = FIFO_WIDTH / 8,
    localparam KSB = KEEP_WIDTH - 1,
    localparam KEEPS = {KEEP_WIDTH{1'b1}},

    // Number of samples per 'tlast'
    parameter PACKET_SIZE = 8,
    localparam CBITS = $clog2(PACKET_SIZE),
    localparam CZERO = {CBITS{1'b0}},
    localparam CSB = CBITS - 1,

    // Only do change-detection for 'SIG_WIDTH' bits
    parameter SIG_WIDTH = 16,
    localparam IGN_WIDTH = FIFO_WIDTH - SIG_WIDTH,
    localparam SSB = SIG_WIDTH - 1,
    localparam ISB = IGN_WIDTH - 1
) (
    input clock,
    input reset,

    input enable_i,
    input [SSB:0] change_i,
    input [ISB:0] ignore_i,
    output [FBITS:0] level_o,

    output m_tvalid,
    input m_tready,
    output m_tlast,
    output m_tkeep,
    output [7:0] m_tdata
);

  // -- Current USB Configuration State -- //

  reg  [  SSB:0] prev_q;
  reg  [  CSB:0] count;
  wire [CBITS:0] cnext;
  wire c_tvalid, c_tready, c_tlast;
  wire x_tvalid, x_tready, x_tlast;
  wire [KSB:0] c_tkeep, x_tkeep;
  wire [MSB:0] c_tdata, x_tdata;

  assign cnext = count + {CZERO, 1'b1};

  assign c_tvalid = enable_i && change_i != prev_q;
  assign c_tkeep = KEEPS;
  assign c_tlast = cnext[CBITS];
  assign c_tdata = {ignore_i, change_i};

  // -- Telemetry Framer -- //

  always @(posedge clock) begin
    if (reset) begin
      prev_q <= {SIG_WIDTH{1'b1}};
    end else if (enable_i) begin
      prev_q <= change_i;
    end

    if (reset) begin
      count <= CZERO;
    end else if (c_tvalid) begin
      count <= cnext[CSB:0];
    end
  end

  // -- Block SRAM FIFO for Telemetry -- //

  axis_fifo #(
      .DEPTH(FIFO_DEPTH),
      .DATA_WIDTH(FIFO_WIDTH),
      .KEEP_ENABLE(KEEP_ENABLE),
      .KEEP_WIDTH(KEEP_WIDTH),
      .LAST_ENABLE(1),
      .ID_ENABLE(0),
      .ID_WIDTH(1),
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
  ) U_FIFO4 (
      .clk(clock),
      .rst(reset),

      .s_axis_tvalid(c_tvalid),
      .s_axis_tready(c_tready),
      .s_axis_tkeep(c_tkeep),
      .s_axis_tlast(c_tlast),
      .s_axis_tdata(c_tdata),  // AXI input
      .s_axis_tid(1'b0),
      .s_axis_tdest(1'b0),
      .s_axis_tuser(1'b0),

      .pause_req(1'b0),

      .m_axis_tvalid(x_tvalid),
      .m_axis_tready(x_tready),
      .m_axis_tkeep(x_tkeep),
      .m_axis_tlast(x_tlast),
      .m_axis_tdata(x_tdata),  // AXI output
      .m_axis_tid(),
      .m_axis_tdest(),
      .m_axis_tuser(),

      .status_depth(level_o),  // Status
      .status_overflow(),
      .status_bad_frame(),
      .status_good_frame()
  );

  wire [KSB:0] tkeep_w;
  assign tkeep_w = KEEP_ENABLE ? x_tkeep : KEEPS;

  axis_adapter #(
      .S_DATA_WIDTH(FIFO_WIDTH),
      .S_KEEP_ENABLE(1),
      .S_KEEP_WIDTH(KEEP_WIDTH),
      .M_DATA_WIDTH(8),
      .M_KEEP_ENABLE(1),
      .M_KEEP_WIDTH(1),
      .ID_ENABLE(0),
      .ID_WIDTH(1),
      .DEST_ENABLE(0),
      .DEST_WIDTH(1),
      .USER_ENABLE(0),
      .USER_WIDTH(1)
  ) U_ADAPT0 (
      .clk(clock),
      .rst(reset),

      .s_axis_tvalid(x_tvalid),
      .s_axis_tready(x_tready),
      .s_axis_tkeep(tkeep_w),
      .s_axis_tlast(x_tlast),
      .s_axis_tdata(x_tdata),  // AXI input
      .s_axis_tid(1'b0),
      .s_axis_tdest(1'b0),
      .s_axis_tuser(1'b0),

      .m_axis_tvalid(m_tvalid),
      .m_axis_tready(m_tready),
      .m_axis_tkeep(m_tkeep),
      .m_axis_tlast(m_tlast),
      .m_axis_tdata(m_tdata),  // AXI output
      .m_axis_tid(),
      .m_axis_tdest(),
      .m_axis_tuser()
  );

endmodule  /* axis_logger */
