`timescale 1ns / 100ps
`define __gowin_for_the_win
module ddr3_top #(
    parameter SRAM_BYTES = 2048,
    parameter DATA_WIDTH = 32,

    parameter TELEMETRY = 1,
    parameter TELE_UART = 1,

    // Trims an additional clock-cycle of latency, if '1'
    parameter LOW_LATENCY = 1'b0,  // 0 or 1
    parameter WR_PREFETCH = 1'b0   // 0 or 1
) (
    input clk_26,
    input arst_n,  // 'S2' button for async-reset

    input bus_clock,
    input bus_reset,

    // Debug UART signals [optional]
    input  send_ni,
    input  uart_rx_i,
    output uart_tx_o,

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

  // Settings for DLL=off mode
  parameter DDR_CL = 6;
  parameter DDR_CWL = 6;

`ifdef __gowin_for_the_win
  localparam PHY_WR_DELAY = 3;
  localparam PHY_RD_DELAY = 3;
`else  /* !__gowin_for_the_win */
  localparam PHY_WR_DELAY = 1;
  localparam PHY_RD_DELAY = 1;
`endif  /* !__gowin_for_the_win */

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
  wire awvalid, wvalid, wlast, bready, arvalid, rready;
  wire awready, wready, bvalid, arready, rvalid, rlast;
  wire [ISB:0] awid, arid, bid, rid;
  wire [7:0] awlen, arlen;
  wire [1:0] awburst, arburst;
  wire [ASB:0] awaddr, araddr;
  wire [BSB:0] wstrb;
  wire [1:0] bresp, rresp;
  wire [MSB:0] rdata, wdata;

  // DFI <-> PHY
  wire dfi_rst_n, dfi_cke, dfi_cs_n, dfi_ras_n, dfi_cas_n, dfi_we_n;
  wire dfi_odt, dfi_wstb, dfi_wren, dfi_rden, dfi_valid, dfi_last;
  wire [  2:0] dfi_bank;
  wire [RSB:0] dfi_addr;
  wire [BSB:0] dfi_mask;
  wire [MSB:0] dfi_wdata, dfi_rdata;

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

  always #2.5 dclk <= ~dclk;
  always #5.0 mclk <= ~mclk;
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
      .clkin (clk_26)
  );

`endif  /* !__icarus */

  assign ddr_clock_o = clock;
  assign ddr_reset_o = reset;

  assign ddr_clk = clk_200;
  assign clock = clk_100;
  assign reset = ~locked;

  // -- Processes & Dispatches Memory Requests -- //

  memreq #(
      .FIFO_DEPTH(SRAM_BYTES * 8 / DATA_WIDTH),
      .DATA_WIDTH(DATA_WIDTH),
      .STROBES(DATA_WIDTH / 8)
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
      .arvalid_o(arvalid),
      .arready_i(arready),
      .araddr_o(araddr),
      .arid_o(arid),
      .arlen_o(arlen),
      .arburst_o(arburst),

      .rvalid_i(rvalid),
      .rready_o(rready),
      .rlast_i(rlast),
      .rresp_i(rresp),
      .rid_i(rid),
      .rdata_i(rdata)
  );


  //
  //  DDR Core Under New Test
  ///

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
      .BYPASS_ENABLE   (0),
      .TELEMETRY       (TELEMETRY),
      .ENDPOINT        (3),
      .USE_UART        (TELE_UART),
      .USE_PACKET_FIFOS(0)
  ) U_LITE (
      .arst_n(arst_n),  // Global, asynchronous reset

      .clock(clock),  // system clock
      .reset(reset),  // synchronous reset

      .configured_o(ddr3_conf_o),

      // Debug UART signals [optional]
      .send_ni  (send_ni),
      .uart_rx_i(uart_rx_i),
      .uart_tx_o(uart_tx_o),

      .tele_select_i(1'b0),
      .tele_start_i (1'b0),
      .tele_level_o (),
      .tele_tvalid_o(),
      .tele_tready_i(1'b0),
      .tele_tlast_o (),
      .tele_tkeep_o (),
      .tele_tdata_o (),

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

      .axi_arvalid_i(arvalid),
      .axi_arready_o(arready),
      .axi_araddr_i(araddr),
      .axi_arid_i(arid),
      .axi_arlen_i(arlen),
      .axi_arburst_i(arburst),

      .axi_rvalid_o(rvalid),
      .axi_rready_i(rready),
      .axi_rlast_o(rlast),
      .axi_rresp_o(rresp),
      .axi_rid_o(rid),
      .axi_rdata_o(rdata),

      .byp_arvalid_i(1'b0),  // [optional] fast-read port
      .byp_arready_o(),
      .byp_araddr_i('bx),
      .byp_arid_i('bx),
      .byp_arlen_i('bx),
      .byp_arburst_i('bx),

      .byp_rready_i(1'b0),
      .byp_rvalid_o(),
      .byp_rlast_o(),
      .byp_rresp_o(),
      .byp_rid_o(),
      .byp_rdata_o(),

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
      .ADDR_BITS  (DDR_ROW_BITS)
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
