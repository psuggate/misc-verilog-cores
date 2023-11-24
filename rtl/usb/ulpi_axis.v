`timescale 1ns / 100ps
`define SERIAL_NUMBER "BULK0000"
`define SERIAL_LENGTH 8

`define VENDOR_STRING "University of Otago"
`define VENDOR_LENGTH 19

`define PRODUCT_STRING "TART USB"
`define PRODUCT_LENGTH 8

module ulpi_axis(/*AUTOARG*/);

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
output usb_reset_o; // USB core is in reset state

// Status flags for IN/OUT FIFOs, and the USB core
output fifo_in_full_o;
output fifo_out_full_o;
output fifo_out_overflow_o;
output fifo_has_data_o;

output usb_sof_o;
output usb_crc_error_o;
output usb_vbus_valid_o;
output usb_idle_o;  // USB core is idling
output usb_suspend_o; // USB core has been suspended

// AXI4-stream slave-port signals (IN: EP -> host)
// Note: USB clock-domain
input  s_axis_tvalid_i;
output s_axis_tready_o;
input  s_axis_tlast_i;
input  [7:0] s_axis_tdata_i;

// AXI4-stream master-port signals (OUT: host -> EP)
// Note: USB clock-domain
output m_axis_tvalid_o;
input  m_axis_tready_i;
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

  usb_ulpi #(
      .HIGH_SPEED(HIGH_SPEED)
  ) usb_ulpi_inst (
      .rst_n(rst_nq),
      .ulpi_clk(clock),

      .ulpi_data_in(ulpi_data_iw),
      .ulpi_data_out(ulpi_data_ow),
      .ulpi_dir(ulpi_dir_i),
      .ulpi_nxt(ulpi_nxt_i),
      .ulpi_stp(ulpi_stp_o),
      .ulpi_reset(ulpi_reset),

      .axis_rx_tvalid_o(axis_rx_tvalid),
      .axis_rx_tready_i(axis_rx_tready),
      .axis_rx_tlast_o (axis_rx_tlast),
      .axis_rx_tdata_o (axis_rx_tdata),

      .axis_tx_tvalid_i(axis_tx_tvalid),
      .axis_tx_tready_o(axis_tx_tready),
      .axis_tx_tlast_i (axis_tx_tlast),
      .axis_tx_tdata_i (axis_tx_tdata),

      .ulpi_rx_overflow_o(ulpi_rx_overflow_o),

      .usb_vbus_valid_o(usb_vbus_valid_o),
      .usb_reset_o(reset),
      .usb_idle_o(usb_idle_o),
      .usb_suspend_o(usb_suspend_o)
  );


  // -- Encode/decode USB packets, over the AXI4 streams -- //

  encode_packet tx_usb_packet_inst (
      .reset(reset),
      .clock(clock),

      .tx_tvalid_o(axis_tx_tvalid),
      .tx_tready_i(axis_tx_tready),
      .tx_tlast_o (axis_tx_tlast),
      .tx_tdata_o (axis_tx_tdata),

      .hsk_send_i(tx_trn_send_hsk),
      .hsk_done_o(tx_trn_hsk_sent),
      .hsk_type_i(tx_trn_hsk_type),

      .tok_send_i(1'b0), // Only used by USB hosts
      .tok_done_o(),
      .tok_type_i(2'bx),
      .tok_data_i(16'bx),

      .trn_start_i (tx_trn_data_start),
      .trn_type_i  (tx_trn_data_type),
      .trn_tvalid_i(tx_trn_data_valid),
      .trn_tready_o(tx_trn_data_ready),
      .trn_tlast_i (tx_trn_data_last),
      .trn_tdata_i (tx_trn_data)
  );

  decode_packet rx_usb_packet_inst (
      .reset(reset),
      .clock(clock),

      // USB configuration fields, and status flags
      .usb_address_i(device_address),
      .usb_sof_o(usb_sof_o),
      .crc_err_o(usb_crc_error_o),

      // ULPI -> decoder stream
      .ulpi_tvalid_i(ulpi_rx_tvalid),
      .ulpi_tready_o(ulpi_rx_tready),
      .ulpi_tlast_i (ulpi_rx_tlast),
      .ulpi_tdata_i (ulpi_rx_tdata),

      // Indicates that a (OUT/IN/SETUP) token was received
      .trn_start_o(usb_rx_trn_start), // Start strobe
      .trn_type_o(usb_rx_trn_type), // Token-type (OUT/IN/SETUP)
      .trn_address_o(usb_rx_trn_address),
      .trn_endpoint_o(usb_rx_trn_endpoint),

      // Data packet (OUT, DATA0/1/2 MDATA) received
      .rx_trn_valid_o(rx_trn_valid),
      .rx_trn_end_o  (rx_trn_end),
      .rx_trn_type_o (rx_trn_data_type),
      .rx_trn_data_o (rx_trn_data),

      .out_tvalid_o(out_tvalid_w),
      .out_tend_o  (out_tend_w),
      .out_ttype_o (out_ttype_w),
      .out_tdata_o (out_tdata_w),

      // Handshake packet information
      .hsk_type_o(rx_trn_hsk_type),
      .hsk_recv_o(rx_trn_hsk_recv)
  );


// -- FSM for USB packets, handshakes, etc. -- //

usb_control
#(  .EP1_BULK_IN(1),  // IN- & OUT- for TART raw (antenna) samples
    .EP1_BULK_OUT(1),
    .EP1_CONTROL(0),
    .EP2_BULK_IN(1),  // IN-only for TART correlated values
    .EP2_BULK_OUT(0),
    .EP2_CONTROL(1),  // Control EP for configuring TART
    .HIGH_SPEED(HIGH_SPEED)
) U_USB_CONTROL (
    .clock(clock),
    .reset(reset),

    .cfg_pipe0_tvalid_o(ctl0_tvalid_w),
    .cfg_pipe0_tready_i(ctl0_tready_w),
    .cfg_pipe0_tlast_o(ctl0_tlast_w),
    .cfg_pipe0_tdata_o(ctl0_tdata_w),

    .cfg_pipe0_tvalid_o(cfgi_tvalid_w),
    .cfg_pipe0_tready_i(cfgi_tready_w),
    .cfg_pipe0_tlast_o(cfgi_tlast_w),
    .cfg_pipe0_tdata_o(cfgi_tdata_w)
);

always @(posedge clock) begin
  if (reset) begin
  end else begin
  end
end


  // -- USB configuration endpoint -- //

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

      .ctl_xfer_endpoint(ctl_xfer_endpoint_int),
      .ctl_xfer_type(ctl_xfer_type_int),
      .ctl_xfer_request(ctl_xfer_request_int),
      .ctl_xfer_value(ctl_xfer_value_int),
      .ctl_xfer_index(ctl_xfer_index_int),
      .ctl_xfer_length(ctl_xfer_length_int),

      .ctl_xfer_gnt_o(ctl_xfer_accept_std),
      .ctl_xfer_req_i(ctl_xfer_int),

      .ctl_tvalid_o(cfgi_tvalid_w),
      .ctl_tready_i(cfgi_tready_w),
      .ctl_tlast_o (cfgi_tlast_w),
      .ctl_tdata_o (cfgi_tdata_w),

      .device_address(device_address),
      .current_configuration(current_configuration),
      .configured(usb_configured),
      .standart_request(cfg_request_w)
  );


endmodule // ulpi_axis
