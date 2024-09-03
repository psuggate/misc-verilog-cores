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
  wire m_tvalid, m_tready, m_tlast, m_tkeep;
  wire [7:0] s_tdata, x_tdata, m_tdata;

  // -- Some Wiring Stuffs -- //

  assign leds = {~cbits[3:0], 2'b11};
  assign s_tkeep = s_tvalid;

// `define __use_legacy_usb_core
`ifdef __use_legacy_usb_core

  // FIFO state //
  wire [FSB:0] level_w;
  reg bulk_in_ready_q, bulk_out_ready_q;

  always @(posedge clock) begin
    if (reset) begin
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

  usb_ulpi_wrapper #(
      .DEBUG(1)
  ) U_USB1 (
      .clk_26(clk_26),
      .rst_n (rst_n),

      // USB ULPI pins on the dev-board
      .ulpi_clk (ulpi_clk),
      .ulpi_rst (ulpi_rst),
      .ulpi_dir (ulpi_dir),
      .ulpi_nxt (ulpi_nxt),
      .ulpi_stp (ulpi_stp),
      .ulpi_data(ulpi_data),

      // Debug UART signals
      .send_ni  (send_n),
      .uart_rx_i(uart_rx),
      .uart_tx_o(uart_tx),

      .configured_o(configured),
      .status_o(cbits),

      // Same clock-domain as the AXI4-Stream ports
      .usb_clk_o(clock),
      .usb_rst_o(reset),

      // USB BULK endpoint #1 //
      .ep1_in_ready_i (bulk_in_ready_q),
      .ep1_out_ready_i(bulk_out_ready_q),

      .m1_tvalid(m_tvalid),
      .m1_tready(m_tready),
      .m1_tlast (m_tlast),
      .m1_tkeep (m_tkeep),
      .m1_tdata (m_tdata),

      .s1_tvalid(s_tvalid),
      .s1_tready(s_tready),
      .s1_tlast (s_tlast),
      .s1_tkeep (s_tkeep),
      .s1_tdata (s_tdata),

      // USB BULK endpoint #2 //
      .ep2_in_ready_i (1'b0),
      .ep2_out_ready_i(1'b0),

      .m2_tvalid(),
      .m2_tready(1'b0),
      .m2_tlast (),
      .m2_tkeep (),
      .m2_tdata (),

      .s2_tvalid(1'b0),
      .s2_tready(),
      .s2_tlast (1'b0),
      .s2_tkeep (1'b0),
      .s2_tdata (8'bx)
  );

  // -- Packet FIFO to Echo OUT -> IN -- //

  packet_fifo #(
      .WIDTH(8),
      .DEPTH(BULK_FIFO_SIZE),
      .STORE_LASTS(1),
      .SAVE_ON_LAST(1),
      .NEXT_ON_LAST(1),
      .USE_LENGTH(1),
      .MAX_LENGTH(MAX_PACKET_LENGTH),
      .OUTREG(2)
  ) U_FIFO1 (
      .clock(clock),
      .reset(reset),

      .level_o(level_w),
      .drop_i (1'b0),
      .save_i (1'b0),
      .redo_i (1'b0),
      .next_i (1'b0),

      .s_tvalid(m_tvalid),
      .s_tready(m_tready),
      .s_tkeep (m_tvalid),
      .s_tlast (m_tlast),
      .s_tdata (m_tdata),

      .m_tvalid(s_tvalid),
      .m_tready(s_tready),
      .m_tlast (s_tlast),
      .m_tdata (s_tdata)
  );

`else  /* !__use_legacy_usb_core */

  wire crc_error_w, conf_event, ep1_rdy, ep2_rdy, ep3_rdy;
  wire [2:0] usb_config;

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
      .ENDPOINT1(ENDPOINT1),
      .ENDPOINT2(ENDPOINT2),
      .DEBUG(DEBUG),
      .USE_UART(0),
      .ENDPOINTD(ENDPOINT3)
  ) U_USB1 (
      .clk_26(clk_26),
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

      .blkx_tvalid_i(x_tvalid),  // Extra 'BULK IN' EP data-path
      .blkx_tready_o(x_tready),
      .blkx_tlast_i (x_tlast),
      .blkx_tdata_i (x_tdata),

      .blko_tvalid_o(m_tvalid),  // USB 'BULK OUT' EP data-path
      .blko_tready_i(LOOPBACK ? s_tready : m_tready),
      .blko_tlast_o(m_tlast),
      .blko_tdata_o(m_tdata)
  );

  assign ep1_rdy = U_USB1.U_USB1.ep1_rdy_w;
  assign ep2_rdy = U_USB1.U_USB1.ep2_rdy_w;
  assign ep3_rdy = U_USB1.U_USB1.ep3_rdy_w | crc_error_w;

`endif  /* !__use_legacy_usb_core */


endmodule  /* usb_demo_top */
