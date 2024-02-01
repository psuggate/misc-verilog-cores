`timescale 1ns / 100ps
module usb_demo_top (
    // Clock and reset from the dev-board
    input clk_26,
    input rst_n,   // 'S2' button for async-reset

    input send_n,  // 'S4' button for telemetry read-back
    output [5:0] leds,

    input  uart_rx,  // '/dev/ttyUSB1'
    output uart_tx,

    // USB ULPI pins on the dev-board
    input ulpi_clk,
    output ulpi_rst,
    input ulpi_dir,
    input ulpi_nxt,
    output ulpi_stp,
    inout [7:0] ulpi_data
);

  // -- Constants -- //

  parameter [15:0] VENDOR_ID = 16'hF4CE;
  parameter integer VENDOR_LENGTH = 19;
  localparam integer VSB = VENDOR_LENGTH * 8 - 1;
  parameter [VSB:0] VENDOR_STRING = "University of Otago";

  parameter [15:0] PRODUCT_ID = 16'h0003;
  parameter integer PRODUCT_LENGTH = 8;
  localparam integer PSB = PRODUCT_LENGTH * 8 - 1;
  parameter [PSB:0] PRODUCT_STRING = "TART USB";

  parameter integer SERIAL_LENGTH = 8;
  localparam integer SSB = SERIAL_LENGTH * 8 - 1;
  parameter [SSB:0] SERIAL_STRING = "TART0001";

  // USB-core configuration
  localparam PIPELINED = 1;
  localparam HIGH_SPEED = 1'b1;  // Note: USB FS (Full-Speed) not supported
  localparam ULPI_DDR_MODE = 0;  // todo: '1' is way too fussy

  // USB BULK IN/OUT SRAM parameters
  parameter USE_SYNC_FIFO = 1;
  localparam integer FIFO_LEVEL_BITS = USE_SYNC_FIFO ? 11 : 12;
  localparam integer FSB = FIFO_LEVEL_BITS - 1;
  localparam integer BULK_FIFO_SIZE = 2048;

  // USB UART settings
  localparam [15:0] UART_PRESCALE = 16'd33;  // For: 60.0 MHz / (230400 * 8)
  // localparam [15:0] UART_PRESCALE = 16'd65;  // For: 60.0 MHz / (115200 * 8)
  // localparam [15:0] UART_PRESCALE = 16'd781;  // For: 60.0 MHz / (9600 * 8)
  // localparam [15:0] UART_PRESCALE = 16'd3125;  // For: 60.0 MHz / (2400 * 8)


  // -- Signals -- //

  // Global signals //
  wire clock, reset, usb_clock, usb_reset;
  wire ddr_clock, locked;
  wire [3:0] cbits;

  // Local Signals //
  wire device_usb_idle_w, crc_error_w, hs_enabled_w;
  wire usb_sof_w, configured, blk_cycle_w, has_telemetry_w, timeout_w;

  // Data-path //
  wire s_tvalid, s_tready, s_tlast, s_tkeep;
  wire [7:0] s_tdata;

  wire m_tvalid, m_tready, m_tlast, m_tkeep;
  wire [  7:0] m_tdata;

  // FIFO state //
  wire [FSB:0] level_w;
  reg bulk_in_ready_q, bulk_out_ready_q;

  // Telemetry signals //
  wire ctl_cycle_w, ctl_error_w, usb_rx_recv_w, usb_tx_done_w, tok_rx_recv_w;
  wire [3:0] phy_state_w, usb_state_w, ctl_state_w, usb_tuser_w, tok_endpt_w;
  wire [2:0] err_code_w;
  wire [7:0] blk_state_w;
  wire [1:0] LineState;


  // -- System Clocks & Resets -- //

  ulpi_reset #(
      .PHASE("0000"),  // Note: timing-constraints used instead
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


  // -- LEDs Stuffs -- //

  // Note: only 4 (of 6) LED's available in default config
  assign cbits = phy_state_w;
  assign leds  = {~cbits[3:0], 2'b11};


  // For a Basic LED Flasher //
  reg [31:0] pcount;

  always @(posedge clock) begin
    pcount <= pcount + 1;
  end


  // -- ULPI Core and BULK IN/OUT SRAM -- //

  wire bsvalid_w, bsready_w, bmvalid_w, bmready_w;

  assign bsvalid_w = s_tvalid && blk_cycle_w;
  assign bsready_w = s_tready && blk_cycle_w;
  assign bmvalid_w = m_tvalid && blk_cycle_w;
  assign bmready_w = m_tready && blk_cycle_w;

  // Bulk Endpoint Status //
  always @(posedge usb_clock) begin
    if (usb_reset) begin
      bulk_in_ready_q  <= 1'b0;
      bulk_out_ready_q <= 1'b0;
    end else begin
      bulk_in_ready_q  <= configured && level_w > 4;
      bulk_out_ready_q <= configured && level_w < 1024;
    end
  end


  //
  // Core Under New Tests
  ///
  ulpi_axis_bridge #(
      .PIPELINED(PIPELINED),
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
      .usb_hs_enabled_o(hs_enabled_w),
      .usb_idle_o(device_usb_idle_w),
      .usb_sof_o(usb_sof_w),
      .crc_err_o(crc_error_w),
      .timeout_o(timeout_w),

      // USB bulk endpoint data-paths
      .blk_in_ready_i(bulk_in_ready_q),
      .blk_out_ready_i(bulk_out_ready_q),
      .blk_start_o(),
      .blk_cycle_o(blk_cycle_w),
      .blk_endpt_o(),
      .blk_error_i(1'b0),

      .s_axis_tvalid_i(bmvalid_w),
      .s_axis_tready_o(m_tready),
      .s_axis_tlast_i (m_tlast),
      .s_axis_tkeep_i (m_tkeep),
      .s_axis_tdata_i (m_tdata),

      .m_axis_tvalid_o(s_tvalid),
      .m_axis_tready_i(bsready_w),
      .m_axis_tlast_o (s_tlast),
      .m_axis_tkeep_o (s_tkeep),
      .m_axis_tdata_o (s_tdata)
  );


  // -- USB ULPI Bulk transfer endpoint (IN & OUT) -- //

  // Loop-back FIFO for Testing //
  generate
    if (USE_SYNC_FIFO) begin : g_sync_fifo

      sync_fifo #(
          .WIDTH (10),
          .ABITS (FIFO_LEVEL_BITS),
          .OUTREG(3)
      ) U_BULK_FIFO0 (
          .clock(usb_clock),
          .reset(usb_reset),

          .level_o(level_w),

          .valid_i(bsvalid_w),
          .ready_o(s_tready),
          .data_i ({s_tkeep, s_tlast, s_tdata}),

          .valid_o(m_tvalid),
          .ready_i(bmready_w),
          .data_o ({m_tkeep, m_tlast, m_tdata})
      );

    end else begin : g_axis_fifo

      axis_fifo #(
          .DEPTH(BULK_FIFO_SIZE),
          .DATA_WIDTH(8),
          .KEEP_ENABLE(1),
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

          .s_axis_tdata (s_tdata),  // AXI4-Stream input
          .s_axis_tkeep (s_tkeep),
          .s_axis_tvalid(bsvalid_w),
          .s_axis_tready(s_tready),
          .s_axis_tlast (s_tlast),
          .s_axis_tid   (1'b0),
          .s_axis_tdest (1'b0),
          .s_axis_tuser (1'b0),

          .pause_req(1'b0),

          .m_axis_tdata(m_tdata),  // AXI4-Stream output
          .m_axis_tkeep(m_tkeep),
          .m_axis_tvalid(m_tvalid),
          .m_axis_tready(bmready_w),
          .m_axis_tlast(m_tlast),
          .m_axis_tid(),
          .m_axis_tdest(),
          .m_axis_tuser(),

          .status_depth(level_w),  // Status
          .status_overflow(),
          .status_bad_frame(),
          .status_good_frame()
      );

    end
  endgenerate


  //
  //  Status via UART
  ///
  reg tstart, tready, send_q;
  wire rx_busy_w, tx_busy_w, rx_orun_w, rx_ferr_w;
  wire xvalid, xready, uvalid, uready;
  wire terror, tcycle, tvalid, tlast, tkeep;
  wire [7:0] xdata, tdata, udata;
  wire [9:0] tlevel;


  // -- Telemetry Read-Back Logic -- //

  assign uready = 1'b1;

  always @(posedge clock) begin
    send_q <= ~send_n & ~tcycle & ~tx_busy_w;

    if (!tcycle && (send_q || uvalid && udata == "a")) begin
      tstart <= 1'b1;
    end else begin
      tstart <= 1'b0;
    end
  end


  // -- Telemetry Logger -- //

  assign phy_state_w = U_ULPI_USB0.phy_state_w;
  assign err_code_w = U_ULPI_USB0.err_code_w;
  assign usb_state_w = U_ULPI_USB0.usb_state_w;
  assign ctl_state_w = U_ULPI_USB0.ctl_state_w;
  assign blk_state_w = U_ULPI_USB0.blk_state_w;
  // assign usb_state_w = U_ULPI_USB0.U_TRANSACT1.state;
  // assign ctl_state_w = U_ULPI_USB0.U_TRANSACT1.xctrl;
  // assign blk_state_w = U_ULPI_USB0.U_TRANSACT1.xbulk;
  assign usb_tuser_w = U_ULPI_USB0.ulpi_rx_tuser_w;
  assign tok_endpt_w = U_ULPI_USB0.tok_endp_w;
  assign LineState = U_ULPI_USB0.LineState;

  assign ctl_cycle_w = U_ULPI_USB0.ctl0_cycle_w;
  assign ctl_error_w = U_ULPI_USB0.ctl0_error_w;
  assign usb_rx_recv_w = U_ULPI_USB0.usb_rx_recv_w;
  assign usb_tx_done_w = U_ULPI_USB0.usb_tx_done_w;
  assign tok_rx_recv_w = U_ULPI_USB0.tok_rx_recv_w;


  // Capture telemetry, so that it can be read back from EP1
  bulk_telemetry #(
      .ENDPOINT(4'd2),
      .PACKET_SIZE(8)  // Note: 8x 32b words per USB (BULK IN) packet
  ) U_TELEMETRY1 (
      .clock(clock),
      .reset(reset),
      .usb_enum_i(1'b1),
      .high_speed_i(hs_enabled_w),

      .LineState(LineState), // Byte 3
      .ctl_cycle_i(ctl_cycle_w),
      .usb_reset_i(usb_reset),
      .usb_endpt_i(tok_endpt_w),

      .usb_tuser_i(usb_tuser_w), // Byte 2
      .ctl_error_i(ctl_error_w),
      .usb_state_i(usb_state_w),
      .crc_error_i(crc_error_w),

      .usb_error_i(err_code_w), // Byte 1
      .usb_recv_i(usb_rx_recv_w),
      .usb_sent_i(usb_tx_done_w),
      .tok_recv_i(tok_rx_recv_w),
      .timeout_i(timeout_w),
      .usb_sof_i(usb_sof_w),
      .blk_state_i(blk_state_w),

      .ctl_state_i(ctl_state_w), // Byte 0
      .phy_state_i(phy_state_w),

      .start_i (tstart || 1'b1),
      .select_i(1'b1),
      .endpt_i (4'd2),
      .error_o (terror),
      .level_o (tlevel),

      .m_tvalid(tvalid),  // AXI4-Stream for telemetry data
      .m_tlast (tlast),
      .m_tkeep (tkeep),
      .m_tdata (tdata),
      .m_tready(tready)
  );

  // Convert 32b telemetry captures to ASCII hexadecimal //
  hex_dump #(
      .UNICODE(0),
      .BLOCK_SRAM(1)
  ) U_HEXDUMP1 (
      .clock(clock),
      .reset(reset),

      .start_dump_i(tstart),
      .is_dumping_o(tcycle),
      .fifo_level_o(),

      .s_tvalid(tvalid),
      .s_tready(tready),
      .s_tlast (tlast),
      .s_tkeep (tkeep),
      .s_tdata (tdata),

      .m_tvalid(xvalid),
      .m_tready(xready),
      .m_tlast (),
      .m_tkeep (),
      .m_tdata (xdata)
  );

  // Use the FTDI USB UART for dumping the telemetry (as ASCII hex) //
  uart #(
      .DATA_WIDTH(8)
  ) U_UART1 (
      .clk(clock),
      .rst(reset),

      .s_axis_tvalid(xvalid && !tx_busy_w),
      .s_axis_tready(xready),
      .s_axis_tdata (xdata),

      .m_axis_tvalid(uvalid),
      .m_axis_tready(uready),
      .m_axis_tdata (udata),

      .rxd(uart_rx),
      .txd(uart_tx),

      .rx_busy(rx_busy_w),
      .tx_busy(tx_busy_w),
      .rx_overrun_error(rx_orun_w),
      .rx_frame_error(rx_ferr_w),

      .prescale(UART_PRESCALE)
  );


endmodule  // usb_demo_top
