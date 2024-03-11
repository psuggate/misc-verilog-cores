`timescale 1ns / 100ps
module usb_demo_top (
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

  // -- Constants -- //

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

  // USB-core configuration
  localparam integer PIPELINED = 1;
  localparam integer HIGH_SPEED = 1;  // Note: USB FS (Full-Speed) not supported
  localparam integer ULPI_DDR_MODE = 0;  // todo: '1' is fiddly to implement ...
  localparam integer ENDPOINT1 = 1;
  localparam integer ENDPOINT2 = 2;

  // USB BULK IN/OUT SRAM parameters
  parameter USE_SYNC_FIFO = 0;
  localparam integer FIFO_LEVEL_BITS = USE_SYNC_FIFO ? 11 : 12;
  localparam integer FSB = FIFO_LEVEL_BITS - 1;
  localparam integer BULK_FIFO_SIZE = 2048;

  // USB UART settings
  localparam [15:0] UART_PRESCALE = 16'd33;  // For: 60.0 MHz / (230400 * 8)
  // localparam [15:0] UART_PRESCALE = 16'd65;  // For: 60.0 MHz / (115200 * 8)
  // localparam [15:0] UART_PRESCALE = 16'd781;  // For: 60.0 MHz / (9600 * 8)


  // -- Signals -- //

  // Global signals //
  wire clock, reset;
  wire [3:0] cbits;

  // Local Signals //
  wire usb_sof_w, configured, blk_cycle_w;
  wire blk_fetch_w, blk_store_w;
  wire [3:0] blk_endpt_w;

  // Data-path //
  wire s_tvalid, s_tready, s_tlast, s_tkeep;
  wire m_tvalid, m_tready, m_tlast, m_tkeep;
  wire [7:0] s_tdata, m_tdata;

  // FIFO state //
  wire [FSB:0] level_w;
  reg bulk_in_ready_q, bulk_out_ready_q;


  // -- LEDs Stuffs -- //

  // Note: only 4 (of 6) LED's available in default config
  assign leds = {~cbits[3:0], 2'b11};
  assign cbits = phy_state_w;


  // -- ULPI Core and BULK IN/OUT SRAM -- //

  assign s_tkeep = s_tvalid;

  always @(posedge clock) begin
    if (reset) begin
      bulk_in_ready_q  <= 1'b0;
      bulk_out_ready_q <= 1'b0;
    end else begin
      bulk_in_ready_q  <= configured && level_w > 4;
      bulk_out_ready_q <= configured && level_w < 1024;
    end
  end


  //
  // Core Under New Tests
  ///
  usb_ulpi_wrapper #(
      .DEBUG(1)
  ) U_USB1 (
      .clk_26(clk_26),
      .rst_n (rst_n),

      // USB ULPI pins on the dev-board
      .ulpi_clk (ulpi_clk),
      .ulpi_rst (ulpi_rst),
      .ulpi_dir (ulpi_dir),
      .ulpi_nxt (ulpi_nxt),
      .ulpi_stp (ulpi_stp),
      .ulpi_data(ulpi_data),

      // Debug UART signals
      .send_ni  (send_n),
      .uart_rx_i(uart_rx),
      .uart_tx_o(uart_tx),

      .configured_o(configured),
      .status_o(cbits),

      // Same clock-domain as the AXI4-Stream ports
      .usb_clk_o(clock),
      .usb_rst_o(reset),

      // USB BULK endpoint #1 //
      .ep1_in_ready_i (bulk_in_ready_q),
      .ep1_out_ready_i(bulk_out_ready_q),

      .m1_tvalid(m_tvalid),
      .m1_tready(m_tready),
      .m1_tlast (m_tlast),
      .m1_tkeep (m_tkeep),
      .m1_tdata (m_tdata),

      .s1_tvalid(s_tvalid),
      .s1_tready(s_tready),
      .s1_tlast (s_tlast),
      .s1_tkeep (s_tkeep),
      .s1_tdata (s_tdata),

      // USB BULK endpoint #2 //
      .ep2_in_ready_i (1'b0),
      .ep2_out_ready_i(1'b0),

      .m2_tvalid(),
      .m2_tready(1'b0),
      .m2_tlast (),
      .m2_tkeep (),
      .m2_tdata (),

      .s2_tvalid(1'b0),
      .s2_tready(),
      .s2_tlast (1'b0),
      .s2_tkeep (1'b0),
      .s2_tdata ('bx)
  );


  //
  //  DDR3 Cores Under Next-generation Tests
  ///

  // -- Constants -- //

  // Settings for DLL=off mode
  parameter DDR_CL = 6;
  parameter DDR_CWL = 6;

  localparam PHY_WR_DELAY = 3;
  localparam PHY_RD_DELAY = 3;
  localparam WR_PREFETCH = 1'b1;

  // Trims an additional clock-cycle of latency, if '1'
  parameter LOW_LATENCY = 1'b0;  // 0 or 1

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


  // `define __use_ddr3_core
