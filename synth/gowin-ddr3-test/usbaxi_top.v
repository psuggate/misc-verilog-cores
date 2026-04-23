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

module usbaxi_top (
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

  // -- DDR3 Settings -- //

  localparam LOW_LATENCY = 1;  // Default value
  localparam WR_PREFETCH = 0;  // Default value
  localparam INVERT_MCLK = 0;  // Default value
  localparam INVERT_DCLK = 0;  // Todo ...

`ifdef __gowin_for_the_win
  localparam CLK_IN_FREQ = "27";

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
  localparam DDR3_NPINS = DDR3_WIDTH / 2;
  localparam QSB = DDR3_NPINS / 8;

  localparam ADDRS = 27;
  localparam REQID = 4;

  // -- Signals -- //

  // Global signals //
  wire clock, reset;
  wire pclk, presetn;
  wire mclk, mrst;
  wire [3:0] cbits;

  localparam AXI_WIDTH = DDR3_WIDTH;
  localparam MSB = AXI_WIDTH - 1;
  localparam STROBES = AXI_WIDTH / 4;
  localparam BSB = STROBES - 1;
  localparam AXI_ADDRS = 32;
  localparam ASB = AXI_ADDRS - 1;
  localparam AXI_IDTAG = REQID;
  localparam ISB = AXI_IDTAG - 1;

  // AXI4 Signals to/from the Memory Controller //
  wire awvalid_w, wvalid_w, wlast_w, bready_w, arvalid_w, rready_w;
  wire awready_w, wready_w, bvalid_w, arready_w, rvalid_w, rlast_w;
  wire [ISB:0] awid_w, arid_w, bid, rid_w;
  wire [7:0] awlen_w, arlen_w;
  wire [1:0] awburst_w, arburst_w;
  wire [ASB:0] awaddr_w, araddr_w;
  wire [BSB:0] wstrb_w;
  wire [1:0] bresp_w, rresp_w;
  wire [MSB:0] rdata_w, wdata_w;

  // -- LEDs Stuffs -- //

  // Note: only 4 (of 6) LED's available in default config
  assign leds = {~cbits[3:0], 2'b11};

  // -- System Clocks & Resets -- //

  wire ulock, uclk, areset;

  ulpi_reset #(
      .PHASE("0000"),  // Note: timing-constraints used instead
      .PLLEN(0)
  ) U_RESET1 (
      .areset_n (rst_n),
      .ulpi_clk (ulpi_clk),
      .sys_clock(clk_26),

      .ulpi_rst_n(ulpi_rst),  // Active LO
      .pll_locked(ulock),

      .usb_clock(uclk),    // 60 MHz, PLL output, phase-shifted
      .usb_reset(areset),  // Active HI
      .ddr_clock()         // 120 MHz, PLL output, phase-shifted
  );

  // -- ULPI Core and BULK IN/OUT SRAM -- //

  wire configured, high_speed, conf_event, ddr3_conf;

  assign cbits = {configured, high_speed, conf_event, ddr3_conf};

  usb_axi_apb_bridge #(
      .DEBUG(DEBUG)
  ) U_USB1 (
      .usb_clock_o(clock),
      .usb_reset_o(reset),

      .ulpi_clock_i(usb_clk),
      .ulpi_dir_i  (ulpi_dir),
      .ulpi_nxt_i  (ulpi_nxt),
      .ulpi_stp_o  (ulpi_stp),
      .ulpi_data_io(ulpi_data),

      .configured_o(configured),
      .high_speed_o(high_speed),
      .conf_event_o(conf_event),
      .conf_value_o(),

      .pclk(pclk),
      .presetn(presetn),

      // APB requester interface, to controllers
      .penable_o(),
      .pwrite_o (),
      .pstrb_o  (),
      .pready_i (1'b0),
      .pslverr_i(1'b0),
      .paddr_o  (),
      .pwdata_o (),
      .prdata_i (0),

      .aclk(mclk),  // AXI clock domain
      .aresetn(~areset),

      .axi_awvalid_o(awvalid_w),
      .axi_awready_i(awready_w),
      .axi_awaddr_o(awaddr_w),
      .axi_awid_o(awid_w),
      .axi_awlen_o(awlen_w),
      .axi_awburst_o(awburst_w),

      .axi_wvalid_o(wvalid_w),
      .axi_wready_i(wready_w),
      .axi_wlast_o (wlast_w),
      .axi_wstrb_o (wstrb_w),
      .axi_wdata_o (wdata_w),

      .axi_bvalid_i(bvalid_w),
      .axi_bready_o(bready_w),
      .axi_bresp_i(bresp_w),
      .axi_bid_i(bid_w),

      .axi_arvalid_o(arvalid_w),
      .axi_arready_i(arready_w),
      .axi_araddr_o(araddr_w),
      .axi_arid_o(arid_w),
      .axi_arlen_o(arlen_w),
      .axi_arburst_o(arburst_w),

      .axi_rvalid_i(rvalid_w),
      .axi_rready_o(rready_w),
      .axi_rlast_i(rlast_w),
      .axi_rresp_i(rresp_w),
      .axi_rid_i(rid_w),
      .axi_rdata_i(rdata_w)
  );

  //
  //  DDR3 Cores Under Next-generation Tests
  ///

  wire [QSB:0] dfi_dqs_p, dfi_dqs_n;
  wire [1:0] dfi_wrdly;
  wire [2:0] dfi_rddly;

  // DFI <-> PHY
  wire dfi_rst_n, dfi_cke, dfi_cs_n, dfi_ras_n, dfi_cas_n, dfi_we_n;
  wire dfi_odt, dfi_wstb, dfi_wren, dfi_rden, dfi_valid, dfi_last;
  wire [  2:0] dfi_bank;
  wire [RSB:0] dfi_addr;
  wire [BSB:0] dfi_mask;
  wire [MSB:0] dfi_wdata, dfi_rdata;

  wire dfi_calib, dfi_align;
  wire [2:0] dfi_shift;

  wire clk_x2, mlock;

  assign mrst = ~mlock;

  // So 27.0 MHz divided by 4, then x29 = 195.75 MHz.
  gw2a_rpll #(
      .FCLKIN(CLK_IN_FREQ),
      .IDIV_SEL(CLK_IDIV_SEL),
      .FBDIV_SEL(CLK_FBDV_SEL),
      .ODIV_SEL(CLK_ODIV_SEL),
      .DYN_SDIV_SEL(CLK_SDIV_SEL)
  ) U_rPLL1 (
      .clkout(clk_x2),  // Default: 249.75  MHz
      .clockd(mclk),    // Default: 124.875 MHz
      .lock  (mlock),
      .clkin (clk_26),
      .reset (~arst_n)
  );

  axi_ddr3_lite #(
      .DDR_FREQ_MHZ(DDR_FREQ_MHZ),
      .DDR_ROW_BITS(DDR_ROW_BITS),
      .DDR_COL_BITS(DDR_COL_BITS),
      .DDR_DQ_WIDTH(DDR_DQ_WIDTH),
      .PHY_WR_DELAY(PHY_WR_DELAY),
      .PHY_RD_DELAY(PHY_RD_DELAY),
      .WR_PREFETCH (WR_PREFETCH),
      .LOW_LATENCY (LOW_LATENCY),
      .AXI_ID_WIDTH(REQID),
      .MEM_ID_WIDTH(REQID),
      .DFIFO_BYPASS(DFIFO_BYPASS),
      .PACKET_FIFOS(0)
  ) U_LITE (
      .arst_n(rst_n),  // Global, asynchronous reset

      .clock(mclk),  // memory subsystem clock
      .reset(mrst),  // synchronous reset

      .configured_o(ddr3_conf),

      // Write Channels
      .axi_awvalid_i(awvalid_w),
      .axi_awready_o(awready_w),
      .axi_awaddr_i(awaddr_w),
      .axi_awid_i(awid_w),
      .axi_awlen_i(awlen_w),
      .axi_awburst_i(awburst_w),

      .axi_wvalid_i(wvalid_w),
      .axi_wready_o(wready_w),
      .axi_wlast_i (wlast_w),
      .axi_wstrb_i (wstrb_w),
      .axi_wdata_i (wdata_w),

      .axi_bvalid_o(bvalid_w),
      .axi_bready_i(bready_w),
      .axi_bresp_o(bresp_w),
      .axi_bid_o(bid_w),

      // Standard Read-Channels
      .axi_arvalid_i(arvalid_w),
      .axi_arready_o(arready_w),
      .axi_araddr_i(araddr_w),
      .axi_arid_i(arid_w),
      .axi_arlen_i(arlen_w),
      .axi_arburst_i(arburst_w),

      .axi_rvalid_o(rvalid_w),
      .axi_rready_i(rready_w),
      .axi_rlast_o(rlast_w),
      .axi_rresp_o(rresp_w),
      .axi_rid_o(rid_w),
      .axi_rdata_o(rdata_w),

      .dfi_align_o(dfi_align),
      .dfi_calib_i(dfi_calib),

      .dfi_rst_no(dfi_rst_n),
      .dfi_cke_o (dfi_cke),
      .dfi_cs_no (dfi_cs_n),
      .dfi_ras_no(dfi_ras_n),
      .dfi_cas_no(dfi_cas_n),
      .dfi_we_no (dfi_we_n),
      .dfi_odt_o (dfi_odt),
      .dfi_bank_o(dfi_bank),
      .dfi_addr_o(dfi_addr),

      .dfi_wstb_o(dfi_wstb),
      .dfi_wren_o(dfi_wren),
      .dfi_mask_o(dfi_mask),
      .dfi_data_o(dfi_wdata),

      .dfi_rden_o(dfi_rden),
      .dfi_rvld_i(dfi_valid),
      .dfi_last_i(dfi_last),
      .dfi_data_i(dfi_rdata)
  );

  // -- DDR3 PHY -- //

`ifdef __gowin_for_the_win

  // GoWin Global System Reset signal tree.
  GSR GSR (.GSRI(1'b1));

  gw2a_ddr3_phy #(
      .WR_PREFETCH(WR_PREFETCH),
      .DDR3_WIDTH (DDR3_NPINS),
      .ADDR_BITS  (DDR_ROW_BITS),
      .INVERT_MCLK(INVERT_MCLK),
      .INVERT_DCLK(INVERT_DCLK),
      .WRITE_DELAY(WRITE_DELAY),
      .CLOCK_SHIFT(CLOCK_SHIFT)
  ) U_PHY1 (
      .clock  (clock),
      .reset  (reset),
      .clk_ddr(clk_x2),

      .dfi_rst_ni(dfi_rst_n),
      .dfi_cke_i (dfi_cke),
      .dfi_cs_ni (dfi_cs_n),
      .dfi_ras_ni(dfi_ras_n),
      .dfi_cas_ni(dfi_cas_n),
      .dfi_we_ni (dfi_we_n),
      .dfi_odt_i (dfi_odt),
      .dfi_bank_i(dfi_bank),
      .dfi_addr_i(dfi_addr),

      .dfi_wstb_i(dfi_wstb),
      .dfi_wren_i(dfi_wren),
      .dfi_mask_i(dfi_mask),
      .dfi_data_i(dfi_wdata),

      .dfi_rden_i(dfi_rden),
      .dfi_rvld_o(dfi_valid),
      .dfi_last_o(dfi_last),
      .dfi_data_o(dfi_rdata),

      // For WRITE- & READ- CALIBRATION
      .dfi_align_i(dfi_align),
      .dfi_calib_o(dfi_calib),
      .dfi_shift_o(dfi_shift),  // In 1/4 clock-steps

      .ddr_ck_po(ddr_ck),
      .ddr_ck_no(ddr_ck_n),
      .ddr_rst_no(ddr_rst_n),
      .ddr_cke_o(ddr_cke),
      .ddr_cs_no(ddr_cs),
      .ddr_ras_no(ddr_ras),
      .ddr_cas_no(ddr_cas),
      .ddr_we_no(ddr_we),
      .ddr_odt_o(ddr_odt),
      .ddr_ba_o(ddr_bank),
      .ddr_a_o(ddr_addr),
      .ddr_dm_o(ddr_dm),
      .ddr_dqs_pio(ddr_dqs),
      .ddr_dqs_nio(ddr_dqs_n),
      .ddr_dq_io(ddr_dq)
  );

`else  /* !__gowin_for_the_win */

  assign dfi_calib = 1'b1;

  // Generic PHY -- that probably won't synthesise correctly, due to how the
  // (read-)data is registered ...
  generic_ddr3_phy #(
      .DDR3_WIDTH(16),  // (default)
      .ADDR_BITS(DDR_ROW_BITS)  // default: 14
  ) U_PHY1 (
      .clock  (clock),
      .reset  (reset),
      .clk_ddr(clk_x2),

      .dfi_rst_ni(dfi_rst_n),
      .dfi_cke_i (dfi_cke),
      .dfi_cs_ni (dfi_cs_n),
      .dfi_ras_ni(dfi_ras_n),
      .dfi_cas_ni(dfi_cas_n),
      .dfi_we_ni (dfi_we_n),
      .dfi_odt_i (dfi_odt),
      .dfi_bank_i(dfi_bank),
      .dfi_addr_i(dfi_addr),

      .dfi_wstb_i(dfi_wstb),
      .dfi_wren_i(dfi_wren),
      .dfi_mask_i(dfi_mask),
      .dfi_data_i(dfi_wdata),

      .dfi_rden_i(dfi_rden),
      .dfi_rvld_o(dfi_valid),
      .dfi_last_o(dfi_last),
      .dfi_data_o(dfi_rdata),

      .ddr3_ck_po(ddr_ck),
      .ddr3_ck_no(ddr_ck_n),
      .ddr3_cke_o(ddr_cke),
      .ddr3_rst_no(ddr_rst_n),
      .ddr3_cs_no(ddr_cs),
      .ddr3_ras_no(ddr_ras),
      .ddr3_cas_no(ddr_cas),
      .ddr3_we_no(ddr_we),
      .ddr3_odt_o(ddr_odt),
      .ddr3_ba_o(ddr_bank),
      .ddr3_a_o(ddr_addr),
      .ddr3_dm_o(ddr_dm),
      .ddr3_dqs_pio(ddr_dqs),
      .ddr3_dqs_nio(ddr_dqs_n),
      .ddr3_dq_io(ddr_dq)
  );

`endif  /* !__gowin_for_the_win */

endmodule  /* usbaxi_top */
