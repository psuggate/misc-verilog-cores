`timescale 1ns / 100ps
module ddr3_telemetry #(
    parameter [3:0] ENDPOINT = 4'd2,
    parameter PACKET_SIZE = 8,
    parameter SMALL_FIFO = 1,
    parameter FIFO_DEPTH = 2048,

    localparam CBITS = $clog2(PACKET_SIZE),
    localparam CZERO = {CBITS{1'b0}},
    localparam CSB   = CBITS - 1,

    localparam FBITS = $clog2(FIFO_DEPTH) + SMALL_FIFO,
    localparam FSB   = FBITS - 1
) (
    input clock,
    input reset,

    input [4:0] fsm_state_i,
    input [4:0] fsm_snext_i,
    input [2:0] ddl_state_i,
    input cfg_rst_ni,
    input cfg_run_i,
    input cfg_req_i,
    input cfg_ref_i,
    input [2:0] cfg_cmd_i,

    // Read-back
    input enable_i,
    input select_i,
    input start_i,
    input [3:0] endpt_i,
    output [FSB:0] level_o,

    output m_tvalid,
    input m_tready,
    output m_tlast,
    output m_tkeep,
    output [7:0] m_tdata
);

  /**
   * Records the DDR3 core's state-changes, for debugging and logging of DDR3
   * SDRAM initialisation and transactions.
   */

  // -- State and Signals -- //

  // Telemetry-core state //
  reg sel_q, err_q;

  // Previous DDR3 core state //
  reg [2:0] fsm_state_q, fsm_snext_q, ddl_state_q, cfg_cmd_q;
  reg cfg_rst_nq, cfg_run_q, cfg_req_q, cfg_ref_q;

  wire [15:0] curr_w, prev_w;
  wire diff_w, valid_w, ready_w, last_w;
  wire a_tvalid_w, a_tready_w, a_tlast_w;
  wire [7:0] a_tdata_w;

  // Telemetry-framing state //
  reg [CSB:0] count;
  wire [CBITS:0] cnext = count + {{CBITS{1'b0}}, 1'b1};


  // -- Input & Output Assignments -- //

  assign m_tvalid = sel_q && a_tvalid_w;
  assign a_tready_w = sel_q && m_tready;
  assign m_tlast = sel_q ? a_tlast_w : 1'bx;
  assign m_tkeep = sel_q && a_tvalid_w;
  assign m_tdata = sel_q ? a_tdata_w : 8'bx;

  assign valid_w = diff_w & ready_w;
  assign last_w = cnext[CBITS];


  // -- Conversions and Packing -- //

  reg [2:0] fsm_state_x, fsm_snext_x;

  always @* begin
    case (fsm_state_i)
      5'h01:   fsm_state_x = 3'd0;
      5'h02:   fsm_state_x = 3'd1;
      5'h04:   fsm_state_x = 3'd2;
      5'h08:   fsm_state_x = 3'd3;
      5'h10:   fsm_state_x = 3'd4;
      default: fsm_state_x = 3'd7;
    endcase
    case (fsm_snext_i)
      5'h01:   fsm_snext_x = 3'd0;
      5'h02:   fsm_snext_x = 3'd1;
      5'h04:   fsm_snext_x = 3'd2;
      5'h08:   fsm_snext_x = 3'd3;
      5'h10:   fsm_snext_x = 3'd4;
      default: fsm_snext_x = 3'd7;
    endcase
  end


  // -- State-Change Detection and Telemetry Capture -- //

  assign prev_w = {
    cfg_cmd_q, cfg_ref_q, cfg_req_q, cfg_run_q, cfg_rst_nq, ddl_state_q, fsm_snext_q, fsm_state_q
  };
  assign curr_w = {
    cfg_cmd_i, cfg_ref_i, cfg_req_i, cfg_run_i, cfg_rst_ni, ddl_state_i, fsm_snext_x, fsm_state_x
  };
  assign diff_w = enable_i && prev_w != curr_w;

  always @(posedge clock) begin
    if (reset) begin
      cfg_cmd_q   <= 3'd7;
      cfg_ref_q   <= 1'b0;
      cfg_req_q   <= 1'b0;
      cfg_run_q   <= 1'b0;
      cfg_rst_nq  <= 1'b0;
      ddl_state_q <= 3'd0;
      fsm_snext_q <= 3'd7;
      fsm_state_q <= 3'd7;
    end else begin
      cfg_cmd_q   <= cfg_cmd_i;
      cfg_ref_q   <= cfg_ref_i;
      cfg_req_q   <= cfg_req_i;
      cfg_run_q   <= cfg_run_i;
      cfg_rst_nq  <= cfg_rst_ni;
      ddl_state_q <= ddl_state_i;
      fsm_snext_q <= fsm_snext_x;
      fsm_state_q <= fsm_state_x;
    end
  end


  // -- Telemetry Framer -- //

  always @(posedge clock) begin
    if (reset) begin
      count <= CZERO;
    end else if (valid_w) begin
      count <= cnext[CSB:0];
    end
  end


  // -- Chip Select -- //

  always @(posedge clock) begin
    if (reset) begin
      sel_q <= 1'b0;
    end else begin
      if (enable_i && start_i && select_i && endpt_i == ENDPOINT) begin
        sel_q <= 1'b1;
      end else if (m_tvalid && m_tready && m_tlast) begin
        sel_q <= 1'b0;
      end
    end
  end


  // -- Block SRAM FIFO for Telemetry -- //

  wire x_tvalid, x_tready, x_tlast;
  wire [15:0] x_tdata;

  generate
    if (!SMALL_FIFO) begin : g_sync_fifo

      sync_fifo #(
          .WIDTH (17),
          .ABITS (FBITS),
          .OUTREG(3)
      ) U_TELEMETRY0 (
          .clock(clock),
          .reset(reset),

          .level_o(level_o),

          .valid_i(valid_w),
          .ready_o(ready_w),
          .data_i ({last_w, curr_w}),

          .valid_o(x_tvalid),
          .ready_i(x_tready),
          .data_o ({x_tlast, x_tdata})
      );

    end else begin : g_axis_fifo

      axis_fifo #(
          .DEPTH(FIFO_DEPTH),
          .DATA_WIDTH(16),
          .KEEP_ENABLE(0),
          .KEEP_WIDTH(2),
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
      ) U_BULK_FIFO0 (
          .clk(clock),
          .rst(reset),

          .s_axis_tdata(curr_w),  // AXI input
          .s_axis_tkeep(2'd3),
          .s_axis_tvalid(diff_w),
          .s_axis_tready(ready_w),
          .s_axis_tlast(last_w),
          .s_axis_tid(1'b0),
          .s_axis_tdest(1'b0),
          .s_axis_tuser(1'b0),

          .pause_req(1'b0),

          .m_axis_tdata(x_tdata),  // AXI output
          .m_axis_tkeep(),
          .m_axis_tvalid(x_tvalid),
          .m_axis_tready(x_tready),
          .m_axis_tlast(x_tlast),
          .m_axis_tid(),
          .m_axis_tdest(),
          .m_axis_tuser(),

          .status_depth(level_o),  // Status
          .status_overflow(),
          .status_bad_frame(),
          .status_good_frame()
      );

    end
  endgenerate

  axis_adapter #(
      .S_DATA_WIDTH(16),
      .S_KEEP_ENABLE(1),
      .S_KEEP_WIDTH(2),
      .M_DATA_WIDTH(8),
      .M_KEEP_ENABLE(1),
      .M_KEEP_WIDTH(1),
      .ID_ENABLE(0),
      .ID_WIDTH(1),
      .DEST_ENABLE(0),
      .DEST_WIDTH(1),
      .USER_ENABLE(0),
      .USER_WIDTH(1)
  ) U_ADAPTER0 (
      .clk(clock),
      .rst(reset),

      .s_axis_tdata(x_tdata),  // AXI input
      .s_axis_tkeep(2'd3),
      .s_axis_tvalid(x_tvalid),
      .s_axis_tready(x_tready),
      .s_axis_tlast(x_tlast),
      .s_axis_tid(1'b0),
      .s_axis_tdest(1'b0),
      .s_axis_tuser(1'b0),

      .m_axis_tdata(a_tdata_w),  // AXI output
      .m_axis_tkeep(),
      .m_axis_tvalid(a_tvalid_w),
      .m_axis_tready(a_tready_w),
      .m_axis_tlast(a_tlast_w),
      .m_axis_tid(),
      .m_axis_tdest(),
      .m_axis_tuser()
  );


endmodule  // ddr3_telemetry
