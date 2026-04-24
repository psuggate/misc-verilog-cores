`timescale 1ns / 100ps
/**
 * Connects a USB ULPI PHY to a DDR3 SRAM, and this top-level module is mostly
 * just a demo, and for testing the DDR3 controller.
 *
 * Copyright 2024, Patrick Suggate.
 *
 */
`define __gowin_for_the_win
// `define __spanner_montana

// With the DDR3 clock at 250 MHz, this slows down simulations
`ifndef __icarus
`define DDR3_250_MHZ
`endif  /* __icarus */

module usbaxi_top #(
    parameter ENDPOINT1 = 4'd5,
    parameter ENDPOINT2 = 4'd3,
    parameter ENDPOINT3 = 4'd1,
    parameter ENDPOINT4 = 4'd2
) (
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
  localparam CLK_IDIV_SEL = 3;
  localparam CLK_FBDV_SEL = 36;
  // localparam FBDIV_SEL = 39; // Works with 'PHY_RD_DELAY = 3', below
  localparam CLK_ODIV_SEL = 4;
  localparam CLK_SDIV_SEL = 2;

  localparam CLOCK_SHIFT = 2'b11;
  localparam WRITE_DELAY = 2'b01;
  localparam PHY_WR_DELAY = 3;
  localparam PHY_RD_DELAY = 2;
  // localparam PHY_RD_DELAY = 3; // Works with 'FBDIV_SEL = 39', above

`else  /* !DDR_FREQ_MHZ */
  // So 27.0 MHz divided by 4, then x29 = 195.75 MHz.
  localparam DDR_FREQ_MHZ = 100;
  localparam CLK_IDIV_SEL = 3;
  localparam CLK_FBDV_SEL = 28;
  localparam CLK_ODIV_SEL = 4;
  localparam CLK_SDIV_SEL = 2;

  localparam CLOCK_SHIFT = 2'b11;
  localparam WRITE_DELAY = 2'b01;
  localparam PHY_WR_DELAY = 3;
  localparam PHY_RD_DELAY = 2;

