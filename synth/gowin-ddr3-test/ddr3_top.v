`timescale 1ns / 100ps
// Comment this out to speed up Icarus Verilog simulations
`define __gowin_for_the_win

`ifndef __icarus
// Slower simulation performance, as the IOB's have to be simulated
`define __gowin_for_the_win
`endif  /* !__icarus */
module ddr3_top #(
<<<<<<< Updated upstream
    parameter SRAM_BYTES = 2048,
    parameter DATA_WIDTH = 32,
    parameter DATA_FIFO_BYPASS = 0,
=======
    parameter SRAM_BYTES   = 2048,
    parameter DATA_WIDTH   = 32,
    parameter DFIFO_BYPASS = 0,

    // Default clock-setup for 125 MHz DDR3 clock, from 27 MHz source
    parameter CLK_IN_FREQ = "27",
    parameter CLK_IDIV_SEL = 3,  // in  / 4
    parameter CLK_FBDV_SEL = 36,  //     x37
    parameter CLK_ODIV_SEL = 4,  // out / 4 (x2 DDR3 clock)
    parameter CLK_SDIV_SEL = 2,  //     / 2
    parameter DDR_FREQ_MHZ = 125,  // out: 249.75 / 2 MHz
>>>>>>> Stashed changes

    // Settings for DLL=off mode
    parameter DDR_CL = 6,
    parameter DDR_CWL = 6,
    parameter PHY_WR_DELAY = 3,
    parameter PHY_RD_DELAY = 3,

    // Trims an additional clock-cycle of latency, if '1'
<<<<<<< Updated upstream
    parameter LOW_LATENCY = 1'b0,   // 0 or 1
    parameter WR_PREFETCH = 1'b0,   // 0 or 1
    parameter RD_FASTPATH = 1'b0,   // 0 or 1
    parameter INVERT_MCLK = 0,
    parameter INVERT_DCLK = 0,
=======
    parameter LOW_LATENCY = 1'b0,  // 0 or 1
    parameter WR_PREFETCH = 1'b0,  // 0 or 1
    parameter RD_FASTPATH = 1'b0,  // 0 or 1
    parameter RD_PORTSWAP = 1'b0,  // 0 or 1
    parameter INVERT_MCLK = 0,  // Todo: unfinished, and to allow extra shifts
    parameter INVERT_DCLK = 0,  // Todo: unfinished, and to allow extra shifts
>>>>>>> Stashed changes
    parameter WRITE_DELAY = 2'b00,
    parameter CLOCK_SHIFT = 2'b10
) (
    input clk_26,
    input arst_n,  // 'S2' button for async-reset

    input bus_clock,
    input bus_reset,

    output ddr3_conf_o,
    output ddr_clock_o,
    output ddr_reset_o,

    // From USB or SPI
    input s_tvalid,
    output s_tready,
    input s_tkeep,
    input s_tlast,
    input [7:0] s_tdata,

    // To USB or SPI
    output m_tvalid,
    input m_tready,
    output m_tkeep,
    output m_tlast,
    output [7:0] m_tdata,

    // Fast-reads port [AXI4, optional]
    input byp_arvalid_i,  // AXI4 Read-Address channel
    output byp_arready_o,
    input [ASB:0] byp_araddr_i,
    input [ISB:0] byp_arid_i,
    input [7:0] byp_arlen_i,
    input [1:0] byp_arburst_i,

    input byp_rready_i,  // AXI4 Read-Data channel
    output byp_rvalid_o,
    output byp_rlast_o,
    output [1:0] byp_rresp_o,
    output [ISB:0] byp_rid_o,
    output [MSB:0] byp_rdata_o,

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

  localparam DDR_FREQ_MHZ = 100;

  localparam IDIV_SEL = 3;
  localparam FBDIV_SEL = 28;
  localparam ODIV_SEL = 4;
  localparam SDIV_SEL = 2;

  // -- Constants -- //

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

  localparam WIDTH = 32;
  localparam MSB = WIDTH - 1;
  localparam MASKS = WIDTH / 8;
  localparam BSB = MASKS - 1;

  // note: (AXI4) byte address, not burst-aligned address
  localparam ADDRS = DDR_COL_BITS + DDR_ROW_BITS + 4;
  localparam ASB = ADDRS - 1;

  localparam REQID = 4;
  localparam ISB = REQID - 1;


  // -- DDR3 Core and AXI Interconnect Signals -- //

  // AXI4 Signals to/from the Memory Controller
  wire awvalid, wvalid, wlast, bready, arvalid_w, rready_w;
  wire awready, wready, bvalid, arready_w, rvalid_w, rlast_w;
  wire [ISB:0] awid, arid_w, bid, rid_w;
  wire [7:0] awlen, arlen_w;
  wire [1:0] awburst, arburst_w;
  wire [ASB:0] awaddr, araddr_w;
  wire [BSB:0] wstrb;
  wire [1:0] bresp, rresp_w;
  wire [MSB:0] rdata_w, wdata;

  // DFI <-> PHY
  wire dfi_rst_n, dfi_cke, dfi_cs_n, dfi_ras_n, dfi_cas_n, dfi_we_n;
  wire dfi_odt, dfi_wstb, dfi_wren, dfi_rden, dfi_valid, dfi_last;
  wire [  2:0] dfi_bank;
  wire [RSB:0] dfi_addr;
  wire [BSB:0] dfi_mask;
  wire [MSB:0] dfi_wdata, dfi_rdata;

  wire dfi_calib, dfi_align;
  wire [2:0] dfi_shift;

  wire clk_200, clk_100, locked;
  wire ddr_clk, clock, reset;

  // TODO: set up this clock, as the DDR3 timings are quite fussy ...

`ifdef __icarus
  //
  //  Simulation-Only Clocks & Resets
  ///
  reg dclk = 1, mclk = 0, lock_q = 0;

  assign clk_200 = dclk;
  assign clk_100 = mclk;
  assign locked  = lock_q;

