`timescale 1ns / 100ps
module gw2a_ddr3_phy_tb;

  // -- Constants -- //

  localparam WR_PREFETCH = 0; // Default value
  localparam INVERT_MCLK = 0; // Default value
  localparam INVERT_DCLK = 0; // Default value
  localparam WRITE_DELAY = 2'b01;
  localparam CLOCK_SHIFT = 2'b01;

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
  localparam SSB = MASKS - 1;

  // note: (AXI4) byte address, not burst-aligned address
  localparam ADDRS = DDR_COL_BITS + DDR_ROW_BITS + 4;
  localparam ASB = ADDRS - 1;

  // -- Globalists -- //

  reg clk_x1 = 1'b1;
  reg rst_x1 = 1'bx;
  reg clk_x2 = 1'b1;
  wire clock, reset;
  
  always #2.50 clk_x2 <= ~clk_x2;
  always #5.00 clk_x1 <= ~clk_x1;

  initial begin
    #10 rst_x1 <= 1'b1;
    #20 rst_x1 <= 1'b0;
  end

  assign clock = clk_x1;
  assign reset = rst_x1;

  // -- Simulation Data -- //

  initial begin
    $dumpfile("gw2a_ddr3_phy_tb.vcd");
    $dumpvars;

    #1600 $finish;
  end

  // -- Simulation Signals -- //

  // PHY <-> DDR3
  wire ddr_ck_p, ddr_ck_n, ddr_cke, ddr_rst_n, ddr_cs_n, ddr_odt;
  wire ddr_ras_n, ddr_cas_n, ddr_we_n;
  wire [2:0] ddr_ba;
  wire [RSB:0] ddr_a;
  wire [QSB:0] ddr_dqs_p, ddr_dqs_n, ddr_dm;
  wire [DSB:0] ddr_dq;

  // DFI <-> PHY
  wire dfi_rst_n, dfi_cke, dfi_cs_n, dfi_ras_n, dfi_cas_n, dfi_we_n;
  wire dfi_odt, dfi_wstb, dfi_wren, dfi_rden, dfi_valid, dfi_last;
  wire [  2:0] dfi_bank, dfi_rddly;
  wire [1:0] dfi_wrdly;
  wire [QSB:0] dfi_dqs_p, dfi_dqs_n;
  wire [RSB:0] dfi_addr;
  wire [SSB:0] dfi_mask;
  wire [MSB:0] dfi_wdata, dfi_rdata;

  // -- Stimulus -- //

  integer count = 0;

  assign #1 dfi_rst_n = count > 1;
  assign #1 dfi_cke   = count > 2;
  assign #1 dfi_cs_n  = count < 4;
  assign #1 dfi_ras_n = count < 5 ? 1'bx : 1'b1;
  assign #1 dfi_cas_n = count < 5 ? 1'bx : 1'b1;
  assign #1 dfi_we_n  = count < 5 ? 1'bx : 1'b1;
  assign #1 dfi_odt   = 1'b0;

  assign dfi_bank = 3'd0;
  assign dfi_addr = {DDR_ROW_BITS{1'b0}};

  assign dfi_wstb = 1'b0;
  assign dfi_wren = 1'b0;
  assign dfi_mask = {MASKS{1'b0}};
  assign dfi_rden = 1'b0;
  assign dfi_wdata = {WIDTH{1'bx}};

  always @(posedge clock) begin
    if (reset) begin
      count <= 0;
    end else begin
      count <= count + 1;
    end
  end

  reg oe_nq = 1'b0;
  reg stb_q = 1'b1;
  reg [1:0] dqs_pq = 2'bz;
  wire [1:0] U1_w, U0_w, DQS_nw, DQS_pw;

  // Start-strobe for a READ
  initial begin
    #20 @(negedge reset) oe_nq = 1'b1;
    #60 oe_nq = 1'b0; stb_q = 1'b0;
    #40 oe_nq = 1'b1; stb_q = 1'b1;
  end

  initial begin
    #10 dqs_pq = 2'bz;
    #82.5 dqs_pq = 2'd0;
    #10 dqs_pq = 2'd3;
    #5 dqs_pq = ~dqs_pq;
    #5 dqs_pq = ~dqs_pq;
    #5 dqs_pq = ~dqs_pq;
    #5 dqs_pq = ~dqs_pq;
    #5 dqs_pq = ~dqs_pq;
    #5 dqs_pq = ~dqs_pq;
    #5 dqs_pq = ~dqs_pq;
    #5 dqs_pq = 2'bz;
  end

  gw2a_ddr_iob #(
      .WRDLY(2'd1)
  ) U_DQS1 [1:0] (
      .PCLK(clk_x1),
      .FCLK(clk_x2),
      .RESET(rst_x1),
      .OEN(oe_nq),
      .SHIFT(2'd2),
      .D0(stb_q),
      .D1(~stb_q),
      .Q0(U0_w),
      .Q1(U1_w),
      .IO(DQS_pw),
      .IOB(DQS_nw)
  );

  //
  //  Cores Under Notable Tests
  ///

  // GoWin Global System Reset signal tree.
  GSR GSR (.GSRI(1'b1));

  gw2a_ddr3_phy #(
      .WR_PREFETCH(WR_PREFETCH),
      .DDR3_WIDTH (DDR_DQ_WIDTH),
      .ADDR_BITS  (DDR_ROW_BITS),
      .INVERT_MCLK(INVERT_MCLK),
      .INVERT_DCLK(INVERT_DCLK),
      .WRITE_DELAY(WRITE_DELAY),
      .CLOCK_SHIFT(CLOCK_SHIFT)
  ) U_PHY1 (
      .clock  (clk_x1),
      .reset  (rst_x1),
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
      .dfi_dqs_po(dfi_dqs_p),
      .dfi_dqs_no(dfi_dqs_n),
      .dfi_wdly_i(dfi_wrdly),  // In 1/4 clock-steps
      .dfi_rdly_i(dfi_rddly),  // In 1/4 clock-steps

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


endmodule  /* gw2a_ddr3_phy_tb */
