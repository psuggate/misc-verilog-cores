`timescale 1ns / 100ps
module usb_ddr3_top (
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
    inout [7:0] ulpi_data,

    // 1Gb DDR3 SDRAM pins
    output ddr_ck,
    output ddr_ck_n,
    output ddr_cke,
    output ddr_rst_n,
    output ddr_cs,
    output ddr_ras,
    output ddr_cas,
    output ddr_we,
    output ddr_odt,
    output [2:0] ddr_bank,
    output [12:0] ddr_addr,
    output [1:0] ddr_dm,
    inout [1:0] ddr_dqs,
    inout [1:0] ddr_dqs_n,
    inout [15:0] ddr_dq
);

  // -- USB Settings -- //

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

  // USB-core end-point configuration
  localparam ENDPOINT1 = 4'd1;
  localparam ENDPOINT2 = 4'd2;
  localparam ENDPOINT3 = 4'd3;

  // Maximum packet lengths for each packet-type (up to 1024 & 64, respectively)
  localparam integer MAX_PACKET_LENGTH = 512;
  localparam integer MAX_CONFIG_LENGTH = 64;

  // -- DDR3 Settings -- //

  parameter DDR_FREQ_MHZ = 100;

  // -- UART Settings -- //

  localparam [15:0] UART_PRESCALE = 16'd33;  // For: 60.0 MHz / (230400 * 8)


  // -- Signals -- //

  // Global signals //
  wire clock, reset;
  wire [3:0] cbits;

  // Local Signals //
  wire configured, crc_error_w, ep1_rdy, ep2_rdy, ep3_rdy;

  // Data-path //
  wire s_tvalid, s_tready, s_tlast, s_tkeep;
  wire x_tvalid, x_tready, x_tlast, x_tkeep;
  wire m_tvalid, m_tready, m_tlast, m_tkeep;
  wire [7:0] s_tdata, x_tdata, m_tdata;

  // -- LEDs Stuffs -- //

  // Note: only 4 (of 6) LED's available in default config
  assign leds = {~cbits[3:0], 2'b11};


  // -- ULPI Core and BULK IN/OUT SRAM -- //

  assign cbits = {ep3_rdy, ep2_rdy, ep1_rdy, configured};

  // Todo: use for control & logging ??
  assign x_tvalid = 1'b0;
  assign x_tkeep = 1'b0;
  assign x_tlast = 1'b0;
  assign x_tdata = 8'hA7;

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
      .MAX_PACKET_LENGTH(MAX_PACKET_LENGTH),
      .MAX_CONFIG_LENGTH(MAX_CONFIG_LENGTH),
      .DEBUG(1),
      .USE_UART(1),
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
      .conf_event_o(),
      .conf_value_o(),
      .crc_error_o (crc_error_w),

      .blki_tvalid_i(s_tvalid),  // USB 'BULK IN' EP data-path
      .blki_tready_o(s_tready),
      .blki_tlast_i (s_tlast),
      .blki_tdata_i (s_tdata),

      .blkx_tvalid_i(x_tvalid),  // Extra 'BULK IN' EP data-path
      .blkx_tready_o(x_tready),
      .blkx_tlast_i (x_tlast),
      .blkx_tdata_i (x_tdata),

      .blko_tvalid_o(m_tvalid),  // USB 'BULK OUT' EP data-path
      .blko_tready_i(m_tready),
      .blko_tlast_o (m_tlast),
      .blko_tdata_o (m_tdata)
  );

  assign ep1_rdy = U_USB1.U_USB1.ep1_rdy_w;
  assign ep2_rdy = U_USB1.U_USB1.ep2_rdy_w;
  assign ep3_rdy = U_USB1.U_USB1.ep3_rdy_w | crc_error_w;


  //
  //  DDR3 Cores Under Next-generation Tests
  ///

  localparam LOW_LATENCY = 0;

  ddr3_top #(
             .SRAM_BYTES(2048),
             .DATA_WIDTH(32),
      .LOW_LATENCY  (LOW_LATENCY)
  ) ddr_core_inst (
      .clk_26(clk_26),  // Dev-board clock
      .rst_n (rst_n),   // 'S2' button for async-reset

      .bus_clock(clock),
      .bus_reset(reset),

      // From USB or SPI
      .s_tvalid(m_tvalid),
      .s_tready(m_tready),
      .s_tkeep (m_tkeep),
      .s_tlast (m_tlast),
      .s_tdata (m_tdata),

      // To USB or SPI
      .m_tvalid(s_tvalid),
      .m_tready(s_tready),
      .m_tkeep (s_tkeep),
      .m_tlast (s_tlast),
      .m_tdata (s_tdata),

      // 1Gb DDR3 SDRAM pins
      .ddr_ck(ddr_ck),
      .ddr_ck_n(ddr_ck_n),
      .ddr_cke(ddr_cke),
      .ddr_rst_n(ddr_rst_n),
      .ddr_cs(ddr_cs),
      .ddr_ras(ddr_ras),
      .ddr_cas(ddr_cas),
      .ddr_we(ddr_we),
      .ddr_odt(ddr_odt),
      .ddr_bank(ddr_bank),
      .ddr_addr(ddr_addr),
      .ddr_dm(ddr_dm),
      .ddr_dqs(ddr_dqs),
      .ddr_dqs_n(ddr_dqs_n),
      .ddr_dq(ddr_dq)
  );


endmodule  // usb_ddr3_top
