`timescale 1ns / 100ps
module usb_demo_top (
    // Clock and reset from the dev-board
    input clk_26,
    input rst_n,

    output [5:0] leds,

    // USB ULPI pins on the dev-board
    input ulpi_clk,
    output ulpi_rst,
    input ulpi_dir,
    input ulpi_nxt,
    output ulpi_stp,
    inout [7:0] ulpi_data
);

  // -- Constants -- //

  parameter integer SERIAL_LENGTH = 8;
  parameter [SERIAL_LENGTH*8-1:0] SERIAL_STRING = "TART0001";

  parameter [15:0] VENDOR_ID = 16'hF4CE;
  parameter integer VENDOR_LENGTH = 19;
  parameter [VENDOR_LENGTH*8-1:0] VENDOR_STRING = "University of Otago";

  parameter [15:0] PRODUCT_ID = 16'h0003;
  parameter integer PRODUCT_LENGTH = 8;
  parameter [PRODUCT_LENGTH*8-1:0] PRODUCT_STRING = "TART USB";

  // USB configuration
  localparam FPGA_VENDOR = "gowin";
  localparam FPGA_FAMILY = "gw2a";

  localparam HIGH_SPEED = 1'b1;
  localparam ULPI_DDR_MODE = 0;  // todo: '1' is way too fussy


  // -- Signals -- //

  // Globalists //
  wire clock, reset, usb_clock, usb_reset;
  wire ddr_clock, locked;
  wire [3:0] cbits;

  assign leds = {~cbits[3:0], 2'b11};


  // -- System Clocks & Resets -- //

  ulpi_reset #(
      .PHASE("0111"),
      .PLLEN(ULPI_DDR_MODE)
  ) U_RESET0 (
      .areset_n (rst_n),
      .ulpi_clk (ulpi_clk),
      .sys_clock(clk_26),

      .ulpi_rst_n(ulpi_rst),  // Active LO
      .pll_locked(locked),

      .usb_clock(clock),  // 60 MHz, PLL output, phase-shifted
      .usb_reset(reset),  // Active HI
      .ddr_clock(ddr_clock)  // 120 MHz, PLL output, phase-shifted
  );


  // Local Signals //
  wire device_usb_idle_w, dev_crc_err_w, usb_hs_enabled_w;
  wire usb_sof, configured, blk_cycle_w, has_telemetry_w, timeout_w;

  // Data-path //
  wire s_tvalid, s_tready, s_tlast;
  wire [7:0] s_tdata;

  wire m_tvalid, m_tready, m_tlast, m_tkeep;
  wire [ 7:0] m_tdata;

  // FIFO state //
  wire [10:0] level_w;
  reg bulk_in_ready_q, bulk_out_ready_q;


  // -- USB ULPI Bulk transfer endpoint (IN & OUT) -- //

  assign m_tkeep = m_tvalid; // todo: ...


  //
  // Core Under New Tests
  ///
  ulpi_axis_bridge #(
      .VENDOR_ID(VENDOR_ID),
      .VENDOR_LENGTH(VENDOR_LENGTH),
      .VENDOR_STRING(VENDOR_STRING),
      .PRODUCT_ID(PRODUCT_ID),
      .PRODUCT_LENGTH(PRODUCT_LENGTH),
      .PRODUCT_STRING(PRODUCT_STRING),
      .SERIAL_LENGTH(SERIAL_LENGTH),
      .SERIAL_STRING(SERIAL_STRING),
      .EP1_CONTROL(0),
      .ENDPOINT1(1),
      .EP2_CONTROL(0),
      .ENDPOINT2(2)
  ) U_ULPI_USB0 (
      .areset_n(~reset),

      .ulpi_clock_i(clock),
      .ulpi_dir_i  (ulpi_dir),
      .ulpi_nxt_i  (ulpi_nxt),
      .ulpi_stp_o  (ulpi_stp),
      .ulpi_data_io(ulpi_data),

      .usb_clock_o(usb_clock),
      .usb_reset_o(usb_reset),

      .configured_o(configured),
      .has_telemetry_o(has_telemetry_w),
      .usb_hs_enabled_o(usb_hs_enabled_w),
      .usb_idle_o(device_usb_idle_w),
      .usb_sof_o(usb_sof),
      .crc_err_o(dev_crc_err_w),
      .timeout_o(timeout_w),

      // USB bulk endpoint data-paths
      .blk_in_ready_i(bulk_in_ready_q),
      .blk_out_ready_i(bulk_out_ready_q),
      .blk_start_o(),
      .blk_cycle_o(blk_cycle_w),
      .blk_endpt_o(),
      .blk_error_i(1'b0),

      .s_axis_tvalid_i(m_tvalid && blk_cycle_w),
      .s_axis_tready_o(m_tready),
      .s_axis_tlast_i (m_tlast),
      .s_axis_tkeep_i (m_tkeep),
      .s_axis_tdata_i (m_tdata),

      .m_axis_tvalid_o(s_tvalid),
      .m_axis_tready_i(s_tready && blk_cycle_w),
      .m_axis_tlast_o (s_tlast),
      .m_axis_tdata_o (s_tdata)
  );


  // -- Loop-back FIFO for Testing -- //

  generate
    if (1) begin : g_sync_fifo

      sync_fifo #(
          .WIDTH (9),
          .ABITS (11),
          .OUTREG(3)
      ) U_BULK_FIFO0 (
          .clock(usb_clock),
          .reset(usb_reset),

          .level_o(level_w),

          .valid_i(s_tvalid && blk_cycle_w),
          .ready_o(s_tready),
          .data_i ({s_tlast, s_tdata}),

          .valid_o(m_tvalid),
          .ready_i(m_tready && blk_cycle_w),
          .data_o ({m_tlast, m_tdata})
      );

    end else begin : g_axis_fifo

      axis_fifo #(
          .DEPTH(2048),
          .DATA_WIDTH(8),
          .KEEP_ENABLE(0),
          .KEEP_WIDTH(1),
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
          .clk(usb_clock),
          .rst(usb_reset),

          // AXI input
          .s_axis_tdata(s_tdata),
          .s_axis_tkeep(1'b1),
          .s_axis_tvalid(s_tvalid && blk_cycle_w),
          .s_axis_tready(s_tready),
          .s_axis_tlast(s_tlast),
          .s_axis_tid(1'b0),
          .s_axis_tdest(1'b0),
          .s_axis_tuser(1'b0),

          .pause_req(0),

          // AXI output
          .m_axis_tdata(m_tdata),
          .m_axis_tkeep(),
          .m_axis_tvalid(m_tvalid),
          .m_axis_tready(m_tready && blk_cycle_w),
          .m_axis_tlast(m_tlast),
          .m_axis_tid(),
          .m_axis_tdest(),
          .m_axis_tuser(),
          // Status
          .status_depth(level_w),
          .status_overflow(),
          .status_bad_frame(),
          .status_good_frame()
      );

    end
  endgenerate


  // --Bulk Endpoint Status -- //

  always @(posedge usb_clock) begin
    if (usb_reset) begin
      bulk_in_ready_q <= 1'b0;
    end else begin
      bulk_in_ready_q  <= configured && level_w > 4;
      bulk_out_ready_q <= configured && level_w < 1024;
    end
  end


  // -- LEDs Stuffs -- //

  // Miscellaneous
  reg [23:0] count;
  reg [31:0] ucount, pcount, dcount;
  reg sof_q, ctl_latch_q = 0, crc_error_q = 0;
  reg  blk_valid_q = 0;

  wire blinky_w = crc_error_q ? count[10] & count[11] : count[12];
  wire ctl0_error_w = U_ULPI_USB0.ctl0_error_w;

  wire xfer_state_w = U_ULPI_USB0.U_TRANSACT1.xfer_idle_w;
  wire xfer_error_w = U_ULPI_USB0.U_TRANSACT1.xfer_dzdp_w && bulk_in_ready_q;
  // wire xfer_error_w = U_ULPI_USB0.U_USB_CTRL0.U_USB_TRN0.xfer_dzdp_w || U_ULPI_USB0.U_USB_CTRL0.U_USB_TRN0.xfer_derr_w;
  // wire xfer_error_w = U_ULPI_USB0.U_USB_CTRL0.U_USB_TRN0.xfer_derr_w;

  // assign cbits = {ucount[24], pcount[24], ulpi_rst, locked};
  // assign cbits = {blinky_w, ctl_latch_q, xfer_state_w, blk_valid_q};
  assign cbits = U_ULPI_USB0.U_LINESTATE1.state;

  always @(posedge usb_clock) begin
    if (usb_reset) begin
      ctl_latch_q <= 1'b0;
      // end else if (U_ULPI_USB0.U_USB_CTRL0.U_DECODER0.tok_ping_q) begin
      // end else if (xfer_error_w) begin
    end else if (timeout_w) begin
      ctl_latch_q <= 1'b1;
    end

    /*
    if (ctl0_error_w) begin
      ctl_latch_q <= 1'b1;
    end

    if (usb_reset) begin
      blk_valid_q <= 1'b0;
    end else begin
      blk_valid_q <= bulk_in_ready_q || bulk_out_ready_q;  // m_tvalid;
    end
     */

    blk_valid_q <= has_telemetry_w;

    if (usb_reset) begin
      crc_error_q <= 1'b0;
    end else if (dev_crc_err_w) begin
      crc_error_q <= 1'b1;
    end
  end


  always @(posedge usb_clock) begin
    if (usb_reset) begin
      count <= 0;
      sof_q <= 1'b0;
    end else begin
      sof_q <= usb_sof;

      if (usb_sof && !sof_q) begin
        count <= count + 1;
      end
    end
  end


  always @(posedge ddr_clock) begin
    dcount <= dcount + 1;
  end

  always @(posedge ulpi_clk) begin
    ucount <= ucount + 1;
  end

  always @(posedge clock) begin
    pcount <= pcount + 1;
  end


endmodule  // usb_demo_top
