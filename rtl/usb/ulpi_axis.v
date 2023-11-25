`timescale 1ns / 100ps
`define SERIAL_NUMBER "BULK0000"
`define SERIAL_LENGTH 8

`define VENDOR_STRING "University of Otago"
`define VENDOR_LENGTH 19

`define PRODUCT_STRING "TART USB"
`define PRODUCT_LENGTH 8

module ulpi_axis (  /*AUTOARG*/);

  parameter [`SERIAL_LENGTH*8-1:0] SERIAL_NUMBER = `SERIAL_NUMBER;
  parameter [7:0] SERIAL_LENGTH = `SERIAL_LENGTH;

  parameter [15:0] VENDOR_ID = 16'hF4CE;
  parameter [`VENDOR_LENGTH*8-1:0] VENDOR_STRING = `VENDOR_STRING;
  parameter [7:0] VENDOR_LENGTH = `VENDOR_LENGTH;

  parameter [15:0] PRODUCT_ID = 16'h0003;
  parameter [`PRODUCT_LENGTH*8-1:0] PRODUCT_STRING = `PRODUCT_STRING;
  parameter [7:0] PRODUCT_LENGTH = `PRODUCT_LENGTH;


  // Global, asynchronous reset
  input areset_n;

  // UTMI Low Pin Interface (ULPI)
  input ulpi_clock_i;
  output ulpi_reset_o;

  input ulpi_dir_i;
  input ulpi_nxt_i;
  output ulpi_stp_o;
  inout [7:0] ulpi_data_io;

  // USB clock-domain clock & reset
  output usb_clock_o;
  output usb_reset_o;  // USB core is in reset state

  // Status flags for IN/OUT FIFOs, and the USB core
  output fifo_in_full_o;
  output fifo_out_full_o;
  output fifo_out_overflow_o;
  output fifo_has_data_o;

  output usb_sof_o;
  output crc_err_o;
  output usb_vbus_valid_o;
  output usb_idle_o;  // USB core is idling
  output usb_suspend_o;  // USB core has been suspended
  output ulpi_rx_overflow_o;

  // AXI4-stream slave-port signals (IN: EP -> host)
  // Note: USB clock-domain
  input s_axis_tvalid_i;
  output s_axis_tready_o;
  input s_axis_tlast_i;
  input [7:0] s_axis_tdata_i;

  // AXI4-stream master-port signals (OUT: host -> EP)
  // Note: USB clock-domain
  output m_axis_tvalid_o;
  input m_axis_tready_i;
  output m_axis_tlast_o;
  output [7:0] m_axis_tdata_o;


  // -- Constants -- //

  localparam HIGH_SPEED = 1;


  // -- Signals and Assignments -- //

  wire clock, reset;
  reg rst_nq, rst_nr;

  assign usb_clock_o = clock;
  assign usb_reset_o = reset;

  assign clock = ~ulpi_clock_i;

  always @(posedge clock or negedge areset_n) begin
    if (!areset_n) begin
      {rst_nq, rst_nr} <= 2'b00;
    end else begin
      {rst_nq, rst_nr} <= {rst_nr, areset_n};
    end
  end

  // ULPI signals
  wire ulpi_dir_i, ulpi_nxt_i, ulpi_stp_o;
  wire [7:0] ulpi_data_iw, ulpi_data_ow;


  assign ulpi_data_io = usb_dir_i ? {8{1'bz}} : ulpi_data_ow;
  assign ulpi_data_iw = ulpi_data_io;


  // -- AXI4 stream to/from ULPI stream -- //

  wire ulpi_rx_tvalid, ulpi_rx_tready, ulpi_rx_tlast;
  wire [7:0] ulpi_rx_tdata;

  wire ulpi_tx_tvalid, ulpi_tx_tready, ulpi_tx_tlast;
  wire [7:0] ulpi_tx_tdata;

  usb_ulpi #(
      .HIGH_SPEED(HIGH_SPEED)
  ) usb_ulpi_inst (
      .rst_n(rst_nq),

      .ulpi_clk(clock),
      .usb_reset_o(reset),  // Sync reset for USB domain cores

      .ulpi_data_in(ulpi_data_iw),
      .ulpi_data_out(ulpi_data_ow),
      .ulpi_dir(ulpi_dir_i),
      .ulpi_nxt(ulpi_nxt_i),
      .ulpi_stp(ulpi_stp_o),
      .ulpi_reset(ulpi_reset_o),

      .axis_rx_tvalid_o(ulpi_rx_tvalid),
      .axis_rx_tready_i(ulpi_rx_tready),
      .axis_rx_tlast_o (ulpi_rx_tlast),
      .axis_rx_tdata_o (ulpi_rx_tdata),

      .axis_tx_tvalid_i(ulpi_tx_tvalid),
      .axis_tx_tready_o(ulpi_tx_tready),
      .axis_tx_tlast_i (ulpi_tx_tlast),
      .axis_tx_tdata_i (ulpi_tx_tdata),

      .ulpi_rx_overflow_o(ulpi_rx_overflow_o),
      .usb_vbus_valid_o(usb_vbus_valid_o),
      .usb_idle_o(usb_idle_o),
      .usb_suspend_o(usb_suspend_o)
  );


  // -- Encode/decode USB packets, over the AXI4 streams -- //

  wire hsk_send, hsk_sent;
  wire [1:0] hsk_type;

  wire in_tsend_w, in_tvalid_w, in_tready_w, in_tlast_w;
  wire [1:0] in_ttype_w;
  wire [7:0] in_tdata_w;

  encode_packet tx_usb_packet_inst (
      .reset(reset),
      .clock(clock),

      .tx_tvalid_o(ulpi_tx_tvalid),
      .tx_tready_i(ulpi_tx_tready),
      .tx_tlast_o (ulpi_tx_tlast),
      .tx_tdata_o (ulpi_tx_tdata),

      .hsk_send_i(hsk_send),
      .hsk_done_o(hsk_sent),
      .hsk_type_i(hsk_type),

      .tok_send_i(1'b0),  // Only used by USB hosts
      .tok_done_o(),
      .tok_type_i(2'bx),
      .tok_data_i(16'bx),

      .trn_tsend_i (in_tsend_w),
      .trn_ttype_i (in_ttype_w),
      .trn_tvalid_i(in_tvalid_w),
      .trn_tready_o(in_tready_w),
      .trn_tlast_i (in_tlast_w),
      .trn_tdata_i (in_tdata_w)
  );

  wire tok_rx_recv, hsk_rx_recv;
  wire [1:0] tok_rx_type, hsk_rx_type;
  wire [6:0] tok_rx_addr;
  wire [3:0] tok_rx_endp;

  wire out_tvalid_w, out_tready_w, out_tlast_w;
  wire [1:0] out_ttype_w;
  wire [7:0] out_tdata_w;

  decode_packet rx_usb_packet_inst (
      .reset(reset),
      .clock(clock),

      // USB configuration fields, and status flags
      .usb_sof_o(usb_sof_o),
      .crc_err_o(crc_err_o),

      // ULPI -> decoder stream
      .ulpi_tvalid_i(ulpi_rx_tvalid),
      .ulpi_tready_o(ulpi_rx_tready),
      .ulpi_tlast_i (ulpi_rx_tlast),
      .ulpi_tdata_i (ulpi_rx_tdata),

      // Indicates that a (OUT/IN/SETUP) token was received
      .tok_recv_o(tok_rx_recv),  // Start strobe
      .tok_type_o(tok_rx_type),  // Token-type (OUT/IN/SETUP)
      .tok_addr_o(tok_rx_addr),
      .tok_endp_o(tok_rx_endp),

      // Data packet (OUT, DATA0/1/2 MDATA) received
      .out_tvalid_o(out_tvalid_w),
      .out_tready_i(out_tready_w),
      .out_tlast_o (out_tlast_w),
      .out_ttype_o (out_ttype_w),
      .out_tdata_o (out_tdata_w),

      // Handshake packet information
      .hsk_recv_o(hsk_rx_recv),
      .hsk_type_o(hsk_rx_type)
  );


  // -- FSM for USB packets, handshakes, etc. -- //

  wire ctl0_tvalid_w, ctl0_tready_w, ctl0_tlast_w;
  wire [7:0] ctl0_tdata_w;

  wire cfgi_tvalid_w, cfgi_tready_w, cfgi_tlast_w;
  wire [7:0] cfgi_tdata_w;

  wire [1:0] ctl_xfer_type_w;
  wire [3:0] ctl_xfer_endp_w;
  wire [7:0] ctl_xfer_request_w;
  wire [15:0] ctl_xfer_value_w, ctl_xfer_index_w, ctl_xfer_length_w;

  wire ctl_xfer_int, ctl_xfer_accept_std;

  transaction #(
      .EP1_BULK_IN(1),  // IN- & OUT- for TART raw (antenna) samples
      .EP1_BULK_OUT(1),
      .EP1_CONTROL(0),
      .EP2_BULK_IN(1),  // IN-only for TART correlated values
      .EP2_BULK_OUT(0),
      .EP2_CONTROL(1),  // Control EP for configuring TART
      .HIGH_SPEED(HIGH_SPEED)
  ) U_USB_CONTROL (
      .clock(clock),
      .reset(reset),

.usb_addr_i(),

.tok_recv_i(),
.tok_type_i(),
.tok_addr_i(),
.tok_endp_i(),

.hsk_recv_i(),
.hsk_type_i(),
.hsk_send_o(),
.hsk_type_o(),
.hsk_sent_i(),

      .ep0_ce_o(ctl_xfer_int),
      .ep1_ce_o(),
      .ep2_ce_o(),

      .cfg_pipe0_type_o(ctl_xfer_type_w),
      .cfg_pipe0_endp_o(ctl_xfer_endp_w),

      .cfg_pipe0_tvalid_o(ctl0_tvalid_w),
      .cfg_pipe0_tready_i(ctl0_tready_w),
      .cfg_pipe0_tlast_o (ctl0_tlast_w),
      .cfg_pipe0_tdata_o (ctl0_tdata_w),

      .cfg_pipe0_tvalid_i(cfgi_tvalid_w),
      .cfg_pipe0_tready_o(cfgi_tready_w),
      .cfg_pipe0_tlast_i (cfgi_tlast_w),
      .cfg_pipe0_tdata_i (cfgi_tdata_w)
  );


  // -- USB configuration endpoint -- //

  wire cfg_request_w, usb_configured;
  wire [6:0] device_address;
  wire [7:0] current_configuration;

  // todo:
  //  - this module is messy -- does it work well enough?
  //  - does wrapping in skid-buffers break it !?
  cfg_pipe0 #(
      .VENDOR_ID(VENDOR_ID),
      .PRODUCT_ID(PRODUCT_ID),
      .MANUFACTURER_LEN(MANUFACTURER_LEN),
      .MANUFACTURER(MANUFACTURER),
      .PRODUCT_LEN(PRODUCT_LEN),
      .PRODUCT(PRODUCT),
      .SERIAL_LEN(SERIAL_LEN),
      .SERIAL(SERIAL),
      .CONFIG_DESC_LEN(CONFIG_DESC_LEN),
      .CONFIG_DESC(CONFIG_DESC),
      .HIGH_SPEED(HIGH_SPEED)
  ) U_CFG_PIPE0 (
      .clock(clock),
      .reset(reset),

      .ctl_xfer_req_i(ctl_xfer_int),
      .ctl_xfer_gnt_o(ctl_xfer_accept_std),

      .ctl_xfer_endpoint(ctl_xfer_endp_w),
      .ctl_xfer_type(ctl_xfer_type_w),
      .ctl_xfer_request(ctl_xfer_request_w),
      .ctl_xfer_value(ctl_xfer_value_w),
      .ctl_xfer_index(ctl_xfer_index_w),
      .ctl_xfer_length(ctl_xfer_length_w),

      .ctl_tvalid_o(cfgi_tvalid_w),
      .ctl_tready_i(cfgi_tready_w),
      .ctl_tlast_o (cfgi_tlast_w),
      .ctl_tdata_o (cfgi_tdata_w),

      .device_address(device_address),
      .current_configuration(current_configuration),
      .configured(usb_configured),
      .standart_request(cfg_request_w)
  );


endmodule  // ulpi_axis
