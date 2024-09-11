`timescale 1ns / 100ps
/**
 * Synchronous FIFO with AXI-Stream signaling.
 *
 * Various FPGA SRAM-types can be supported, with either zero or one pipeline-
 * registers (within the SRAM primitive), with additional pipeline registers, as
 * well as supporting fast-reads (similar to First-Word-Fall-Through, FWFT), if
 * desired.
 *
 * There are four output pipeline settings, with the last two instantiating a
 * skid-buffer, for the output data, so that registered-output SRAM's can be
 * used; e.g., Xilinx Block SRAMs, or GoWin BSRAMs, and without additional wait-
 * states when stopping and starting.
 *
 * Notes:
 *  - OUTREG = 0 for a FIFO that supports LUT-SRAMs with asynchronous reads
 *  - OUTREG = 1 for the smallest block-SRAM FIFO
 *  - OUTREG = 2 for a block-SRAM FIFO with First-Word Fall-Through (FWFT)
 *  - OUTREG = 3 for a block-SRAM, FWFT FIFO with "double-fall-through"
 */
module axis_sfifo #(
    parameter WIDTH = 8,
    localparam MSB = WIDTH - 1,
    localparam KEEPS = WIDTH / 8,
    localparam KZERO = {KEEPS{1'b0}},
    localparam KSB = KEEPS - 1,
    parameter DEPTH = 2048,
    localparam ABITS = $clog2(DEPTH),
    localparam ASB = ABITS - 1,
    parameter USELIB = 0,
    parameter BYPASS = 0,
    parameter OUTREG = 1,  // 0, 1, 2, or 3
    parameter TKEEP = 0,  // 0, 1
    parameter TLAST = 1  // 0, 1
) (
    input clock,
    input reset,

    output [ASB:0] level_o,

    input s_tvalid,
    output s_tready,
    input [KSB:0] s_tkeep,
    input s_tlast,
    input [MSB:0] s_tdata,

    output m_tvalid,
    input m_tready,
    output [KSB:0] m_tkeep,
    output m_tlast,
    output [MSB:0] m_tdata
);

  generate
    if (BYPASS == 1) begin : g_bypass

      // No buffering
      assign m_tvalid = s_tvalid;
      assign s_tready = m_tready;
      assign m_tkeep  = s_tkeep;
      assign m_tlast  = s_tlast;
      assign m_tdata  = s_tdata;

      initial begin
        $display("=> Bypassing AXI-S '%m'");
      end

    end // g_bypass
  else if (USELIB) begin : g_lib_fifo

      wire [ABITS:0] level_w;

      assign level_o = level_w[ASB:0];

      // Use the "library" version (by Alex Forencich), as it is smaller (but it
      // has combinational delays on some of its outputs, reducing f_max).

      axis_fifo #(
          .DEPTH(DEPTH),
          .DATA_WIDTH(WIDTH),
          .KEEP_ENABLE(TKEEP),
          .KEEP_WIDTH(KEEPS),
          .LAST_ENABLE(TLAST),
          .ID_ENABLE(0),
          .ID_WIDTH(1),
          .DEST_ENABLE(0),
          .DEST_WIDTH(1),
          .USER_ENABLE(0),
          .USER_WIDTH(1),
          .RAM_PIPELINE(OUTREG > 0),
          .OUTPUT_FIFO_ENABLE(0),
          .FRAME_FIFO(0),
          .USER_BAD_FRAME_VALUE(0),
          .USER_BAD_FRAME_MASK(0),
          .DROP_BAD_FRAME(0),
          .DROP_WHEN_FULL(0)
      ) U_FIFO1 (
          .clk(clock),
          .rst(reset),

          .s_axis_tvalid(s_tvalid),
          .s_axis_tready(s_tready),
          .s_axis_tkeep(s_tkeep),
          .s_axis_tlast(s_tlast),
          .s_axis_tid(1'b0),
          .s_axis_tdest(1'b0),
          .s_axis_tuser(1'b0),
          .s_axis_tdata(s_tdata),

          .pause_req(1'b0),
          .pause_ack(),

          .m_axis_tvalid(m_tvalid),
          .m_axis_tready(m_tready),
          .m_axis_tkeep(m_tkeep),
          .m_axis_tlast(m_tlast),
          .m_axis_tid(),
          .m_axis_tdest(),
          .m_axis_tuser(),
          .m_axis_tdata(m_tdata),

          .status_depth(level_w),
          .status_depth_commit(),
          .status_overflow(),
          .status_bad_frame(),
          .status_good_frame()
      );

    end else begin : g_axis_afifo

      localparam WBITS = WIDTH + TLAST + KEEPS;
      localparam WSB = WBITS - 1;
      localparam SBITS = WIDTH + TLAST + (TKEEP ? KEEPS : 0);
      localparam SSB = SBITS - 1;

      wire [WSB:0] sdata_w = {s_tkeep, s_tlast, s_tdata};
      wire [WSB:0] mdata_w;

      assign m_tkeep = TKEEP ? mdata_w[WSB:WIDTH-KEEPS] : KZERO;
      assign m_tlast = TLAST ? mdata_w[WIDTH] : 1'b0;
      assign m_tdata = mdata_w[MSB:0];

      sync_fifo #(
          .WIDTH (SBITS),
          .ABITS (ABITS),
          .OUTREG(OUTREG)
      ) U_FIFO1 (
          .clock  (clock),
          .reset  (reset),
          .level_o(level_o),

          .valid_i(s_tvalid),
          .ready_o(s_tready),
          .data_i (sdata_w[SSB:0]),

          .valid_o(m_tvalid),
          .ready_i(m_tready),
          .data_o (mdata_w)
      );

    end  // g_axis_afifo
  endgenerate


endmodule  /* axis_sfifo */
