`timescale 1ns / 100ps
/**
 * Connects a USB ULPI PHY to a DDR3 SRAM, and this top-level module is mostly
 * just a demo, and for testing the DDR3 controller.
 *
 * Copyright 2024, Patrick Suggate.
 *
 */

`define __gowin_for_the_win

// With the DDR3 clock at 250 MHz, this slows down simulations
`ifndef __icarus
`define DDR3_250_MHZ
`endif  /* __icarus */

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

  localparam SRAM_BYTES = 2048;

  // -- USB Settings -- //

  localparam DEBUG = 1;
  localparam LOOPBACK = 1;
  localparam USE_EP4_OUT = 1;

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
  localparam ENDPOINT4 = 4'd4;

  // Maximum packet lengths for each packet-type (up to 1024 & 64, respectively)
  localparam integer MAX_PACKET_LENGTH = 512;
  localparam integer MAX_CONFIG_LENGTH = 64;

  // -- DDR3 Settings -- //

  localparam LOW_LATENCY = 1;  // Default value
  localparam WR_PREFETCH = 0;  // Default value
  localparam INVERT_MCLK = 0;  // Default value
  localparam INVERT_DCLK = 0;  // Todo ...

`ifdef __gowin_for_the_win
  localparam CLK_IN_FREQ  = "27";

`ifdef DDR3_250_MHZ
  // So 27.0 MHz divided by 4, then x37 = 249.75 MHz.
  localparam DDR_FREQ_MHZ = 125;
  localparam IDIV_SEL = 3;
  localparam FBDIV_SEL = 36;
  // localparam FBDIV_SEL = 39; // Works with 'PHY_RD_DELAY = 3', below
  localparam ODIV_SEL = 4;
  localparam SDIV_SEL = 2;

  localparam CLOCK_SHIFT = 2'b11;
  localparam WRITE_DELAY = 2'b01;
  localparam PHY_WR_DELAY = 3;
  localparam PHY_RD_DELAY = 2;
  // localparam PHY_RD_DELAY = 3; // Works with 'FBDIV_SEL = 39', above

`else  /* !DDR_FREQ_MHZ */
  // So 27.0 MHz divided by 4, then x29 = 195.75 MHz.
  localparam DDR_FREQ_MHZ = 100;
  localparam IDIV_SEL = 3;
  localparam FBDIV_SEL = 28;
  localparam ODIV_SEL = 4;
  localparam SDIV_SEL = 2;

  localparam CLOCK_SHIFT = 2'b11;
  localparam WRITE_DELAY = 2'b01;
  localparam PHY_WR_DELAY = 3;
  localparam PHY_RD_DELAY = 2;

`endif  /* !DDR_FREQ_MHZ */
`else  /* !__gowin_for_the_win */
  //
  // Uses simulation-only clocks, and a "generic" DDR3 PHY
  //
  localparam CLOCK_SHIFT = 2'b11;
  localparam WRITE_DELAY = 2'b01;
  localparam PHY_WR_DELAY = 1;
  localparam PHY_RD_DELAY = 1;