`ifndef __use_ddr3_core

  // Just set these signals in order to configure the IOBs of the FPGA.
  assign dfi_rst_n = 1'b0;
  assign dfi_cke   = 1'b0;
  assign dfi_cs_n  = 1'b1;
  assign dfi_ras_n = 1'b1;
  assign dfi_cas_n = 1'b1;
  assign dfi_we_n  = 1'b1;
  assign dfi_odt   = 1'b0;
  assign dfi_bank  = 3'b111;
  assign dfi_addr  = 13'h1fff;
  assign dfi_wstb  = 1'b0;
  assign dfi_wren  = 1'b0;
  assign dfi_mask  = 2'b00;
  assign dfi_wdata = 16'hffff;
  assign dfi_rden  = 1'b0;


  // -- Loop-back FIFO for Testing -- //

  generate
    if (USE_SYNC_FIFO) begin : g_sync_fifo

      sync_fifo #(
          .WIDTH (9),
          .ABITS (FIFO_LEVEL_BITS),
          .OUTREG(3)
      ) U_BULK_FIFO0 (
          .clock(clock),
          .reset(reset),

          .level_o(level_w),

          .valid_i(s_tvalid),
          .ready_o(s_tready),
          .data_i ({s_tlast, s_tdata}),

          .valid_o(m_tvalid),
          .ready_i(m_tready),
          .data_o ({m_tlast, m_tdata})
      );

    end else begin : g_axis_fifo

      axis_fifo #(
          .DEPTH(BULK_FIFO_SIZE),
          .DATA_WIDTH(8),
          .KEEP_ENABLE(0),
          .KEEP_WIDTH(1),
          .LAST_ENABLE(1),
          .ID_ENABLE(0),
          .ID_WIDTH(1),
          .DEST_ENABLE(0),
          .DEST_WIDTH(1),
          .USER_ENABLE(0),
          .USER_WIDTH(1),
          .RAM_PIPELINE(1),
          .OUTPUT_FIFO_ENABLE(0),
          .FRAME_FIFO(0),
          .USER_BAD_FRAME_VALUE(0),
          .USER_BAD_FRAME_MASK(0),
          .DROP_BAD_FRAME(0),
          .DROP_WHEN_FULL(0)
      ) U_BULK_FIFO1 (
          .clk(clock),
          .rst(reset),

          .s_axis_tvalid(s_tvalid),  // AXI4-Stream input
          .s_axis_tready(s_tready),
          .s_axis_tlast (s_tlast),
          .s_axis_tid   (1'b0),
          .s_axis_tdest (1'b0),
          .s_axis_tuser (1'b0),
          .s_axis_tkeep (1'b1),
          .s_axis_tdata (s_tdata),

          .pause_req(1'b0),

          .m_axis_tvalid(m_tvalid),  // AXI4-Stream output
          .m_axis_tready(m_tready),
          .m_axis_tlast(m_tlast),
          .m_axis_tid(),
          .m_axis_tdest(),
          .m_axis_tuser(),
          .m_axis_tkeep(),
          .m_axis_tdata(m_tdata),

          .status_depth(level_w),  // Status
          .status_overflow(),
          .status_bad_frame(),
          .status_good_frame()
      );

    end
  endgenerate

`else

  // -- DDR3 Core and AXI Interconnect Signals -- //

  wire ddr3_conf;

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


  // `define __use_250_MHz
