`timescale 1ns / 100ps
module axis_ddr3_ctrl_tb;

  // -- Simulation Settings -- //

  localparam DDR_FREQ_MHZ = 100;
  `include "ddr3_settings.vh"

  localparam DDR_ROW_BITS = 13;
  localparam RSB = DDR_ROW_BITS - 1;

  parameter DDR_COL_BITS = 10;
  localparam CSB = DDR_COL_BITS - 1;

  localparam PHY_WR_DELAY = 3;
  localparam PHY_RD_DELAY = 3;
  localparam WR_PREFETCH = 1'b0;

  // Trims an additional clock-cycle of latency, if '1'
  parameter LOW_LATENCY = 1'b1;  // 0 or 1

  // -- Data-path and address settings -- //

  localparam WIDTH = 32;
  localparam MSB = WIDTH - 1;
  localparam HSB = WIDTH / 2 - 1;

  localparam MASKS = WIDTH / 8;
  localparam SSB = MASKS - 1;
  localparam QSB = MASKS / 2 - 1;

  // note: (AXI4) byte address, not burst-aligned address
  localparam ADDRS = DDR_COL_BITS + DDR_ROW_BITS + 4;
  localparam ASB = ADDRS - 1;

  localparam REQID = 4;
  localparam ISB = REQID - 1;


  // -- Simulation Data -- //

  initial begin
    $dumpfile("axis_ddr3_ctrl_tb.vcd");
    $dumpvars;

    #80000 $finish;  // todo ...
  end


  // -- Globals -- //

  reg osc = 1'b1;
  reg ddr = 1'b1;
  reg rst = 1'b0;

  always #5.0 osc <= ~osc;
  always #2.5 ddr <= ~ddr;

  initial begin
    rst <= 1'b1;
    #200 rst <= 1'b0;
  end


  wire locked, clock, reset;
  wire clk_ddr, clk_ddr_dqs, clk_ref;

  assign #50 locked = 1'b1;
  assign clk_ddr = ddr;

  assign clock = osc;
  assign reset = rst | ~locked;


  // -- DDR3 and AXI-Stream Signals -- //

  // Used to control the AXI-S -> DDR3 transactions
  reg s_tvalid, s_tlast, m_tready;
  wire m_tvalid, s_tready, m_tlast;
  reg  [7:0] s_tdata;
  wire [7:0] m_tdata;

  // AXI4 Signals to/from the Memory Controller
  wire awvalid, wvalid, wlast, bready, arvalid, rready;
  wire awready, wready, bvalid, arready, rvalid, rlast;
  wire [ISB:0] awid, arid, bid, rid;
  wire [7:0] awlen, arlen;
  wire [1:0] awburst, arburst;
  wire [ASB:0] awaddr, araddr;
  wire [SSB:0] wstrb;
  wire [1:0] bresp, rresp;
  wire [MSB:0] rdata, wdata;

  // DFI <-> PHY
  wire dfi_rst_n, dfi_cke, dfi_cs_n, dfi_ras_n, dfi_cas_n, dfi_we_n;
  wire dfi_odt, dfi_wstb, dfi_wren, dfi_rden, dfi_valid, dfi_last;
  wire [  2:0] dfi_bank;
  wire [RSB:0] dfi_addr;
  wire [SSB:0] dfi_mask;
  wire [MSB:0] dfi_wdata, dfi_rdata;

  // PHY <-> DDR3
  wire ddr_ck_p, ddr_ck_n;
  wire ddr_rst_n, ddr_cke, ddr_cs_n, ddr_ras_n, ddr_cas_n, ddr_we_n;
  wire ddr_odt;
  wire [2:0] ddr_ba;
  wire [RSB:0] ddr_a;
  wire [QSB:0] ddr_dm, ddr_dqs_p, ddr_dqs_n;
  wire [HSB:0] ddr_dq;


  // -- Initialisation -- //

  reg [127:0] data;
  reg done;

  initial begin : Stimulus
    @(posedge clock);

    while (reset) begin
      @(posedge clock);
      s_tvalid <= 1'b0;
      s_tlast  <= 1'b0;
      m_tready <= 1'b0;
      done     <= 1'b0;
    end

    while (!s_tready || !awready || !arready) begin
      @(posedge clock);
    end

    @(posedge clock);
    @(posedge clock);

    axis_store(27'h010, 3, 6);
    $display("TB:%10t: WRITE = %x", $time, data);

    //
    // READ request
    @(posedge clock);
    while (!bvalid || !bready) begin
      @(posedge clock);
    end
    @(posedge clock);

    axis_fetch(16, 3, 3, data);
    $display("TB:%10t: READ = %x", $time, data);

    #400 @(posedge clock);
    $finish;
  end


  // -- Controls the DDR3 via USB -- //

  axis_ddr3_ctrl axdr_ctrl_inst (
      .clock(clock),
      .reset(reset),

      .s_valid_i(s_tvalid),
      .s_ready_o(s_tready),
      .s_last_i (s_tlast),
      .s_data_i (s_tdata),

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
  wire ddr3_conf;

  axi_ddr3_lite #(
      .DDR_FREQ_MHZ (DDR_FREQ_MHZ),
      .DDR_ROW_BITS (DDR_ROW_BITS),
      .DDR_COL_BITS (DDR_COL_BITS),
      .DDR_DQ_WIDTH (WIDTH / 2),
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


  // -- DDR3 PHY -- //

  // GoWin Global System Reset signal tree.
  GSR GSR ();

  gw2a_ddr3_phy #(
      .DDR3_WIDTH(16),  // (default)
      .ADDR_BITS(DDR_ROW_BITS)
  ) u_phy (
      .clock  (clock),
      .reset  (reset),
      .clk_ddr(clk_ddr),

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

      .ddr_ck_po(ddr_ck_p),
      .ddr_ck_no(ddr_ck_n),
      .ddr_rst_no(ddr_rst_n),
      .ddr_cke_o(ddr_cke),
      .ddr_cs_no(ddr_cs_n),
      .ddr_ras_no(ddr_ras_n),
      .ddr_cas_no(ddr_cas_n),
      .ddr_we_no(ddr_we_n),
      .ddr_odt_o(ddr_odt),
      .ddr_ba_o(ddr_ba),
      .ddr_a_o(ddr_a),
      .ddr_dm_o(ddr_dm),
      .ddr_dqs_pio(ddr_dqs_p),
      .ddr_dqs_nio(ddr_dqs_n),
      .ddr_dq_io(ddr_dq)
  );


  // -- DDR3 Simulation Model from Micron -- //

  ddr3 ddr3_sdram_inst (
      .rst_n(ddr_rst_n),
      .ck(ddr_ck_p),
      .ck_n(ddr_ck_n),
      .cke(ddr_cke),
      .cs_n(ddr_cs_n),
      .ras_n(ddr_ras_n),
      .cas_n(ddr_cas_n),
      .we_n(ddr_we_n),
      .dm_tdqs(ddr_dm),
      .ba(ddr_ba),
      .addr({1'b0, ddr_a}),
      .dq(ddr_dq),
      .dqs(ddr_dqs_p),
      .dqs_n(ddr_dqs_n),
      .tdqs_n(),
      .odt(ddr_odt)
  );


  //
  //  Simulation Tasks
  ///

  // -- Perform write transfer (128-bit) -- //

  task axis_store;
    input [ASB:0] addr;
    input [7:0] len;
    input [ISB:0] tid;
    begin
      integer count;
      reg [31:0] command;

      s_tvalid <= 1'b1;
      s_tlast <= 1'b0;
      m_tready <= 1'b0;
      {s_tdata, command} <= {len, 1'b1, tid, addr};
      count <= 4;

      while (!done) begin
        @(posedge clock);

        {s_tdata, command} <= {command[31:0], 8'bx};
        count <= count - 1;
        s_tlast <= count == 1;
        s_tvalid <= count > 0;
        done <= count == 0;
      end

      done <= 1'b0;
      @(posedge clock);

      count <= {22'h0, len, 2'b11};
      s_tvalid <= 1'b1;
      s_tlast <= 1'b0;
      m_tready <= 1'b1;
      s_tdata <= $urandom;

      while (!done) begin
        data <= {s_tdata, data[127:8]};
        @(posedge clock);

        s_tdata <= $urandom;
        count <= count - 1;
        s_tlast <= count == 1;
        s_tvalid <= count > 0;
        done <= count == 0;
      end

      done <= 1'b0;
      @(posedge clock);

      @(posedge clock);
    end
  endtask  // axis_store


  // -- Perform read transfer (128-bit) -- //

  task axis_fetch;
    input [ASB:0] addr;
    input [7:0] len;
    input [ISB:0] tid;
    output [127:0] data;
    begin
      integer count;
      reg [31:0] command;

      s_tvalid <= 1'b1;
      s_tlast <= 1'b0;
      m_tready <= 1'b0;
      {s_tdata, command} <= {len, 1'b0, tid, addr};
      count <= 4;

      while (!done) begin
        @(posedge clock);

        {s_tdata, command} <= {command[31:0], 8'bx};
        count <= count - 1;
        s_tlast <= count == 1;
        s_tvalid <= count > 0;
        done <= count == 0;
      end
      done <= 1'b0;
      @(posedge clock);

      count    <= {22'h0, len, 2'b11};
      m_tready <= 1'b1;
      @(posedge clock);

      while (!done) begin
        @(posedge clock);

        if (m_tvalid && m_tready) begin
          data <= {m_tdata, data[127:8]};
          count <= count - 1;
          done <= m_tlast;
          m_tready <= ~m_tlast;
        end
      end

      done <= 1'b0;
      @(posedge clock);

      @(posedge clock);
    end
  endtask  // axis_fetch


endmodule  // axis_ddr3_ctrl_tb
