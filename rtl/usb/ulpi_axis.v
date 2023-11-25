`timescale 1ns / 100ps
`define SERIAL_STRING "BULK0000"
`define SERIAL_LENGTH 8

`define VENDOR_STRING "University of Otago"
`define VENDOR_LENGTH 19

`define PRODUCT_STRING "TART USB"
`define PRODUCT_LENGTH 8

module ulpi_axis (  /*AUTOARG*/
    // Outputs
    ulpi_reset_o,
    ulpi_stp_o,
    usb_clock_o,
    usb_reset_o,
    fifo_in_full_o,
    fifo_out_full_o,
    fifo_out_overflow_o,
    fifo_has_data_o,
    usb_sof_o,
    crc_err_o,
    usb_vbus_valid_o,
    usb_idle_o,
    usb_suspend_o,
    ulpi_rx_overflow_o,
    s_axis_tready_o,
    m_axis_tvalid_o,
    m_axis_tlast_o,
    m_axis_tdata_o,
    // Inouts
    ulpi_data_io,
    // Inputs
    areset_n,
    ulpi_clock_i,
    ulpi_dir_i,
    ulpi_nxt_i,
    s_axis_tvalid_i,
    s_axis_tlast_i,
    s_axis_tdata_i,
    m_axis_tready_i
);

  parameter EP1_BULK_IN = 1;
  parameter EP1_BULK_OUT = 1;
  parameter EP1_CONTROL = 0;

  parameter EP2_BULK_IN = 1;
  parameter EP2_BULK_OUT = 0;
  parameter EP2_CONTROL = 1;

  parameter ENDPOINT1 = 1;  // set to '0' to disable
  parameter ENDPOINT2 = 2;  // set to '0' to disable

  parameter [`SERIAL_LENGTH*8-1:0] SERIAL_STRING = `SERIAL_STRING;
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


  assign ulpi_data_io = ulpi_dir_i ? {8{1'bz}} : ulpi_data_ow;
  assign ulpi_data_iw = ulpi_data_io;


  // -- AXI4 stream to/from ULPI stream -- //

  wire ctl_start_w;
  wire [7:0] ctl_rtype_w, ctl_rargs_w;
  wire [15:0] ctl_value_w, ctl_index_w, ctl_length_w;

  wire ulpi_rx_tvalid_w, ulpi_rx_tready_w, ulpi_rx_tlast_w;
  wire ulpi_tx_tvalid_w, ulpi_tx_tready_w, ulpi_tx_tlast_w;
  wire [7:0] ulpi_rx_tdata_w, ulpi_tx_tdata_w;

  wire ctl0_tvalid_w, ctl0_tready_w, ctl0_tlast_w;
  wire cfgi_tvalid_w, cfgi_tready_w, cfgi_tlast_w;
  wire [7:0] ctl0_tdata_w, cfgi_tdata_w;

  wire ctlo_tvalid_w, ctlo_tready_w, ctlo_tlast_w;
  wire ctli_tvalid_w, ctli_tready_w, ctli_tlast_w;
  wire [7:0] ctlo_tdata_w, ctli_tdata_w;

  wire blko_tvalid_w, blko_tready_w, blko_tlast_w;
  wire blki_tvalid_w, blki_tready_w, blki_tlast_w;
  wire [7:0] blko_tdata_w, blki_tdata_w;

  usb_ulpi #(
      .HIGH_SPEED(HIGH_SPEED)
  ) U_USB_ULPI0 (
      .rst_n(rst_nq),

      .ulpi_clk(clock),
      .usb_reset_o(reset),  // Sync reset for USB domain cores

      .ulpi_data_in(ulpi_data_iw),
      .ulpi_data_out(ulpi_data_ow),
      .ulpi_dir(ulpi_dir_i),
      .ulpi_nxt(ulpi_nxt_i),
      .ulpi_stp(ulpi_stp_o),
      .ulpi_reset(ulpi_reset_o),

      .axis_rx_tvalid_o(ulpi_rx_tvalid_w),
      .axis_rx_tready_i(ulpi_rx_tready_w),
      .axis_rx_tlast_o (ulpi_rx_tlast_w),
      .axis_rx_tdata_o (ulpi_rx_tdata_w),

      .axis_tx_tvalid_i(ulpi_tx_tvalid_w),
      .axis_tx_tready_o(ulpi_tx_tready_w),
      .axis_tx_tlast_i (ulpi_tx_tlast_w),
      .axis_tx_tdata_i (ulpi_tx_tdata_w),

      .ulpi_rx_overflow_o(ulpi_rx_overflow_o),
      .usb_vbus_valid_o  (usb_vbus_valid_o),
      .usb_idle_o        (usb_idle_o),
      .usb_suspend_o     (usb_suspend_o)
  );


  // -- Route Bulk IN Signals -- //

  generate
    if (EP1_BULK_IN && EP2_BULK_IN) begin : g_yes_mux_bulk_in

      // todo: 2:1 AXI4-Stream MUX (from Alex Forencich)

    end else begin : g_no_mux_bulk_in

      // todo: Hook-up bulk EP signals

    end
  endgenerate


  // -- Route Control Transfer Signals -- //

  generate
    if (EP1_CONTROL && EP2_CONTROL) begin : g_yes_mux_control

      // todo: 2:1 AXI4-Stream MUX (from Alex Forencich)

    end else begin : g_no_mux_control

      // todo: Hook-up control EP signals

    end
  endgenerate


  // -- Top-level USB Control Core -- //

  usb_control #(
      .EP1_BULK_IN(EP1_BULK_IN),  // IN- & OUT- for TART raw (antenna) samples
      .EP1_BULK_OUT(EP1_BULK_OUT),
      .EP1_CONTROL(EP1_CONTROL),
      .ENDPOINT1(ENDPOINT1),
      .EP2_BULK_IN(EP2_BULK_IN),  // IN-only for TART correlated values
      .EP2_BULK_OUT(EP2_BULK_OUT),
      .EP2_CONTROL(EP2_CONTROL),  // Control EP for configuring TART
      .ENDPOINT2(ENDPOINT2),
      .VENDOR_ID(VENDOR_ID),
      .VENDOR_LENGTH(VENDOR_LENGTH),
      .VENDOR_STRING(VENDOR_STRING),
      .PRODUCT_ID(PRODUCT_ID),
      .PRODUCT_LENGTH(PRODUCT_LENGTH),
      .PRODUCT_STRING(PRODUCT_STRING),
      .SERIAL_LENGTH(SERIAL_LENGTH),
      .SERIAL_STRING(SERIAL_STRING)
  ) U_USB_CONTROL0 (
      .configured_o(),
      .usb_addr_o(),
      .usb_conf_o(),
      .usb_sof_o(),
      .crc_err_o(),

      // USB control & bulk data received from host (via decoder)
      .usb_tvalid_i(ulpi_rx_tvalid_w),
      .usb_tready_o(ulpi_rx_tready_w),
      .usb_tlast_i (ulpi_rx_tlast_w),
      .usb_tdata_i (ulpi_rx_tdata_w),

      // USB control & bulk data transmitted to host (via encoder)
      .usb_tvalid_o(ulpi_tx_tvalid_w),
      .usb_tready_i(ulpi_tx_tready_w),
      .usb_tlast_o (ulpi_tx_tlast_w),
      .usb_tdata_o (ulpi_tx_tdata_w),

      .blk_start_o (),
      .blk_dtype_o (),
      .blk_done1_i (1'b0),
      .blk_done2_i (1'b0),
      .blk_muxsel_o(),

      .blk_tvalid_o(blko_tvalid_w),
      .blk_tready_i(blko_tready_w),
      .blk_tlast_o (blko_tlast_w),
      .blk_tdata_o (blko_tdata_w),

      .blk_tvalid_i(blki_tvalid_w),
      .blk_tready_o(blki_tready_w),
      .blk_tlast_i (blki_tlast_w),
      .blk_tdata_i (blki_tdata_w),

      .ctl_start_o (ctl_start_w),
      .ctl_rtype_o (ctl_rtype_w),
      .ctl_rargs_o (ctl_rargs_w),
      .ctl_value_o (ctl_value_w),
      .ctl_index_o (ctl_index_w),
      .ctl_length_o(ctl_length_w),

      .ctl_tvalid_o(ctlo_tvalid_w),
      .ctl_tready_i(ctlo_tready_w),
      .ctl_tlast_o (ctlo_tlast_w),
      .ctl_tdata_o (ctlo_tdata_w),

      .ctl_tvalid_i(ctli_tvalid_w),
      .ctl_tready_o(ctli_tready_w),
      .ctl_tlast_i (ctli_tlast_w),
      .ctl_tdata_i (ctli_tdata_w),
      /*AUTOINST*/
      // Outputs
      .reset       (reset),
      // Inputs
      .clock       (clock)
  );


endmodule  // ulpi_axis