<<<<<<< Updated upstream
  always #2.5 dclk <= ~dclk;
  always #5.0 mclk <= ~mclk;
=======
  always #QCLK_DELAY dclk <= ~dclk;
  always #HCLK_DELAY mclk <= ~mclk;
>>>>>>> Stashed changes
  initial #20 lock_q = 0;

  always @(posedge mclk or negedge arst_n) begin
    if (!arst_n) begin
      lock_q <= 1'b0;
    end else begin
      lock_q <= #100000 1'b1;
    end
  end

`else  /* !__icarus */

  // So 27.0 MHz divided by 4, then x29 = 195.75 MHz.
  gw2a_rpll #(
      .FCLKIN("27"),
      .IDIV_SEL(IDIV_SEL),
      .FBDIV_SEL(FBDIV_SEL),
      .ODIV_SEL(ODIV_SEL),
      .DYN_SDIV_SEL(SDIV_SEL)
  ) U_rPLL1 (
      .clkout(clk_200),  // 200 MHz
      .clockd(clk_100),  // 100 MHz
      .lock  (locked),
      .clkin (clk_26),
      .reset (~arst_n)
  );

`endif  /* !__icarus */

  assign ddr_clock_o = clock;
  assign ddr_reset_o = reset;

  assign ddr_clk = clk_200;
  assign clock = clk_100;
  assign reset = ~locked;

  // -- Processes & Dispatches Memory Requests -- //

  wire mr_arvalid, mr_arready, mr_rvalid, mr_rready, mr_rlast;
  wire [ISB:0] mr_arid, mr_rid;
  wire [7:0] mr_arlen;
  wire [1:0] mr_arburst, mr_rresp;
  wire [ASB:0] mr_araddr;
  wire [MSB:0] mr_rdata;

  memreq #(
      .FIFO_DEPTH(SRAM_BYTES * 8 / DATA_WIDTH),
      .DATA_WIDTH(DATA_WIDTH),
      .STROBES(DATA_WIDTH / 8),
      .WR_FRAME_FIFO(1)
  ) U_MEMREQ1 (
      .mem_clock(clock),  // DDR3 controller domain
      .mem_reset(reset),

      .bus_clock(bus_clock),  // SPI or USB domain
      .bus_reset(bus_reset),

      // From USB or SPI
      .s_tvalid(s_tvalid),
      .s_tready(s_tready),
      .s_tkeep (s_tkeep),
      .s_tlast (s_tlast),
      .s_tdata (s_tdata),

      // To USB or SPI
      .m_tvalid(m_tvalid),
      .m_tready(m_tready),
      .m_tkeep (m_tkeep),
      .m_tlast (m_tlast),
      .m_tdata (m_tdata),

      // Write -address(), -data(), & -response ports(), to/from DDR3 controller
      .awvalid_o(awvalid),
      .awready_i(awready),
      .awaddr_o(awaddr),
      .awid_o(awid),
      .awlen_o(awlen),
      .awburst_o(awburst),

      .wvalid_o(wvalid),
      .wready_i(wready),
      .wlast_o (wlast),
      .wstrb_o (wstrb),
      .wdata_o (wdata),

      .bvalid_i(bvalid),
      .bready_o(bready),
      .bresp_i(bresp),
      .bid_i(bid),

      // Read -address & -data ports(), to/from the DDR3 controller
      .arvalid_o(mr_arvalid),
      .arready_i(mr_arready),
      .araddr_o(mr_araddr),
      .arid_o(mr_arid),
      .arlen_o(mr_arlen),
      .arburst_o(mr_arburst),

      .rvalid_i(mr_rvalid),
      .rready_o(mr_rready),
      .rlast_i(mr_rlast),
      .rresp_i(mr_rresp),
      .rid_i(mr_rid),
      .rdata_i(mr_rdata)
  );


  //
  //  DDR Core Under New Test
  ///

  wire [QSB:0] dfi_dqs_p, dfi_dqs_n;
  wire [1:0] dfi_wrdly;
  wire [2:0] dfi_rddly;

