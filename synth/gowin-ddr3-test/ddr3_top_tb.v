`timescale 1ns / 100ps
module ddr3_top_tb;

  localparam SRAM_BYTES = 2048;
  localparam DATA_WIDTH = 32;

  localparam [7:0] CMD_NOP = 8'h00;
  localparam [7:0] CMD_STORE = 8'h01;
  localparam [7:0] CMD_WDONE = 8'h02;
  localparam [7:0] CMD_WFAIL = 8'h03;
  localparam [7:0] CMD_FETCH = 8'h80;
  localparam [7:0] CMD_RDATA = 8'h81;
  localparam [7:0] CMD_RFAIL = 8'h82;

  reg mclk = 1;
  reg bclk = 1;
  reg rst;
  wire configured;

  reg [47:0] req = {CMD_STORE, 8'h08, 4'hA, 28'h0_20_80_F0};

  reg s_tvalid, s_tkeep, s_tlast, m_tready;
  reg [7:0] s_tdata;
  wire s_tready, m_tvalid, m_tkeep, m_tlast;
  wire [7:0] m_tdata;

  always #5 mclk <= ~mclk;
  always #8 bclk <= ~bclk;

  initial begin
    $dumpfile("ddr3_top_tb.vcd");
    $dumpvars;

    rst      <= 1'b1;
    s_tvalid <= 1'b0;
    s_tkeep  <= 1'b0;
    s_tlast  <= 1'b0;
    m_tready <= 1'b0;
    #40 rst <= 1'b0;

    #16 s_tdata <= req[47:40];
    s_tvalid <= 1'b1;
    s_tkeep  <= 1'b1;
    #16 s_tdata <= req[39:32];
    #16 s_tdata <= req[31:24];
    #16 s_tdata <= req[23:16];
    #16 s_tdata <= req[15:8];
    #16 s_tdata <= req[7:0];
    s_tlast <= 1'b1;
    #16 s_tvalid <= 1'b0;
    s_tkeep <= 1'b0;
    s_tlast <= 1'b0;

    #800 $finish;
  end


  // 1Gb DDR3 SDRAM pins
  wire ddr_ck_p, ddr_ck_n, ddr_cke, ddr_rst_n;
  wire ddr_cs_n, ddr_ras_n, ddr_cas_n, ddr_we_n, ddr_odt;
  wire [ 2:0] ddr_ba;
  wire [12:0] ddr_a;
  wire [1:0] ddr_dm, ddr_dqs_p, ddr_dqs_n;
  wire [15:0] ddr_dq;


  ddr3_top #(
      .SRAM_BYTES(SRAM_BYTES),
      .DATA_WIDTH(DATA_WIDTH),
      .LOW_LATENCY(1'b0)  // 0 or 1
  ) U_TOP1 (
      .osc_in(mclk),
      .arst_n(~rst),  // 'S2' button for async-reset

      .bus_clock(bclk),
      .bus_reset(rst),

      .ddr3_conf_o(configured),

      .s_tvalid(s_tvalid),
      .s_tready(s_tready),
      .s_tkeep (s_tkeep),
      .s_tlast (s_tlast),
      .s_tdata (s_tdata),

      .m_tvalid(m_tvalid),
      .m_tready(m_tready),
      .m_tkeep (m_tkeep),
      .m_tlast (m_tlast),
      .m_tdata (m_tdata),

      .ddr_ck(ddr_ck_p),
      .ddr_ck_n(ddr_ck_n),
      .ddr_cke(ddr_cke),
      .ddr_rst_n(ddr_rst_n),
      .ddr_cs(ddr_cs_n),
      .ddr_ras(ddr_ras_n),
      .ddr_cas(ddr_cas_n),
      .ddr_we(ddr_we_n),
      .ddr_odt(ddr_odt),
      .ddr_bank(ddr_ba),
      .ddr_addr(ddr_a),
      .ddr_dm(ddr_dm),
      .ddr_dqs(ddr_dqs_p),
      .ddr_dqs_n(ddr_dqs_n),
      .ddr_dq(ddr_dq)
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


endmodule  /* ddr3_top_tb */