`endif  /* !__gowin_for_the_win */

  // We only require the ASYNC FIFOs, because the USB End-Points provide packet
  // FIFOs, for each direction
  localparam DFIFO_BYPASS = 1;
  localparam DDR3_WIDTH = 32;

  // -- UART Settings -- //

  localparam [15:0] UART_PRESCALE = 16'd33;  // For: 60.0 MHz / (230400 * 8)

  // -- Signals -- //

  // Global signals //
  wire clock, reset;
  wire [3:0] cbits;

  // Local Signals //
  wire configured, crc_error_w, ep1_rdy, ep2_rdy, ep3_rdy;
  wire ddr3_conf_w, sys_clk, sys_rst;

  // Data-path //
  wire s_tvalid, s_tready, s_tlast, s_tkeep;
  wire x_tvalid, x_tready, x_tlast, x_tkeep;
  wire m_tvalid, m_tready, m_tlast, m_tkeep;
  wire y_tvalid, y_tready, y_tlast, y_tkeep;
  wire [7:0] s_tdata, x_tdata, m_tdata, y_tdata;

  // -- LEDs Stuffs -- //

  // Note: only 4 (of 6) LED's available in default config
  assign leds = {~cbits[3:0], 2'b11};
  assign uart_tx = 1'b1;


  // -- ULPI Core and BULK IN/OUT SRAM -- //

  wire ep1_sel, ep2_sel;
  // assign cbits = {ep3_rdy, ep2_rdy, ep1_rdy, configured};
  assign cbits = {ep2_sel, ep2_rdy, ep1_sel, ep1_rdy};

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
      .DEBUG(DEBUG),
      .USE_UART(0),
      .ENDPOINTD(ENDPOINT3),
      .ENDPOINT4(ENDPOINT4),
      .USE_EP4_OUT(USE_EP4_OUT)
  ) U_USB1 (
      .osc_in(sys_clk),
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
      .uart_tx_o(),

      .usb_clock_o(clock),
      .usb_reset_o(reset),

      .configured_o(configured),
      .conf_event_o(),
      .conf_value_o(),
      .crc_error_o (crc_error_w),

      .blki_tvalid_i(x_tvalid),  // Extra 'BULK IN' EP data-path
      .blki_tready_o(x_tready),
      .blki_tlast_i (x_tlast),
      .blki_tdata_i (x_tdata),

      .blko_tvalid_o(y_tvalid),  // USB 'BULK OUT' EP data-path
      .blko_tready_i(y_tready),
      .blko_tlast_o (y_tlast),
      .blko_tdata_o (y_tdata),

      .blkx_tvalid_i(LOOPBACK ? m_tvalid : s_tvalid),  // USB 'BULK IN' EP data-path
      .blkx_tready_o(s_tready),
      .blkx_tlast_i (LOOPBACK ? m_tlast : s_tlast),
      .blkx_tdata_i (LOOPBACK ? m_tdata : s_tdata),

      .blky_tvalid_o(m_tvalid),  // USB 'BULK OUT' EP data-path
      .blky_tready_i(LOOPBACK ? s_tready : m_tready),
      .blky_tlast_o(m_tlast),
      .blky_tdata_o(m_tdata)
  );

  assign ep1_rdy = U_USB1.U_TOP1.ep1_rdy_w;
  assign ep1_sel = U_USB1.U_TOP1.ep1_sel_w && !U_USB1.U_TOP1.ep1_hlt_w;
  assign ep2_rdy = U_USB1.U_TOP1.ep2_rdy_w;
  assign ep2_sel = U_USB1.U_TOP1.ep2_sel_w && !U_USB1.U_TOP1.ep2_hlt_w;

  //
  //  DDR3 Cores Under Next-generation Tests
  ///

  localparam ADDRS = 27;
  localparam REQID = 4;

  assign y_tkeep = y_tvalid;  // Todo ...

`ifdef __use_bypass
  ddr3_top_plus #(

`else  /* !__use_bypass */
  ddr3_top #(

`endif /* !__use_bypass */
      .SRAM_BYTES  (SRAM_BYTES),
      .DATA_WIDTH  (DDR3_WIDTH),
      .DFIFO_BYPASS(DFIFO_BYPASS),
      .PHY_WR_DELAY(PHY_WR_DELAY),
      .PHY_RD_DELAY(PHY_RD_DELAY),
      .CLK_IDIV_SEL(IDIV_SEL),
      .CLK_FBDV_SEL(FBDIV_SEL),
      .CLK_ODIV_SEL(ODIV_SEL),
      .CLK_SDIV_SEL(SDIV_SEL),
      .DDR_FREQ_MHZ(DDR_FREQ_MHZ),
      .LOW_LATENCY (LOW_LATENCY),
      .WR_PREFETCH (WR_PREFETCH),
      .WRITE_DELAY (WRITE_DELAY),
      .CLOCK_SHIFT (CLOCK_SHIFT)
  ) ddr_core_inst (
      .osc_in(clk_26),  // Dev-board clock
      .arst_n(rst_n),   // 'S2' button for async-reset

      .bus_clock(clock),
      .bus_reset(reset),

      .ddr3_conf_o(ddr3_conf_w),
      .ddr_clock_o(sys_clk),
      .ddr_reset_o(sys_rst),

      // From USB or SPI
      .s_tvalid(y_tvalid),
      .s_tready(y_tready),
      .s_tkeep (y_tkeep),
      .s_tlast (y_tlast),
      .s_tdata (y_tdata),

      // To USB or SPI
      .m_tvalid(x_tvalid),
      .m_tready(x_tready),
      .m_tkeep (x_tkeep),
      .m_tlast (x_tlast),
      .m_tdata (x_tdata),

`ifdef __use_bypass
      // Fast-read channels [optional]
      .byp_arvalid_i(1'b0),
      .byp_arready_o(),
      .byp_araddr_i({ADDRS{1'b0}}),
      .byp_arid_i({REQID{1'b0}}),
      .byp_arlen_i(8'd0),
      .byp_arburst_i(2'd0),

      .byp_rvalid_o(),
      .byp_rready_i(1'b1),
      .byp_rlast_o(),
      .byp_rresp_o(),
      .byp_rid_o(),
      .byp_rdata_o(),
`endif /* __use_bypass */

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


endmodule  /* usb_ddr3_top */
