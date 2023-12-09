`timescale 1ns / 100ps
module control_endpoint #(
    parameter [3:0] ENDPOINT = 4'd1
) (
    input clock,
    input reset,

    input usb_enum_i,

    input crc_error_i,
    input [3:0] usb_state_i,
    input [3:0] ctl_state_i,
    input [7:0] blk_state_i,

    input select_i,
    input start_i,
    output error_o,
    output [9:0] level_o,

    input [ 3:0] req_endpt,
    input [ 7:0] req_type,
    input [ 7:0] req_args,
    input [15:0] req_value,
    input [15:0] req_index,
    input [15:0] req_length,

    input s_tvalid,
    output s_tready,
    input s_tlast,
    input [7:0] s_tdata,

    output m_tvalid,
    input m_tready,
    output m_tlast,
    output [7:0] m_tdata
);


  // -- Current USB Configuration State -- //

  reg sel_q, crc_error_q;
  reg [3:0] usb_state_q, ctl_state_q;
  reg [7:0] blk_state_q;
  wire changed_w, ready_w, last_w;
  wire [16:0] previous_w, current_w;
  wire a_tvalid_w, a_tready_w, a_tlast_w;
  wire [7:0] a_tdata_w;


  // -- Input & Output Assignments -- //

  assign error_o = 1'b0;

  assign s_tready = sel_q;
  assign m_tvalid = sel_q && a_tvalid_w;
  assign a_tready_w = sel_q && m_tready;
  assign m_tlast = sel_q ? a_tlast_w : 1'bx;
  assign m_tdata = sel_q ? a_tdata_w : 8'bx;


  // -- State-Change Detection and Telemetry Capture -- //

  assign previous_w = {crc_error_q, usb_state_q, ctl_state_q, blk_state_q};
  assign current_w = {crc_error_i, usb_state_i, ctl_state_i, blk_state_i};
  assign changed_w = usb_enum_i && previous_w != current_w;

  always @(posedge clock) begin
    if (reset) begin
      crc_error_q <= 1'b0;
      usb_state_q <= 4'h0;
      ctl_state_q <= 4'h0;
      blk_state_q <= 8'h0;
    end else begin
      crc_error_q <= crc_error_i;
      usb_state_q <= usb_state_i;
      ctl_state_q <= ctl_state_i;
      blk_state_q <= blk_state_i;
    end
  end


  // -- Telemetry Framer -- //

  reg  [2:0] count;
  wire [3:0] cnext = count + 3'd1;

  assign last_w = cnext[3];

  always @(posedge clock) begin
    if (reset) begin
      count <= 3'd0;
    end else begin
      if (changed_w && ready_w) begin
        count <= cnext[2:0];
      end
    end
  end


  // -- Chip Select -- //

  always @(posedge clock) begin
    if (reset) begin
      sel_q <= 1'b0;
    end else begin
      if (usb_enum_i && start_i && select_i && req_endpt == ENDPOINT) begin
        sel_q <= 1'b1;
      end else if (m_tvalid && m_tready && m_tlast) begin
        sel_q <= 1'b0;
      end
    end
  end


  // -- Block SRAM FIFO for Telemetry -- //

  wire x_tvalid, x_tready, x_tlast;
  wire [16:0] x_tdata;

  sync_fifo #(
      .WIDTH (18),
      .ABITS (10),
      .OUTREG(3)
  ) U_TELEMETRY0 (
      .clock(clock),
      .reset(reset),

      .level_o(level_o),

      .valid_i(changed_w),
      .ready_o(ready_w),
      .data_i ({last_w, current_w}),

      .valid_o(x_tvalid),
      .ready_i(x_tready),
      .data_o ({x_tlast, x_tdata})
  );

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


endmodule  // control_endpoint