<<<<<<< Updated upstream
  wire crvalid, crready, cvalid, cready, clast;
  wire [1:0] crburst, cresp;
  wire [7:0] crlen;
  wire [ASB:0] craddr;
  wire [ISB:0] crid, cid;
  wire [MSB:0] cdata;

  wire arvalid, arready, rvalid, rready, rlast;
  wire [1:0] arburst, rresp;
  wire [7:0] arlen;
  wire [ASB:0] araddr;
  wire [ISB:0] arid, rid;
  wire [MSB:0] rdata;

  assign crvalid = BYPASS_ENABLE ? arvalid_w : 1'b0;
  assign crid    = BYPASS_ENABLE ? arid_w : {REQID{1'bx}};
  assign crlen   = BYPASS_ENABLE ? arlen_w : 8'bx;
  assign crburst = BYPASS_ENABLE ? arburst_w : 2'bx;
  assign craddr  = BYPASS_ENABLE ? araddr_w : {ADDRS{1'bx}};

  assign arvalid = BYPASS_ENABLE ? 1'b0 : arvalid_w;
  assign arid    = BYPASS_ENABLE ? {REQID{1'bx}} : arid_w;
  assign arlen   = BYPASS_ENABLE ? 8'bx : arlen_w;
  assign arburst = BYPASS_ENABLE ? 2'bx : arburst_w;
  assign araddr  = BYPASS_ENABLE ? {ADDRS{1'bx}} : araddr_w;

  assign arready_w = BYPASS_ENABLE ? crready : arready;

  assign rready  = BYPASS_ENABLE ? 1'b0 : rready_w;
  assign cready  = BYPASS_ENABLE ? rready_w : 1'b0;
=======
  //
  // Select the source & destination channels for the bypass port
  //
  // Notes:
  //  - Switches between the mem-req vs bypass ports;
  //  - This can also be used to connect the AXI4 read-channels directly to the
  //    DDR3 controller;
  //

  wire rd_arvalid, rd_arready, rd_rvalid, rd_rready, rd_rlast;
  wire [ISB:0] rd_arid, rd_rid;
  wire [7:0] rd_arlen;
  wire [1:0] rd_arburst, rd_rresp;
  wire [ASB:0] rd_araddr;
  wire [MSB:0] rd_rdata;

  wire by_arvalid, by_arready, by_rvalid, by_rready, by_rlast;
  wire [ISB:0] by_arid, by_rid;
  wire [7:0] by_arlen;
  wire [1:0] by_arburst, by_rresp;
  wire [ASB:0] by_araddr;
  wire [MSB:0] by_rdata;

  // 'Bypass' MUX-output intermediate signals
  wire byvalid, byready, bxvalid, bxready, bxlast;
  wire [1:0] byburst, bxresp;
  wire [  7:0] bylen;
  wire [ASB:0] byaddr;
  wire [ISB:0] byid, bxid;
  wire [MSB:0] bxdata;

  // 'Bypass' Read-Address channel MUX, to the AXI DDR3 controller
  assign byvalid       = RD_PORTSWAP ? mr_arvalid : byp_arvalid_i;
  assign byready       = RD_PORTSWAP ? rd_arready : by_arready;
  assign byid          = RD_PORTSWAP ? mr_arid : byp_arid_i;
  assign bylen         = RD_PORTSWAP ? mr_arlen : byp_arlen_i;
  assign byburst       = RD_PORTSWAP ? mr_arburst : byp_arburst_i;
  assign byaddr        = RD_PORTSWAP ? mr_araddr : byp_araddr_i;

  // Read-Address enable/disable, for the 'bypass' port
  assign by_arvalid    = RD_FASTPATH ? byvalid : 1'b0;
  assign by_arid       = RD_FASTPATH ? byid : {REQID{1'bx}};
  assign by_arlen      = RD_FASTPATH ? bylen : 8'bx;
  assign by_arburst    = RD_FASTPATH ? byburst : 2'bx;
  assign by_araddr     = RD_FASTPATH ? byaddr : {ADDRS{1'bx}};
  assign by_rready     = RD_FASTPATH ? bxready : 1'b0;

  // 'Bypass' Read-Data channel MUX, out of this ('ddr3_top') module
  assign bxvalid       = RD_PORTSWAP ? rd_rvalid : by_rvalid;
  assign bxready       = RD_PORTSWAP ? mr_rready : byp_rready_i;
  assign bxlast        = RD_PORTSWAP ? rd_rlast : by_rlast;
  assign bxresp        = RD_PORTSWAP ? rd_rresp : by_rresp;
  assign bxid          = RD_PORTSWAP ? rd_rid : by_rid;
  assign bxdata        = RD_PORTSWAP ? rd_rdata : by_rdata;

  // 'Bypass' response-enable signals, for this ('ddr3_top') module
  assign byp_arready_o = RD_FASTPATH ? byready : 1'b0;
  assign byp_rvalid_o  = RD_FASTPATH ? bxvalid : 1'b0;
  assign byp_rlast_o   = RD_FASTPATH ? bxlast : 1'b0;
  assign byp_rresp_o   = RD_FASTPATH ? bxresp : 2'bx;
  assign byp_rid_o     = RD_FASTPATH ? bxid : {REQID{1'bx}};
  assign byp_rdata_o   = RD_FASTPATH ? bxdata : {DATA_WIDTH{1'bx}};

  // Select the Read-Address channel source for the AXI DDR3 controller
  assign rd_arvalid    = RD_PORTSWAP ? byp_arvalid_i : mr_arvalid;
  assign rd_arid       = RD_PORTSWAP ? byp_arid_i : mr_arid;
  assign rd_arlen      = RD_PORTSWAP ? byp_arlen_i : mr_arlen;
  assign rd_arburst    = RD_PORTSWAP ? byp_arburst_i : mr_arburst;
  assign rd_araddr     = RD_PORTSWAP ? byp_araddr_i : mr_araddr;
  assign rd_rready     = RD_PORTSWAP ? byp_rready_i : mr_rready;

  // Read-Address and Read-Data responses to the memory-request ('memreq')
  // functional unit
  assign mr_arready    = RD_PORTSWAP ? by_arready : rd_arready;
  assign mr_rvalid     = RD_PORTSWAP ? by_rvalid : rd_rvalid;
  assign mr_rlast      = RD_PORTSWAP ? by_rlast : rd_rlast;
  assign mr_rresp      = RD_PORTSWAP ? by_rresp : rd_rresp;
  assign mr_rid        = RD_PORTSWAP ? by_rid : rd_rid;
  assign mr_rdata      = RD_PORTSWAP ? by_rdata : rd_rdata;
>>>>>>> Stashed changes

  axi_ddr3_lite #(
      .DDR_FREQ_MHZ    (DDR_FREQ_MHZ),
      .DDR_ROW_BITS    (DDR_ROW_BITS),
      .DDR_COL_BITS    (DDR_COL_BITS),
      .DDR_DQ_WIDTH    (DDR_DQ_WIDTH),
      .PHY_WR_DELAY    (PHY_WR_DELAY),
      .PHY_RD_DELAY    (PHY_RD_DELAY),
      .WR_PREFETCH     (WR_PREFETCH),
      .LOW_LATENCY     (LOW_LATENCY),
      .AXI_ID_WIDTH    (REQID),
      .MEM_ID_WIDTH    (REQID),
<<<<<<< Updated upstream
      .DATA_FIFO_BYPASS(DATA_FIFO_BYPASS),
      .BYPASS_ENABLE   (BYPASS_ENABLE),
=======
      .DFIFO_BYPASS    (DFIFO_BYPASS),
      .BYPASS_ENABLE   (RD_FASTPATH),
>>>>>>> Stashed changes
      .USE_PACKET_FIFOS(0)
  ) U_LITE (
      .arst_n(arst_n),  // Global, asynchronous reset

      .clock(clock),  // system clock
      .reset(reset),  // synchronous reset

      .configured_o(ddr3_conf_o),

      // Write Channels
      .axi_awvalid_i(awvalid),
      .axi_awready_o(awready),
      .axi_awaddr_i(awaddr),
      .axi_awid_i(awid),
      .axi_awlen_i(awlen),
      .axi_awburst_i(awburst),

      .axi_wvalid_i(wvalid),
      .axi_wready_o(wready),
      .axi_wlast_i (wlast),
      .axi_wstrb_i (wstrb),
      .axi_wdata_i (wdata),

      .axi_bvalid_o(bvalid),
      .axi_bready_i(bready),
      .axi_bresp_o(bresp),
      .axi_bid_o(bid),

      // Standard Read-Channels
      .axi_arvalid_i(rd_arvalid),
      .axi_arready_o(rd_arready),
      .axi_araddr_i(rd_araddr),
      .axi_arid_i(rd_arid),
      .axi_arlen_i(rd_arlen),
      .axi_arburst_i(rd_arburst),

      .axi_rvalid_o(rd_rvalid),
      .axi_rready_i(rd_rready),
      .axi_rlast_o(rd_rlast),
      .axi_rresp_o(rd_rresp),
      .axi_rid_o(rd_rid),
      .axi_rdata_o(rd_rdata),

      // Fast-read channels [optional]
      .byp_arvalid_i(by_arvalid),
      .byp_arready_o(by_arready),
      .byp_araddr_i(by_araddr),
      .byp_arid_i(by_arid),
      .byp_arlen_i(by_arlen),
      .byp_arburst_i(by_arburst),

      .byp_rvalid_o(by_rvalid),
      .byp_rready_i(by_rready),
      .byp_rlast_o(by_rlast),
      .byp_rresp_o(by_rresp),
      .byp_rid_o(by_rid),
      .byp_rdata_o(by_rdata),

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
      .DDR3_WIDTH (16),
      .ADDR_BITS  (DDR_ROW_BITS),
      .INVERT_MCLK(INVERT_MCLK),
      .INVERT_DCLK(INVERT_DCLK),
      .WRITE_DELAY(WRITE_DELAY),
      .CLOCK_SHIFT(CLOCK_SHIFT)
  ) U_PHY1 (
      .clock  (clock),
      .reset  (reset),
      .clk_ddr(ddr_clk),

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

  // Generic PHY -- that probably won't synthesise correctly, due to how the
  // (read-)data is registered ...
  generic_ddr3_phy #(
      .DDR3_WIDTH(16),  // (default)
      .ADDR_BITS(DDR_ROW_BITS)  // default: 14
  ) U_PHY1 (
      .clock  (clock),
      .reset  (reset),
      .clk_ddr(ddr_clk),

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


endmodule  /* ddr3_top */