`endif  /* !DDR_FREQ_MHZ */
`else  /* !__gowin_for_the_win */
  //
  // Uses simulation-only clocks, and a "generic" DDR3 PHY
  //
  localparam DDR_FREQ_MHZ = 125;

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

  // Data-path widths
  localparam DDR_DQ_WIDTH = 16;
  localparam DSB = DDR_DQ_WIDTH - 1;

  localparam DDR_DM_WIDTH = 2;
  localparam QSB = DDR_DM_WIDTH - 1;

  // Address widths
  localparam DDR_ROW_BITS = 13;
  localparam RSB = DDR_ROW_BITS - 1;

  localparam DDR_COL_BITS = 10;
  localparam CSB = DDR_COL_BITS - 1;

  localparam DDR3_MASKS = DDR3_WIDTH / 8;
  localparam ESB = DDR3_MASKS - 1;

  // note: (AXI4) byte address, not burst-aligned address
  localparam ADDRS = DDR_COL_BITS + DDR_ROW_BITS + 4;
  localparam REQID = 4;

  // -- Signals -- //

  assign uart_tx = 1'b1;

  // Global signals //
  wire clock, reset, aresetn;
  wire pclk, presetn;
  wire mclk, mrst;
  wire [3:0] cbits;

  assign aresetn = ~areset;
  assign presetn = aresetn;

  localparam AXI_WIDTH = DDR3_WIDTH;
  localparam MSB = AXI_WIDTH - 1;
  localparam STROBES = AXI_WIDTH / 8;
  localparam BSB = STROBES - 1;
  localparam AXI_ADDRS = 32;
  localparam ASB = AXI_ADDRS - 1;
  localparam AXI_IDTAG = REQID;
  localparam ISB = AXI_IDTAG - 1;

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
      .ddr_clock(pclk)     // 120 MHz, PLL output, phase-shifted
  );

  // -- USB ULPI Core and AXI+APB Bridge -- //

  wire configured, high_speed, conf_event, ddr3_conf;

  assign cbits = {configured, high_speed, conf_event, ddr3_conf};

  wire io_tvalid_w, io_tready_w, io_tlast_w;
  wire [7:0] io_tdata_w;

  // AXI4 Signals to/from the Memory Controller //
  wire awvalid_w, wvalid_w, wlast_w, bready_w, arvalid_w, rready_w;
  wire awready_w, wready_w, bvalid_w, arready_w, rvalid_w, rlast_w;
  wire [ISB:0] awid_w, arid_w, bid_w, rid_w;
  wire [7:0] awlen_w, arlen_w;
  wire [1:0] awburst_w, arburst_w;
  wire [ASB:0] awaddr_w, araddr_w;
  wire [BSB:0] wstrb_w;
  wire [1:0] bresp_w, rresp_w;
  wire [MSB:0] rdata_w, wdata_w;

  usb_axi_apb_bridge #(
      .ENDPOINT1  (ENDPOINT1),
      .ENDPOINT2  (ENDPOINT2),
      .ENDPOINT3  (ENDPOINT3),
      .ENDPOINT4  (ENDPOINT4),
      .USE_EP3_IN (1),
      .USE_EP4_OUT(1),
      .DEBUG      (DEBUG)
  ) U_USB1 (
      .aresetn(aresetn),

      .usb_clock_o(clock),
      .usb_reset_o(reset),

      .ulpi_clock_i(uclk),
      .ulpi_dir_i  (ulpi_dir),
      .ulpi_nxt_i  (ulpi_nxt),
      .ulpi_stp_o  (ulpi_stp),
      .ulpi_data_io(ulpi_data),

      .configured_o(configured),
      .high_speed_o(high_speed),
      .conf_event_o(conf_event),
      .conf_value_o(),

      .blki_tvalid_i(io_tvalid_w),  // Extra 'BULK IN' EP data-path
      .blki_tready_o(io_tready_w),
      .blki_tlast_i (io_tlast_w),
      .blki_tdata_i (io_tdata_w),

      .blko_tvalid_o(io_tvalid_w),  // USB 'BULK OUT' EP data-path
      .blko_tready_i(io_tready_w),
      .blko_tlast_o (io_tlast_w),
      .blko_tdata_o (io_tdata_w),

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
      .prdata_i (16'd0),

      .aclk(mclk),  // AXI clock domain
      .arst(mrst),

      .awvalid_o(awvalid_w),
      .awready_i(awready_w),
      .awaddr_o(awaddr_w),
      .awid_o(awid_w),
      .awlen_o(awlen_w),
      .awburst_o(awburst_w),

      .wvalid_o(wvalid_w),
      .wready_i(wready_w),
      .wlast_o (wlast_w),
      .wstrb_o (wstrb_w),
      .wdata_o (wdata_w),

      .bvalid_i(bvalid_w),
      .bready_o(bready_w),
      .bresp_i(bresp_w),
      .bid_i(bid_w),

      .arvalid_o(arvalid_w),
      .arready_i(arready_w),
      .araddr_o(araddr_w),
      .arid_o(arid_w),
      .arlen_o(arlen_w),
      .arburst_o(arburst_w),

      .rvalid_i(rvalid_w),
      .rready_o(rready_w),
      .rlast_i(rlast_w),
      .rresp_i(rresp_w),
      .rid_i(rid_w),
      .rdata_i(rdata_w)
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
  wire [ESB:0] dfi_mask;
  wire [MSB:0] dfi_wdata, dfi_rdata;

  wire dfi_calib, dfi_align;
  wire [2:0] dfi_shift;

  wire clk_x2, mlock;

  assign #500000 mrst = ~mlock;

`ifdef __spanner_montana

  reg mem_clk_125 = 1;
  reg mem_clk_250 = 0;
  reg mem_clk_rdy = 0;

  assign mclk = mem_clk_rdy ? mem_clk_125 : 1'b0;
  assign clk_x2 = mem_clk_rdy ? mem_clk_250 : 1'b0;
  assign #360 mlock = mem_clk_rdy;

  always #5.0 mem_clk_125 <= ~mem_clk_125;
  always #2.5 mem_clk_250 <= ~mem_clk_250;

  always @(posedge clk_26 or negedge rst_n) begin
    if (!rst_n) begin
      mem_clk_rdy <= 1'b0;
    end else begin
      mem_clk_rdy <= #49948 1'b1;
    end
  end

`else  /* !__spanner_montana */
`ifdef __gowin_for_the_win

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
      .clockp(),
      .lock  (mlock),
      .clkin (clk_26),
      .reset (~rst_n)
  );

`endif  /* __gowin_for_the_win */
`endif  /* !__spanner_montana */

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
      .axi_awaddr_i(awaddr_w[ADDRS-1:0]),
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
      .axi_araddr_i(araddr_w[ADDRS-1:0]),
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
      .clock  (mclk),
      .reset  (mrst),
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
      .DDR3_WIDTH(DDR3_NPINS),   // (default)
      .ADDR_BITS (DDR_ROW_BITS)  // default: 14
  ) U_PHY1 (
      .clock  (mclk),
      .reset  (mrst),
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
