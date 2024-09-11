`timescale 1ns / 100ps
module usb_ulpi_core #(
    parameter integer PACKET_FIFO_DEPTH = 2048,
    parameter integer MAX_PACKET_LENGTH = 512,
    parameter integer MAX_CONFIG_LENGTH = 64,

    parameter [3:0] ENDPOINT1 = 4'd1,
    parameter [3:0] ENDPOINT2 = 4'd2,
    parameter USE_EP4_OUT = 0,
    parameter [3:0] ENDPOINT4 = 4'd4,

    // Debug-mode end-point, for reading telemetry
    parameter DEBUG = 0,
    parameter LOGGER = 0,
    parameter USE_UART = 1,
    localparam USE_EP3_IN = LOGGER && USE_UART || USE_EP4_OUT ? 1 : 0,
    parameter [3:0] ENDPOINTD = 4'd3,

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
    parameter [SSB:0] SERIAL_STRING = "TART0001"
) (
    input clk_26,
    input arst_n,

    // Debug UART signals
    input  send_ni,
    input  uart_rx_i,
    output uart_tx_o,

    output configured_o,
    output conf_event_o,
    output [2:0] conf_value_o,
    output crc_error_o,

    // USB ULPI pins on the dev-board
    input ulpi_clk,
    output ulpi_rst,
    input ulpi_dir,
    input ulpi_nxt,
    output ulpi_stp,
    inout [7:0] ulpi_data,

    // Same clock-domain as the AXI4-Stream ports
    output usb_clock_o,
    output usb_reset_o,

    input blki_tvalid_i,
    output blki_tready_o,
    input blki_tlast_i,
    input [7:0] blki_tdata_i,

    input blkx_tvalid_i,  // Optional Bulk IN endpoint
    output blkx_tready_o,
    input blkx_tlast_i,
    input [7:0] blkx_tdata_i,

    output blko_tvalid_o,
    input blko_tready_i,
    output blko_tlast_o,
    output [7:0] blko_tdata_o,

    output blky_tvalid_o,
    input blky_tready_i,
    output blky_tlast_o,
    output [7:0] blky_tdata_o
);

  wire usb_clk, usb_rst;
  wire locked, clock, reset;
  wire configured, high_speed, conf_event;
  wire [2:0] conf_value;

  wire x_tvalid, x_tready, x_tlast, y_tvalid, y_tready, y_tlast;
  wire [7:0] x_tdata, y_tdata;

  assign usb_clock_o  = usb_clk;
  assign usb_reset_o  = usb_rst;

  assign configured_o = configured;

  // -- System Clocks & Resets -- //

  ulpi_reset #(
      .PHASE("0000"),  // Note: timing-constraints used instead
      .PLLEN(0)
  ) U_RESET1 (
      .areset_n (arst_n),
      .ulpi_clk (ulpi_clk),
      .sys_clock(clk_26),

      .ulpi_rst_n(ulpi_rst),  // Active LO
      .pll_locked(locked),

      .usb_clock(clock),  // 60 MHz, PLL output, phase-shifted
      .usb_reset(reset),  // Active HI
      .ddr_clock()        // 120 MHz, PLL output, phase-shifted
  );

  usb_ulpi_top #(
      .DEBUG(DEBUG),

      .VENDOR_ID(VENDOR_ID),
      .VENDOR_LENGTH(VENDOR_LENGTH),
      .VENDOR_STRING(VENDOR_STRING),
      .PRODUCT_ID(PRODUCT_ID),
      .PRODUCT_LENGTH(PRODUCT_LENGTH),
      .PRODUCT_STRING(PRODUCT_STRING),
      .SERIAL_LENGTH(SERIAL_LENGTH),
      .SERIAL_STRING(SERIAL_STRING),

      .MAX_PACKET_LENGTH(MAX_PACKET_LENGTH),  // For HS-mode
      .PACKET_FIFO_DEPTH(PACKET_FIFO_DEPTH),
      .ENDPOINT1(ENDPOINT1),
      .ENDPOINT2(ENDPOINT2),
      .ENDPOINT3(ENDPOINTD),
      .ENDPOINT4(ENDPOINT4),
      .USE_EP2_IN(1),
      .USE_EP3_IN(USE_EP3_IN),
      .USE_EP1_OUT(1),
      .USE_EP4_OUT(USE_EP4_OUT)
  ) U_USB1 (
      .areset_n(~reset),
      // .areset_n(arst_n),

      .ulpi_clock_i(clock),
      .ulpi_dir_i  (ulpi_dir),
      .ulpi_nxt_i  (ulpi_nxt),
      .ulpi_stp_o  (ulpi_stp),
      .ulpi_data_io(ulpi_data),

      .usb_clock_o(usb_clk),
      .usb_reset_o(usb_rst),

      .configured_o(configured),
      .high_speed_o(high_speed),
      .conf_event_o(conf_event_o),
      .conf_value_o(conf_value_o),

      .blki_tvalid_i(blki_tvalid_i),  // USB 'BULK IN' EP data-path
      .blki_tready_o(blki_tready_o),
      .blki_tlast_i (blki_tlast_i),
      .blki_tdata_i (blki_tdata_i),

      .blkx_tvalid_i(y_tvalid),  // USB 'BULK IN' EP data-path
      .blkx_tready_o(y_tready),
      .blkx_tlast_i (y_tlast),
      .blkx_tdata_i (y_tdata),

      .blko_tvalid_o(blko_tvalid_o),  // USB 'BULK OUT' EP data-path
      .blko_tready_i(blko_tready_i),
      .blko_tlast_o (blko_tlast_o),
      .blko_tdata_o (blko_tdata_o),

      .blky_tvalid_o(blky_tvalid_o),  // USB 'BULK OUT' EP data-path
      .blky_tready_i(blky_tready_i),
      .blky_tlast_o (blky_tlast_o),
      .blky_tdata_o (blky_tdata_o)
  );

  assign crc_error_o = U_USB1.crc_error_w;

  // -- Route USB End-Point #3 -- //

  generate
    if (LOGGER == 0 || USE_UART == 1) begin : g_route_ep3

      assign y_tvalid = blkx_tvalid_i;
      assign blkx_tready_o = y_tready;
      assign y_tlast = blkx_tlast_i;
      assign y_tdata = blkx_tdata_i;

    end else begin : g_debug_ep

      assign blkx_tready_o = 1'b0;

      assign y_tvalid = x_tvalid;
      assign x_tready = y_tready;
      assign y_tlast = x_tlast;
      assign y_tdata = x_tdata;

    end
  endgenerate  /* g_debug_ep */

  // -- Telemetry Logging -- //

  localparam LOG_WIDTH = 32;
  localparam SIG_WIDTH = 20;
  // localparam SIG_WIDTH = 3;
  localparam XSB = SIG_WIDTH - 1;
  localparam ISB = LOG_WIDTH - SIG_WIDTH - 1;

  generate
    if (LOGGER) begin : g_debug

      reg en_q;
      wire [10:0] sof_w;
      wire [XSB:0] sig_w;
      wire [ISB:0] ign_w;
      wire [3:0] ep1_w, ep2_w, ep3_w, pid_w;
      wire [2:0] st_w;
      wire re_w;

      assign st_w  = U_USB1.stout_w;
      assign re_w  = U_USB1.RxEvent == 2'b01;

      assign ep1_w = {U_USB1.ep1_err_w, U_USB1.ep1_sel_w, U_USB1.ep1_par_w, U_USB1.ep1_rdy_w};
      assign ep2_w = {U_USB1.ep2_err_w, U_USB1.ep2_sel_w, U_USB1.ep2_par_w, U_USB1.ep2_rdy_w};
      assign ep3_w = {U_USB1.ep3_err_w, U_USB1.ep3_sel_w, U_USB1.ep3_par_w, U_USB1.ep3_rdy_w};
      assign pid_w = U_USB1.U_PROTO1.pid_q;
      assign sof_w = U_USB1.sof_count_w;

      assign sig_w = {ep3_w, ep2_w, ep1_w, pid_w, re_w, st_w};  // 20b
      assign ign_w = {crc_error_o, sof_w};  // 12b
      // assign sig_w = st_w;  // 3b
      // assign ign_w = {crc_error_o, sof_w, ep3_w, ep2_w, ep1_w, pid_w, re_w};  // 29b

      always @(posedge usb_clk) begin
        if (usb_rst) begin
          en_q <= 1'b0;
        end else if (!en_q && configured) begin
          en_q <= 1'b1;
        end
      end

      // Capture telemetry, so that it can be read back from EP1
      axis_logger #(
          .SRAM_BYTES(2048),
          // .SRAM_BYTES(4096),
          .FIFO_WIDTH(LOG_WIDTH),
          .SIG_WIDTH(SIG_WIDTH),
          .PACKET_SIZE(8)  // Note: 8x 32b words per USB (BULK IN) packet
      ) U_LOG1 (
          .clock(usb_clk),
          .reset(usb_rst),

          .enable_i(configured),
          // .enable_i(en_q),
          .change_i(sig_w),
          .ignore_i(ign_w),
          .level_o (),

          .m_tvalid(x_tvalid),  // AXI4-Stream for telemetry data
          .m_tready(x_tready),
          .m_tkeep (),
          .m_tlast (x_tlast),
          .m_tdata (x_tdata)
      );

    end
  endgenerate  /* !g_debug */

  // -- Telemetry Read-Back Logic -- //

  localparam [15:0] UART_PRESCALE = 16'd33;  // For: 60.0 MHz / (230400 * 8)

  generate
    if (LOGGER && USE_UART) begin : g_use_uart

      reg tstart, send_q;
      wire tcycle_w, tx_busy_w, rx_busy_w;
      wire u_tvalid, u_tready, r_tvalid, r_tready;
      wire [7:0] u_tdata, r_tdata;

      assign r_tready = 1'b1;

      always @(posedge clock) begin
        send_q <= ~send_ni & ~tcycle_w & ~tx_busy_w;

        if (!tcycle_w && (send_q || r_tvalid && r_tdata == "a")) begin
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
          .clock(usb_clk),
          .reset(usb_rst),

          .start_dump_i(tstart),
          .is_dumping_o(tcycle_w),
          .fifo_level_o(),

          .s_tvalid(x_tvalid),
          .s_tready(x_tready),
          .s_tlast (x_tlast),
          .s_tkeep (1'b1),
          .s_tdata (x_tdata),

          .m_tvalid(u_tvalid),
          .m_tready(u_tready),
          .m_tlast (),
          .m_tkeep (),
          .m_tdata (u_tdata)
      );

      // Use the FTDI USB UART for dumping the telemetry (as ASCII hex) //
      uart #(
          .DATA_WIDTH(8)
      ) U_UART1 (
          .clk(usb_clk),
          .rst(usb_rst),

          .s_axis_tvalid(u_tvalid && !tx_busy_w),
          .s_axis_tready(u_tready),
          .s_axis_tdata (u_tdata),

          .m_axis_tvalid(r_tvalid),
          .m_axis_tready(r_tready),
          .m_axis_tdata (r_tdata),

          .rxd(uart_rx_i),
          .txd(uart_tx_o),

          .rx_busy(rx_busy_w),
          .tx_busy(tx_busy_w),
          .rx_overrun_error(),
          .rx_frame_error(),

          .prescale(UART_PRESCALE)
      );

    end else begin

      assign uart_tx_o = 1'b1;

    end
  endgenerate  /* g_use_uart */

endmodule  /* usb_ulpi_core */
