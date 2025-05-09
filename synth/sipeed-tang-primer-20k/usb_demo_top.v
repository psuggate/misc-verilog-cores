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

  localparam DEBUG = 1;

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
  localparam integer PIPELINED = 1;
  localparam integer HIGH_SPEED = 1;  // Note: USB FS (Full-Speed) not supported
  localparam integer ULPI_DDR_MODE = 0;  // todo: '1' is fiddly to implement ...
  localparam ENDPOINT1 = 4'd1;
  localparam ENDPOINT2 = 4'd2;
  localparam ENDPOINT3 = 4'd3;
  localparam ENDPOINT4 = 4'd4;

  localparam integer MAX_PACKET_LENGTH = 512;
  localparam integer MAX_CONFIG_LENGTH = 64;

  localparam BULK_FIFO_SIZE = 2048;
  localparam FBITS = $clog2(BULK_FIFO_SIZE);
  localparam FSB = FBITS - 1;

  // USB UART settings
  localparam [15:0] UART_PRESCALE = 16'd33;  // For: 60.0 MHz / (230400 * 8)

  // -- Signals -- //

  // Global signals //
  wire clock, reset;
  wire [3:0] cbits;

  // Local Signals //
  wire configured;

  // Data-path //
  wire s_tvalid, s_tready, s_tlast, s_tkeep;
  wire x_tvalid, x_tready, x_tlast, x_tkeep;
  wire y_tvalid, y_tready, y_tlast;
  wire m_tvalid, m_tready, m_tlast, m_tkeep;
  wire [7:0] s_tdata, x_tdata, y_tdata, m_tdata;

  // -- Some Wiring Stuffs -- //

  assign leds = {~cbits[3:0], 2'b11};
  assign s_tkeep = s_tvalid;

  wire crc_error_w, conf_event, ep1_rdy, ep2_rdy, ep3_rdy;
  wire [2:0] usb_config, stout_w;

  // assign cbits = {conf_event, usb_config};
  assign cbits = {ep3_rdy, ep2_rdy, ep1_rdy, configured};

  assign x_tvalid = 1'b0;
  assign x_tkeep = 1'b0;
  assign x_tlast = 1'b0;
  assign x_tdata = 8'hA7;

  localparam LOOPBACK = 1;

  usb_ulpi_core #(
      .VENDOR_ID(VENDOR_ID),
      .VENDOR_LENGTH(VENDOR_LENGTH),
      .VENDOR_STRING(VENDOR_STRING),
      .PRODUCT_ID(PRODUCT_ID),
      .PRODUCT_LENGTH(PRODUCT_LENGTH),
      .PRODUCT_STRING(PRODUCT_STRING),
      .SERIAL_LENGTH(SERIAL_LENGTH),
      .SERIAL_STRING(SERIAL_STRING),
      .DEBUG(DEBUG),
      .USE_UART(0),
      .ENDPOINT1(ENDPOINT1),
      .ENDPOINT2(ENDPOINT2),
      .ENDPOINTD(ENDPOINT3),
      .ENDPOINT4(ENDPOINT4),
      .USE_EP4_OUT(DEBUG)
  ) U_USB1 (
      .osc_in(clk_26),
      .arst_n(rst_n),

      .ulpi_clk (ulpi_clk),
      .ulpi_rst (ulpi_rst),
      .ulpi_dir (ulpi_dir),
      .ulpi_nxt (ulpi_nxt),
      .ulpi_stp (ulpi_stp),
      .ulpi_data(ulpi_data),

      // Todo: debug UART signals ...
      .send_ni  (send_n),
      .uart_rx_i(uart_rx),
      .uart_tx_o(uart_tx),

      .usb_clock_o(clock),
      .usb_reset_o(reset),

      .configured_o(configured),
      .conf_event_o(conf_event),
      .conf_value_o(usb_config),
      .crc_error_o (crc_error_w),

      .blki_tvalid_i(LOOPBACK ? m_tvalid : s_tvalid),  // USB 'BULK IN' EP data-path
      .blki_tready_o(s_tready),
      .blki_tlast_i (LOOPBACK ? m_tlast : s_tlast),
      .blki_tdata_i (LOOPBACK ? m_tdata : s_tdata),

      .blkx_tvalid_i(LOOPBACK ? y_tvalid : x_tvalid),  // Extra 'BULK IN' EP data-path
      .blkx_tready_o(x_tready),
      .blkx_tlast_i (LOOPBACK ? y_tlast : x_tlast),
      .blkx_tdata_i (LOOPBACK ? y_tdata : x_tdata),

      .blko_tvalid_o(m_tvalid),  // USB 'BULK OUT' EP data-path
      .blko_tready_i(LOOPBACK ? s_tready : m_tready),
      .blko_tlast_o(m_tlast),
      .blko_tdata_o(m_tdata),

      .blky_tvalid_o(y_tvalid),  // USB 'BULK OUT' EP data-path
      .blky_tready_i(LOOPBACK ? x_tready : 1'b0),
      .blky_tlast_o(y_tlast),
      .blky_tdata_o(y_tdata)
  );

  assign ep1_rdy = U_USB1.U_TOP1.ep1_rdy_w;
  assign ep2_rdy = U_USB1.U_TOP1.ep2_rdy_w;
  assign ep3_rdy = U_USB1.U_TOP1.ep3_rdy_w | crc_error_w;

  assign stout_w = U_USB1.U_TOP1.stout_w;


endmodule  /* usb_demo_top */