`ifdef __use_250_MHz
  localparam DDR_FREQ_MHZ = 125;

  localparam IDIV_SEL = 3;
  localparam FBDIV_SEL = 36;
  localparam ODIV_SEL = 4;
  localparam SDIV_SEL = 2;
`else
  localparam DDR_FREQ_MHZ = 100;

  localparam IDIV_SEL = 3;
  localparam FBDIV_SEL = 28;
  localparam ODIV_SEL = 4;
  localparam SDIV_SEL = 2;
`endif


  /*
  // TODO: set up this clock, as the DDR3 timings are quite fussy ...

  // So 27.0 MHz divided by 4, then x29 = 195.75 MHz.
  gw2a_rpll #(
      .FCLKIN("27"),
      .IDIV_SEL(IDIV_SEL),
      .FBDIV_SEL(FBDIV_SEL),
      .ODIV_SEL(ODIV_SEL),
      .DYN_SDIV_SEL(SDIV_SEL)
  ) axis_rpll_inst (
      .clkout(ddr_clk),  // 200 MHz
      .clockd(clock),    // 100 MHz
      .lock  (locked),
      .clkin (clk_26)
  );
*/


  // -- Controls the DDR3 via USB -- //

  axis_ddr3_ctrl U_DDR3_AXIS1 (
      .clock(clock),
      .reset(reset),

      .s_valid_i(cvalid),
      .s_ready_o(cready),
      .s_last_i (clast),
      .s_data_i (cdata),

      .m_valid_o(m_tvalid),
      .m_ready_i(m_tready),
      .m_last_o (m_tlast),
      .m_data_o (m_tdata),

      .awvalid_o(awvalid),
      .awready_i(awready),
      .awburst_o(awburst),
      .awlen_o(awlen),
      .awid_o(awid),
      .awaddr_o(awaddr),

      .wvalid_o(wvalid),
      .wready_i(wready),
      .wlast_o (wlast),
      .wstrb_o (wstrb),
      .wdata_o (wdata),

      .bvalid_i(bvalid),
      .bready_o(bready),
      .bid_i(bid),
      .bresp_i(bresp),

      .arvalid_o(arvalid),
      .arready_i(arready),
      .arburst_o(arburst),
      .arlen_o(arlen),
      .arid_o(arid),
      .araddr_o(araddr),

      .rvalid_i(rvalid),
      .rready_o(rready),
      .rlast_i(rlast),
      .rid_i(rid),
      .rresp_i(rresp),
      .rdata_i(rdata)
  );


  //
  //  DDR Core Under New Test
  ///
  axi_ddr3_lite #(
      .DDR_FREQ_MHZ (DDR_FREQ_MHZ),
      .DDR_ROW_BITS (DDR_ROW_BITS),
      .DDR_COL_BITS (DDR_COL_BITS),
      .DDR_DQ_WIDTH (DDR_DQ_WIDTH),
      .PHY_WR_DELAY (PHY_WR_DELAY),
      .PHY_RD_DELAY (PHY_RD_DELAY),
      .WR_PREFETCH  (WR_PREFETCH),
      .LOW_LATENCY  (LOW_LATENCY),
      .AXI_ID_WIDTH (REQID),
      .MEM_ID_WIDTH (REQID),
      .BYPASS_ENABLE(0),
      .TELEMETRY    (0)
  ) ddr_core_inst (
      .clock(clock),  // system clock
      .reset(reset),  // synchronous reset

      .configured_o(ddr3_conf),

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

`endif


  // -- DDR3 PHY -- //

  gw2a_ddr3_phy #(
      .WR_PREFETCH(WR_PREFETCH),
      .DDR3_WIDTH (16),
      .ADDR_BITS  (DDR_ROW_BITS)
  ) u_phy (
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


endmodule  // usb_demo_top
