`timescale 1ns / 100ps
module usb_ulpi_core #(
    parameter integer PACKET_FIFO_DEPTH = 2048,
    parameter integer MAX_PACKET_LENGTH = 512,
    parameter integer MAX_CONFIG_LENGTH = 64,

    parameter [3:0] ENDPOINT1 = 4'd1,
    parameter [3:0] ENDPOINT2 = 4'd2,

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
    input blki_tkeep_i,
    input [7:0] blki_tdata_i,

    output blko_tvalid_o,
    input blko_tready_i,
    output blko_tlast_o,
    output blko_tkeep_o,
    output [7:0] blko_tdata_o
);

  wire locked, clock, reset;
  wire configured, conf_event;
  wire [2:0] conf_value;

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
      .USE_EP2_IN(1),
      .USE_EP1_OUT(1)
  ) U_USB1 (
      // .areset_n       (ulpi_rst),
      .areset_n(~reset),

      .ulpi_clock_i(clock),
      .ulpi_dir_i  (ulpi_dir),
      .ulpi_nxt_i  (ulpi_nxt),
      .ulpi_stp_o  (ulpi_stp),
      .ulpi_data_io(ulpi_data),

      .usb_clock_o(usb_clock_o),
      .usb_reset_o(usb_reset_o),

      .configured_o(configured_o),
      .conf_event_o(conf_event_o),
      .conf_value_o(conf_value_o),

      .blki_tvalid_i(blki_tvalid_i),  // USB 'BULK IN' EP data-path
      .blki_tready_o(blki_tready_o),
      .blki_tlast_i (blki_tlast_i),
      .blki_tkeep_i (blki_tkeep_i),
      .blki_tdata_i (blki_tdata_i),

      .blko_tvalid_o(blko_tvalid_o),  // USB 'BULK OUT' EP data-path
      .blko_tready_i(blko_tready_i),
      .blko_tlast_o (blko_tlast_o),
      .blko_tkeep_o (blko_tkeep_o),
      .blko_tdata_o (blko_tdata_o)
  );

  assign uart_tx_o   = 1'b1;
  assign crc_error_o = U_USB1.crc_error_w;


endmodule  /* usb_ulpi_core */
