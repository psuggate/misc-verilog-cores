`timescale 1ns / 100ps
module bulk_telemetry #(
    parameter [3:0] ENDPOINT = 4'd2,
    parameter PACKET_SIZE = 8
) (
    input clock,
    input reset,

    input usb_enum_i,
    input usb_sof_i,
    input usb_recv_i,
    input usb_sent_i,
    input tok_recv_i,
    input high_speed_i,

    input crc_error_i,
    input timeout_i,
    input [3:0] phy_state_i,
    input [2:0] usb_error_i,
    input [3:0] usb_state_i,
    input [3:0] ctl_state_i,
    input [7:0] blk_state_i,

    input select_i,
    input start_i,
    input [3:0] endpt_i,
    output error_o,
    output [9:0] level_o,

    input s_tvalid,
    output s_tready,
    input s_tlast,
    input s_tkeep,
    input [7:0] s_tdata,

    output m_tvalid,
    input m_tready,
    output m_tlast,
    output m_tkeep,
    output [7:0] m_tdata
);

  localparam CBITS = $clog2(PACKET_SIZE);
  localparam CZERO = {CBITS{1'b0}};
  localparam CSB = CBITS - 1;


  // -- Current USB Configuration State -- //

  reg sel_q, crc_error_q, usb_sof_q;
  reg [3:0] phy_state_q, ctl_state_q;
  reg [2:0] blk_state_q, err_code_q;
  wire diff_w, valid_w, ready_w, last_w;
  wire [15:0] prev_w, curr_w;
  wire a_tvalid_w, a_tready_w, a_tlast_w;
  wire [7:0] a_tdata_w;


  // -- Input & Output Assignments -- //

  assign error_o = 1'b0;

  assign s_tready = sel_q;
  assign m_tvalid = sel_q && a_tvalid_w;
  assign a_tready_w = sel_q && m_tready;
  assign m_tlast = sel_q ? a_tlast_w : 1'bx;
  assign m_tkeep = sel_q && a_tvalid_w;
  assign m_tdata = sel_q ? a_tdata_w : 8'bx;

  assign valid_w = diff_w & ready_w;


  // -- Conversions and Packing -- //

  reg [2:0] blk_state_x, err_code_x;

  always @* begin
    if (timeout_i) begin
      err_code_x = 3'd7;
    end else if (usb_state_i == 4'h8) begin
      err_code_x = 3'd6;
    end else if (usb_sent_i) begin
      err_code_x = 3'd5;
    end else if (usb_recv_i) begin
      err_code_x = 3'd4;
    end else if (tok_recv_i) begin
      err_code_x = 3'd3;
    end else begin
      err_code_x = usb_error_i;
    end

    case (blk_state_i)
      8'h01:   blk_state_x = 3'd0;
      8'h02:   blk_state_x = 3'd1;
      8'h04:   blk_state_x = 3'd2;
      8'h08:   blk_state_x = 3'd3;
      8'h10:   blk_state_x = 3'd4;
      8'h20:   blk_state_x = 3'd5;
      8'h40:   blk_state_x = 3'd6;
      default: blk_state_x = 3'd7;
    endcase
  end


  // -- USB Start-of-Frames Every 32 ms -- //

  reg [7:0] sof_count;
  wire [8:0] sof_cnext = {1'b0, sof_count} + (high_speed_i ? 9'd1 : 9'd8);
  wire usb_sof_w = usb_sof_i && sof_cnext[8];

  // In HS-mode, there are 8x SOF per millisecond
  always @(posedge clock) begin
    if (reset) begin
      sof_count <= 8'd0;
      usb_sof_q <= 1'b0;
    end else begin
      if (usb_sof_i && !usb_sof_q) begin
        sof_count <= sof_cnext[7:0];
      end
      usb_sof_q <= usb_sof_w;
    end
  end


  // -- State-Change Detection and Telemetry Capture -- //

  assign prev_w = {crc_error_q, err_code_q, usb_sof_q, blk_state_q, ctl_state_q, phy_state_q};
  assign curr_w = {crc_error_i, err_code_x, usb_sof_w, blk_state_x, ctl_state_i, phy_state_i};
  assign diff_w = usb_enum_i && prev_w != curr_w;

  always @(posedge clock) begin
    if (reset) begin
      crc_error_q <= 1'b0;
      err_code_q  <= 3'd0;
      blk_state_q <= 3'd0;
      ctl_state_q <= 4'h0;
      phy_state_q <= 4'h0;
    end else begin
      crc_error_q <= crc_error_i;
      err_code_q  <= err_code_x;
      blk_state_q <= blk_state_x;
      ctl_state_q <= ctl_state_i;
      phy_state_q <= phy_state_i;
    end
  end


  // -- Telemetry Framer -- //

  reg  [  CSB:0] count;
  wire [CBITS:0] cnext = count + {{CBITS{1'b0}}, 1'b1};

  assign last_w = cnext[CBITS];

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
      if (usb_enum_i && start_i && select_i && endpt_i == ENDPOINT) begin
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
    if (0) begin : g_sync_fifo

      sync_fifo #(
          .WIDTH (17),
          .ABITS (10),
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
          .DEPTH(1024),
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

          // AXI input
          .s_axis_tdata(curr_w),
          .s_axis_tkeep(2'b11),
          .s_axis_tvalid(diff_w),
          .s_axis_tready(ready_w),
          .s_axis_tlast(last_w),
          .s_axis_tid(1'b0),
          .s_axis_tdest(1'b0),
          .s_axis_tuser(1'b0),

          .pause_req(1'b0),

          // AXI output
          .m_axis_tdata(x_tdata),
          .m_axis_tkeep(),
          .m_axis_tvalid(x_tvalid),
          .m_axis_tready(x_tready),
          .m_axis_tlast(x_tlast),
          .m_axis_tid(),
          .m_axis_tdest(),
          .m_axis_tuser(),
          // Status
          .status_depth(level_o),
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

      // AXI input
      .s_axis_tdata(x_tdata[15:0]),
      .s_axis_tkeep(2'b11),
      .s_axis_tvalid(x_tvalid),
      .s_axis_tready(x_tready),
      .s_axis_tlast(x_tlast),
      .s_axis_tid(1'b0),
      .s_axis_tdest(1'b0),
      .s_axis_tuser(1'b0),

      // AXI output
      .m_axis_tdata(a_tdata_w),
      .m_axis_tkeep(),
      .m_axis_tvalid(a_tvalid_w),
      .m_axis_tready(a_tready_w),
      .m_axis_tlast(a_tlast_w),
      .m_axis_tid(),
      .m_axis_tdest(),
      .m_axis_tuser()
  );


endmodule  // bulk_telemetry
