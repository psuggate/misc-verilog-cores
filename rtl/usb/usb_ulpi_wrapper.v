`timescale 1ns / 100ps
module usb_ulpi_wrapper #(
    parameter [15:0] VENDOR_ID = 16'hF4CE,
    parameter integer VENDOR_LENGTH = 19,
    localparam integer VSB = VENDOR_LENGTH * 8 - 1,
    parameter [VSB:0] VENDOR_STRING = "University of Otago",

    parameter [15:0] PRODUCT_ID = 16'h0003,
    parameter integer PRODUCT_LENGTH = 8,
    localparam integer PSB = PRODUCT_LENGTH * 8 - 1,
    parameter [PSB:0] PRODUCT_STRING = "TART USB",

    parameter integer SERIAL_LENGTH = 8,
    localparam integer SSB = SERIAL_LENGTH * 8 - 1,
    parameter [SSB:0] SERIAL_STRING = "TART0001",

    parameter USE_SYNC_FIFO = 0,
    parameter integer DEBUG = 1
) (
    input clk_26,
    input rst_n,

    // Debug UART signals
    input  send_ni,
    input  uart_rx_i,
    output uart_tx_o,

    output configured_o,
    output crc_error_o,
    output [3:0] status_o,

    // USB ULPI pins on the dev-board
    input ulpi_clk,
    output ulpi_rst,
    input ulpi_dir,
    input ulpi_nxt,
    output ulpi_stp,
    inout [7:0] ulpi_data,

    // Same clock-domain as the AXI4-Stream ports
    output usb_clk_o,
    output usb_rst_o,

    // USB BULK endpoint #1 //
    input ep1_in_ready_i,
    input ep1_out_ready_i,

    output m1_tvalid,
    input m1_tready,
    output m1_tlast,
    output m1_tkeep,
    output [7:0] m1_tdata,

    input s1_tvalid,
    output s1_tready,
    input s1_tlast,
    input s1_tkeep,
    input [7:0] s1_tdata,

    // USB BULK endpoint #2 //
    input ep2_in_ready_i,
    input ep2_out_ready_i,

    output m2_tvalid,
    input m2_tready,
    output m2_tlast,
    output m2_tkeep,
    output [7:0] m2_tdata,

    input s2_tvalid,
    output s2_tready,
    input s2_tlast,
    input s2_tkeep,
    input [7:0] s2_tdata
);


  // -- Constants -- //

  // USB-core configuration
  localparam integer PIPELINED = 1;
  localparam integer ENDPOINT1 = 1;
  localparam integer ENDPOINT2 = 2;

  // USB BULK IN/OUT SRAM parameters
  localparam integer FIFO_LEVEL_BITS = USE_SYNC_FIFO ? 11 : 12;
  localparam integer FSB = FIFO_LEVEL_BITS - 1;
  localparam integer BULK_FIFO_SIZE = 2048;

  // USB UART settings
  localparam [15:0] UART_PRESCALE = 16'd33;  // For: 60.0 MHz / (230400 * 8)
  // localparam [15:0] UART_PRESCALE = 16'd65;  // For: 60.0 MHz / (115200 * 8)
  // localparam [15:0] UART_PRESCALE = 16'd781;  // For: 60.0 MHz / (9600 * 8)


  // -- Signals -- //

  // Global signals //
  wire clock, reset, usb_clock, usb_reset, locked;

  // Local Signals //
  wire device_usb_idle_w, crc_error_w, hs_enabled_w;
  wire usb_sof_w, configured, blk_cycle_w, has_telemetry_w, timeout_w;
  wire blk_fetch_w, blk_store_w;
  wire [3:0] blk_endpt_w;

  // Data-path //
  reg bulk_in_ready_q, bulk_out_ready_q;
  wire s_tvalid, s_tready, s_tlast, s_tkeep;
  wire m_tvalid, m_tready, m_tlast, m_tkeep;
  wire [7:0] s_tdata, m_tdata;

  // Telemetry signals //
  wire ctl_cycle_w, ctl_error_w, usb_rx_recv_w, usb_tx_done_w, tok_rx_recv_w;
  wire hsk_tx_done_w, tok_parity_w;
  wire [3:0] phy_state_w, usb_state_w, ctl_state_w, usb_tuser_w, tok_endpt_w;
  wire [2:0] err_code_w;
  wire [7:0] blk_state_w;
  wire [1:0] LineState;

  assign configured_o = configured;
  assign crc_error_o = crc_error_w;
  assign status_o = phy_state_w;

  assign usb_clk_o = usb_clock;
  assign usb_rst_o = usb_reset;


  // -- System Clocks & Resets -- //

  ulpi_reset #(
      .PHASE("0000"),  // Note: timing-constraints used instead
      .PLLEN(0)
  ) U_RESET0 (
      .areset_n (rst_n),
      .ulpi_clk (ulpi_clk),
      .sys_clock(clk_26),

      .ulpi_rst_n(ulpi_rst),  // Active LO
      .pll_locked(locked),

      .usb_clock(clock),  // 60 MHz, PLL output, phase-shifted
      .usb_reset(reset),  // Active HI
      .ddr_clock()  // 120 MHz, PLL output, phase-shifted
  );


  //
  //  Demultiplexor for the Two USB Endpoints
  ///
  axis_demux #(
      .M_COUNT(2),
      .DATA_WIDTH(8),
      .KEEP_ENABLE(1),
      .KEEP_WIDTH(1),
      .ID_ENABLE(0),
      .ID_WIDTH(1),
      .DEST_ENABLE(0),
      .M_DEST_WIDTH(1),
      .USER_ENABLE(0),
      .USER_WIDTH(1),
      .TDEST_ROUTE(0)
  ) U_AXIS_DEMUX1 (
      .clk(usb_clock),
      .rst(usb_reset),

      .enable(blk_store_w),
      .drop  (1'b0),
      .select(blk_endpt_w == ENDPOINT2),

      // Connects to the 'M' port of the USB ULPI core
      .s_axis_tvalid(m_tvalid),
      .s_axis_tready(m_tready),
      .s_axis_tlast(m_tlast),
      .s_axis_tkeep(m_tkeep),
      .s_axis_tid(1'd0),
      .s_axis_tdest(2'd0),
      .s_axis_tuser(1'b0),
      .s_axis_tdata(m_tdata),

      .m_axis_tvalid({m2_tvalid, m1_tvalid}),
      .m_axis_tready({m2_tready, m1_tready}),
      .m_axis_tkeep ({m2_tkeep, m1_tkeep}),
      .m_axis_tlast ({m2_tlast, m1_tlast}),
      .m_axis_tdata ({m2_tdata, m1_tdata})
  );


  //
  //  Multiplexor for the Two USB Endpoints
  ///
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
  ) U_AXIS_MUX1 (
      .clk(usb_clock),
      .rst(usb_reset),

      .enable(blk_fetch_w),
      .select(blk_endpt_w == ENDPOINT2),

      // Connects to the 'S' port of the USB ULPI core
      .m_axis_tvalid(s_tvalid),
      .m_axis_tready(s_tready),
      .m_axis_tlast (s_tlast),
      .m_axis_tkeep (s_tkeep),
      .m_axis_tdata (s_tdata),

      .s_axis_tvalid({s2_tvalid, s1_tvalid}),
      .s_axis_tready({s2_tready, s1_tready}),
      .s_axis_tlast({s2_tlast, s1_tlast}),
      .s_axis_tkeep({s2_tkeep, s1_tkeep}),
      .s_axis_tid(2'd0),
      .s_axis_tdest(2'd0),
      .s_axis_tuser(2'b0),
      .s_axis_tdata({s2_tdata, s1_tdata})
  );


  // -- USB ULPI Bulk transfer endpoint (IN & OUT) -- //

  always @(posedge clock) begin
    if (blk_endpt_w == ENDPOINT2) begin
      bulk_in_ready_q  <= ep2_in_ready_i;
      bulk_out_ready_q <= ep2_out_ready_i;
    end else begin
      bulk_in_ready_q  <= ep1_in_ready_i;
      bulk_out_ready_q <= ep1_out_ready_i;
    end
  end


  // Sanitise the data-stream from the USB packet-decoder.
  wire x_tvalid, x_tready, x_tlast, x_tkeep;
  wire [7:0] x_tdata;

  axis_clean #(
      .WIDTH(8),
      .DEPTH(16)
  ) U_AXIS_CLEAN2 (
      .clock(usb_clock),
      .reset(usb_reset),

      .s_tvalid(x_tvalid),
      .s_tready(x_tready),
      .s_tlast (x_tlast),
      .s_tkeep (x_tkeep),
      .s_tdata (x_tdata),

      .m_tvalid(m_tvalid),
      .m_tready(m_tready),
      .m_tlast (m_tlast),
      .m_tkeep (m_tkeep),
      .m_tdata (m_tdata)
  );


  //
  //  USB ULPI Core Top-Level Module
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
      .ENDPOINT1(ENDPOINT1),
      .EP2_CONTROL(0),
      .ENDPOINT2(ENDPOINT2)
  ) U_ULPI_USB1 (
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
      .blk_fetch_o(blk_fetch_w),
      .blk_store_o(blk_store_w),
      .blk_endpt_o(blk_endpt_w),
      .blk_error_i(1'b0),

      .s_axis_tvalid_i(s_tvalid),
      .s_axis_tready_o(s_tready),
      .s_axis_tlast_i (s_tlast),
      .s_axis_tkeep_i (s_tkeep),
      .s_axis_tdata_i (s_tdata),

      .m_axis_tvalid_o(x_tvalid),
      .m_axis_tready_i(x_tready),
      .m_axis_tlast_o (x_tlast),
      .m_axis_tkeep_o (x_tkeep),
      .m_axis_tdata_o (x_tdata)
  );


  // -- Telemetry Logger -- //

  reg tstart, send_q;
  wire rx_busy_w, tx_busy_w;
  wire xvalid, xready, uvalid, uready;
  wire terror, tcycle, tvalid, tready, tlast, tkeep;
  wire [7:0] xdata, tdata, udata;
  wire [9:0] tlevel;

  wire gvalid, gready, glast, xlast;
  wire [7:0] gdata;

  assign phy_state_w = U_ULPI_USB1.phy_state_w;
  assign err_code_w = U_ULPI_USB1.err_code_w;
  assign usb_state_w = U_ULPI_USB1.usb_state_w;
  assign ctl_state_w = U_ULPI_USB1.ctl_state_w;
  assign blk_state_w = U_ULPI_USB1.blk_state_w;
  assign usb_tuser_w = U_ULPI_USB1.ulpi_rx_tuser_w;
  assign tok_endpt_w = U_ULPI_USB1.tok_endp_w;
  assign LineState = U_ULPI_USB1.LineState;

  assign ctl_cycle_w = U_ULPI_USB1.ctl0_cycle_w;
  assign ctl_error_w = U_ULPI_USB1.ctl0_error_w;
  assign usb_rx_recv_w = U_ULPI_USB1.usb_rx_recv_w;
  assign usb_tx_done_w = U_ULPI_USB1.usb_tx_done_w;
  assign hsk_tx_done_w = U_ULPI_USB1.hsk_tx_done_w;
  assign tok_rx_recv_w = U_ULPI_USB1.tok_rx_recv_w;
  assign tok_parity_w = U_ULPI_USB1.parity1_w;

  assign uready = 1'b1;

  generate
    if (DEBUG) begin : g_debug

      // Capture telemetry, so that it can be read back from EP1
      bulk_telemetry #(
          .ENDPOINT(ENDPOINT2),
          .FIFO_DEPTH(1024),
          .PACKET_SIZE(8)  // Note: 8x 32b words per USB (BULK IN) packet
      ) U_TELEMETRY1 (
          .clock(clock),
          .reset(reset),

          .usb_enum_i  (1'b1),
          .high_speed_i(hs_enabled_w),

          .LineState  (LineState),    // Byte 3
          .ctl_cycle_i(ctl_cycle_w),
          .usb_reset_i(usb_reset),
          .usb_endpt_i(tok_endpt_w),

          .usb_tuser_i(usb_tuser_w),  // Byte 2
          .ctl_error_i(ctl_error_w),
          .usb_state_i(usb_state_w),
          .crc_error_i(crc_error_w),

          .usb_error_i(err_code_w),  // Byte 1
          .usb_recv_i(usb_rx_recv_w),
          .usb_sent_i(usb_tx_done_w),
          .hsk_sent_i(hsk_tx_done_w),
          .tok_recv_i(tok_rx_recv_w),
          .tok_ping_i(tok_parity_w),  // todo ...
          .timeout_i(timeout_w),
          .usb_sof_i(usb_sof_w),
          .blk_state_i(blk_state_w),

          .ctl_state_i(ctl_state_w),  // Byte 0
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


      // -- Telemetry Read-Back Logic -- //

      always @(posedge clock) begin
        send_q <= ~send_ni & ~tcycle & ~tx_busy_w;

        if (!tcycle && (send_q || uvalid && udata == "a")) begin
          tstart <= 1'b1;
        end else begin
          tstart <= 1'b0;
        end
      end

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
          .m_tlast (xlast),
          .m_tkeep (),
          .m_tdata (xdata)
      );

      assign gvalid = xvalid && !tx_busy_w;
      assign xready = gready;
      assign glast  = xlast;
      assign gdata  = xdata;


      //
      //  Status via UART
      ///
      // Use the FTDI USB UART for dumping the telemetry (as ASCII hex) //
      uart #(
          .DATA_WIDTH(8)
      ) U_UART1 (
          .clk(clock),
          .rst(reset),

          .s_axis_tvalid(gvalid),
          .s_axis_tready(gready),
          .s_axis_tdata (gdata),

          .m_axis_tvalid(uvalid),
          .m_axis_tready(uready),
          .m_axis_tdata (udata),

          .rxd(uart_rx_i),
          .txd(uart_tx_o),

          .rx_busy(rx_busy_w),
          .tx_busy(tx_busy_w),
          .rx_overrun_error(),
          .rx_frame_error(),

          .prescale(UART_PRESCALE)
      );

    end
  endgenerate


endmodule  // usb_ulpi_wrapper
