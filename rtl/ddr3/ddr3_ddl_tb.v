`timescale 1ns / 100ps
`define __gowin_for_the_win
module ddr3_ddl_tb;

  localparam DDR_FREQ_MHZ = 100;

  // -- Simulation Settings -- //

  parameter ADDRS = 32;
  localparam ASB = ADDRS - 1;

  parameter WIDTH = 32;
  localparam MSB = WIDTH - 1;

  parameter MASKS = WIDTH / 8;
  localparam SSB = MASKS - 1;

  parameter DDR3_ROW_BITS = 13;
  localparam RSB = DDR3_ROW_BITS - 1;
  parameter DDR3_COL_BITS = 10;
  localparam CSB = DDR3_COL_BITS - 1;

  localparam DSB = WIDTH / 2 - 1;
  localparam QSB = MASKS / 2 - 1;


  // -- Constants -- //

  localparam DDR3_ACTV = 3'b011;
  localparam DDR3_READ = 3'b010;


  // -- Simulation Data -- //

  initial begin
    $dumpfile("ddr3_ddl_tb.vcd");
    $dumpvars();

    #800 $finish;  // todo ...
  end


  // -- Globals -- //

  reg osc = 1'b1;
  reg ddr = 1'b1;
  reg rst = 1'b0;

  always #5.0 osc <= ~osc;
  always #2.5 ddr <= ~ddr;

  initial begin
    rst <= 1'b1;
    #60 rst <= 1'b0;
  end


  wire locked, clock, reset;
  wire clk_ddr, clk_ddr_dqs, clk_ref;


  assign clock = osc;
  assign reset = rst | ~locked;

  assign #50 locked = 1'b1;
  assign clk_ddr = ddr;


  wire ddr_ck_p, ddr_ck_n, ddr_odt;
  wire ddr_cke, ddr_rst_n, ddr_cs_n, ddr_ras_n, ddr_cas_n, ddr_we_n;
  wire [  2:0] ddr_ba;
  wire [RSB:0] ddr_a;
  wire [QSB:0] ddr_dqs_p, ddr_dqs_n, ddr_dm;
  wire [DSB:0] ddr_dq;

  wire dfi_cke, dfi_rst_n, dfi_cs_n, dfi_ras_n, dfi_cas_n, dfi_we_n;
  wire dfi_odt, dfi_rden, dfi_wstb, dfi_wren, dfi_valid, dfi_last;
  wire [  2:0] dfi_bank;
  wire [RSB:0] dfi_addr;
  wire [SSB:0] dfi_mask;
  wire [MSB:0] dfi_rdata, dfi_wdata;

  reg en, req, seq, pre;
  reg [  2:0] cmd;
  reg [  2:0] ba;
  reg [RSB:0] ad;


  // -- Stimulus -- //

  reg [MSB:0] data;

  initial begin : STIMULATE
    ddr_actv(0, 0);
    ddr_read(0, 0);
  end  // STIMULATE


  always @(posedge clock) begin
    if (reset) begin
      req <= 1'b0;
      seq <= 1'b0;
      en  <= 1'b0;
      pre <= 1'b0;
    end else begin
      en <= 1'b1;  // todo: wait > 5 cycles (for CK to stabilise) ??
    end
  end


  // -- Module Under Test -- //

  wire rfc, rdy;

  // AXI <-> {FSM, DDL} signals
  wire wr_valid, wr_ready, wr_last;
  wire rd_valid, rd_ready, rd_last;
  wire [SSB:0] wr_mask;
  wire [MSB:0] wr_data, rd_data;

  assign dfi_rst_n = 1'b0;
  assign dfi_cke   = 1'b0;
  assign dfi_cs_n  = 1'b1;

  ddr3_ddl #(
      .DDR_FREQ_MHZ(100),
      .DDR_ROW_BITS(DDR3_ROW_BITS),
      .DDR_COL_BITS(DDR3_COL_BITS),
      .DFI_DQ_WIDTH(WIDTH)
  ) ddr3_ddl_inst (
      .clock(clock),
      .reset(reset),

      .ddr_cke_i(en),
      .ddr_cs_ni(~en),

      .ctl_req_i(req),
      .ctl_seq_i(seq),
      .ctl_rdy_o(rdy),
      .ctl_cmd_i(cmd),
      .ctl_ba_i (ba),
      .ctl_adr_i(ad),

      .mem_wvalid_i(wr_valid),
      .mem_wready_o(wr_ready),
      .mem_wlast_i (wr_last),
      .mem_wrmask_i(wr_mask),
      .mem_wrdata_i(wr_data),

      .mem_rvalid_o(rd_valid),
      .mem_rready_i(rd_ready),
      .mem_rlast_o (rd_last),
      .mem_rddata_o(rd_data),

      .dfi_ras_no(dfi_ras_n),
      .dfi_cas_no(dfi_cas_n),
      .dfi_we_no (dfi_we_n),
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


  // -- PHY for the DDR3 -- //

`ifdef __gowin_for_the_win

  // GoWin Global System Reset signal tree.
  GSR GSR ();

  gw2a_ddr3_phy #(
      .DDR3_WIDTH(WIDTH / 2),  // (default)
      .ADDR_BITS(DDR3_ROW_BITS)
  ) gw2a_ddr3_phy_inst (
      .clock  (clock),
      .reset  (reset),
      .clk_ddr(clk_ddr),

      .dfi_cke_i (dfi_cke),
      .dfi_rst_ni(dfi_rst_n),
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
      .dfi_data_o(dfi_rdata),

      .ddr_ck_po(ddr_ck_p),
      .ddr_ck_no(ddr_ck_n),
      .ddr_cke_o(ddr_cke),
      .ddr_rst_no(ddr_rst_n),
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

`else  /* !__gowin_for_the_win */

  generic_ddr3_phy #(
      .DDR3_WIDTH(WIDTH / 2),
      .DDR3_MASKS(MASKS / 2),
      .ADDR_BITS (DDR3_ROW_BITS)
  ) generic_ddr3_phy_inst (
      .clock  (clock),
      .reset  (reset),
      .clk_ddr(clk_ddr),

      .dfi_rst_ni(dfi_rst_n),
      .dfi_cke_i (dfi_cke),
      .dfi_cs_ni (dfi_cs_n),
      .dfi_ras_ni(dfi_ras_n),
      .dfi_cas_ni(dfi_cas_n),
      .dfi_we_ni (dfi_we_n),
      .dfi_odt_i (1'b0),
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

      .ddr3_ck_po(ddr_ck_p),
      .ddr3_ck_no(ddr_ck_n),
      .ddr3_rst_no(ddr_rst_n),
      .ddr3_cke_o(ddr_cke),
      .ddr3_cs_no(ddr_cs_n),
      .ddr3_ras_no(ddr_ras_n),
      .ddr3_cas_no(ddr_cas_n),
      .ddr3_we_no(ddr_we_n),
      .ddr3_odt_o(ddr_odt),
      .ddr3_ba_o(ddr_ba),
      .ddr3_a_o(ddr_a),
      .ddr3_dm_o(ddr_dm),
      .ddr3_dqs_pio(ddr_dqs_p),
      .ddr3_dqs_nio(ddr_dqs_n),
      .ddr3_dq_io(ddr_dq)
  );
`endif


  // -- Micron's DDR3 Simulation Module -- //

  ddr3 ddr3_inst (
      .ck(ddr_ck_p),
      .ck_n(ddr_ck_n),
      .rst_n(ddr_rst_n),
      .cke(ddr_cke),
      .cs_n(ddr_cs_n),
      .ras_n(ddr_ras_n),
      .cas_n(ddr_cas_n),
      .we_n(ddr_we_n),
      .ba(ddr_ba),
      .addr({1'b0, ddr_a}),
      .odt(1'b0),
      .dm_tdqs(ddr_dm),
      .tdqs_n(),
      .dqs(ddr_dqs_p),
      .dqs_n(ddr_dqs_n),
      .dq(ddr_dq)
  );


  // -- DDR3 Row ACTIVATE Command -- //

  task ddr_actv;
    input [2:0] bank;
    input [RSB:0] row;
    begin
      cmd <= DDR3_ACTV;
      req <= 1'b1;
      pre <= 1'b0;
      ba  <= bank;
      ad  <= row;

      @(posedge clock);
      while (!rdy) begin
        @(posedge clock);
      end

      req <= 1'b0;
      @(posedge clock);
    end
  endtask  // ddr_actv


  // -- DDR3 READ Command -- //

  task ddr_read;
    input [2:0] bank;
    input [CSB:0] col;
    begin
      cmd <= DDR3_READ;
      req <= 1'b1;
      pre <= 1'b0;
      ba  <= bank;
      ad  <= {4'h0, pre, col};  // todo:

      @(posedge clock);
      while (!rdy) begin
        @(posedge clock);
      end

      req <= 1'b0;
      @(posedge clock);
    end
  endtask  // ddr_read


endmodule  // ddr3_ddl_tb
