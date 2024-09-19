`timescale 1ns / 100ps
module gw2a_ddr3_phy_tb;

  // -- Constants -- //

  localparam WR_PREFETCH = 0;  // Default value
  localparam INVERT_MCLK = 0;  // Default value
  localparam INVERT_DCLK = 0;  // Default value
  localparam WRITE_DELAY = 2'b01;
  localparam CLOCK_SHIFT = 2'b00;

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
  wire [  2:0] ddr_ba;
  wire [RSB:0] ddr_a;
  wire [QSB:0] ddr_dqs_p, ddr_dqs_n, ddr_dm;
  wire [DSB:0] ddr_dq;

  // DFI <-> PHY
  wire dfi_rst_n, dfi_cke, dfi_cs_n, dfi_ras_n, dfi_cas_n, dfi_we_n;
  wire dfi_odt, dfi_wstb, dfi_wren, dfi_rden, dfi_valid, dfi_last;
  wire [2:0] dfi_bank, dfi_rddly;
  wire [  1:0] dfi_wrdly;
  wire [RSB:0] dfi_addr;
  wire [SSB:0] dfi_mask;
  wire [MSB:0] dfi_wdata, dfi_rdata;

  // -- Start-Up Stimulus -- //

  integer count = 0;

  always @(posedge clock) begin
    if (reset) begin
      count <= 0;
    end else begin
      count <= count + 1;
    end
  end

  assign #1 dfi_rst_n = count > 1;
  assign #1 dfi_cke = count > 2;
  assign #1 dfi_cs_n = count < 4;
  assign #1 dfi_ras_n = count < 5 ? 1'bx : 1'b1;
  assign #1 dfi_cas_n = count < 5 ? 1'bx : 1'b1;
  assign #1 dfi_we_n = count < 5 ? 1'bx : 1'b1;
  assign #1 dfi_odt = 1'b0;

  assign dfi_bank = 3'd0;
  assign dfi_addr = {DDR_ROW_BITS{1'b0}};

  assign dfi_wstb = 1'b0;
  assign dfi_wren = 1'b0;
  assign dfi_mask = {MASKS{1'b0}};
  assign dfi_wdata = {WIDTH{1'bx}};

  // -- Data-Capture Stimulus -- //

  reg oen_q = 1'b1, vld_q = 1'b0, rdy_q;
  reg [QSB:0] dqs_pq = 2'bz, dqs_nq = 2'bz;
  reg [DSB:0] dat_q;
  wire [QSB:0] dqs_p90, dqs_180, dqs_m90;
  wire [QSB:0] dqs_n90, dqs_360, dqs_q90;
  wire [DSB:0] dqp90_w, dq180_w, dqm90_w;

  wire vld_p90, vld_180, vld_m90;
  wire [MSB:0] dat_p90, dat_180, dat_m90;

  task send_data;
    begin
      #40 dqs_pq = 2'd0;
      oen_q = 1'b0;
      #10 dqs_pq = 2'd3;
      vld_q = 1'b1;
      #5 dqs_pq = ~dqs_pq;
      #5 dqs_pq = ~dqs_pq;
      #5 dqs_pq = ~dqs_pq;
      #5 dqs_pq = ~dqs_pq;
      #5 dqs_pq = ~dqs_pq;
      #5 dqs_pq = ~dqs_pq;
      #5 dqs_pq = ~dqs_pq;
      #5 dqs_pq = 2'bz;
      oen_q = 1'b1;
      vld_q = 1'b0;
    end
  endtask  /* send_data */

  initial begin
    #10 dqs_pq = 2'bz;
    oen_q = 1'b1;
    #52.5 dfi_align = 1'b1;

    send_data();
    send_data();
    send_data();
    send_data();
    send_data();
    send_data();
    send_data();
    send_data();
    send_data();
    send_data();
  end

  assign dfi_rden = rdy_q;  // vld_q;

  assign ddr_dqs_p = oen_q ? 2'bz : dqs_pq;
  assign ddr_dqs_n = oen_q ? 2'bz : ~dqs_pq;
  assign ddr_dq = vld_q ? dat_q : {DDR_DQ_WIDTH{1'bz}};

  assign #2.5 dqs_p90 = ddr_dqs_p;
  assign #2.5 dqs_n90 = ddr_dqs_n;
  assign #2.5 dqp90_w = ddr_dq;

  assign #2.5 dqs_180 = dqs_p90;
  assign #2.5 dqs_360 = dqs_n90;
  assign #2.5 dq180_w = dqp90_w;

  assign #2.5 dqs_m90 = dqs_180;
  assign #2.5 dqs_q90 = dqs_360;
  assign #2.5 dqm90_w = dq180_w;

  always @(negedge clk_x2) begin
    if (reset) begin
      oen_q <= 1'b1;
    end else begin
      dat_q <= $urandom;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      rdy_q <= 1'b0;
    end else begin
      rdy_q <= vld_q;
    end
  end

  //
  //  Cores Under Notable Tests
  ///

  reg dfi_align = 1'b0;
  wire dfi_cal_w, dfi_calib, dfi_cal_p90, dfi_cal_180, dfi_cal_m90;
  wire [2:0] dfi_shift, dfi_sht_p90, dfi_sht_180, dfi_sht_m90;

  assign dfi_cal_w = dfi_calib && dfi_cal_p90 && dfi_cal_180 && dfi_cal_m90;

  always @(posedge clock) begin
    if (reset) begin
      dfi_align <= 1'b0;
    end else if (dfi_cal_w) begin
      dfi_align <= 1'b0;
    end
  end

  // GoWin Global System Reset signal tree.
  GSR GSR (.GSRI(1'b1));

  gw2a_ddr3_phy #(
      .WR_PREFETCH(WR_PREFETCH),
      .DDR3_WIDTH (DDR_DQ_WIDTH),
      .ADDR_BITS  (DDR_ROW_BITS),
      .INVERT_MCLK(INVERT_MCLK),
      .INVERT_DCLK(INVERT_DCLK),
      .WRITE_DELAY(2'd1),
      .CLOCK_SHIFT(2'd0)
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
      .dfi_align_i(dfi_align),
      .dfi_calib_o(dfi_calib),
      .dfi_shift_o(dfi_shift),  // In 1/4 clock-steps

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

  gw2a_ddr3_phy #(
      .WR_PREFETCH(WR_PREFETCH),
      .DDR3_WIDTH (DDR_DQ_WIDTH),
      .ADDR_BITS  (DDR_ROW_BITS),
      .INVERT_MCLK(INVERT_MCLK),
      .INVERT_DCLK(INVERT_DCLK),
      .WRITE_DELAY(2'd1),
      .CLOCK_SHIFT(2'd1)
  ) U_PHY2 (
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
      .dfi_rvld_o(vld_p90),
      .dfi_last_o(),
      .dfi_data_o(dat_p90),

      // For WRITE- & READ- CALIBRATION
      .dfi_align_i(dfi_align),
      .dfi_calib_o(dfi_cal_p90),
      .dfi_shift_o(dfi_sht_p90),  // In 1/4 clock-steps

      .ddr_ck_po(),
      .ddr_ck_no(),
      .ddr_rst_no(),
      .ddr_cke_o(),
      .ddr_cs_no(),
      .ddr_ras_no(),
      .ddr_cas_no(),
      .ddr_we_no(),
      .ddr_odt_o(),
      .ddr_ba_o(),
      .ddr_a_o(),
      .ddr_dm_o(),
      .ddr_dqs_pio(dqs_p90),
      .ddr_dqs_nio(dqs_n90),
      .ddr_dq_io(dqp90_w)
  );

  gw2a_ddr3_phy #(
      .WR_PREFETCH(WR_PREFETCH),
      .DDR3_WIDTH (DDR_DQ_WIDTH),
      .ADDR_BITS  (DDR_ROW_BITS),
      .INVERT_MCLK(INVERT_MCLK),
      .INVERT_DCLK(INVERT_DCLK),
      .WRITE_DELAY(2'd1),
      .CLOCK_SHIFT(2'd2)
  ) U_PHY3 (
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
      .dfi_rvld_o(vld_180),
      .dfi_last_o(),
      .dfi_data_o(dat_180),

      // For WRITE- & READ- CALIBRATION
      .dfi_align_i(dfi_align),
      .dfi_calib_o(dfi_cal_180),
      .dfi_shift_o(dfi_sht_180),  // In 1/4 clock-steps

      .ddr_ck_po(),
      .ddr_ck_no(),
      .ddr_rst_no(),
      .ddr_cke_o(),
      .ddr_cs_no(),
      .ddr_ras_no(),
      .ddr_cas_no(),
      .ddr_we_no(),
      .ddr_odt_o(),
      .ddr_ba_o(),
      .ddr_a_o(),
      .ddr_dm_o(),
      .ddr_dqs_pio(dqs_180),
      .ddr_dqs_nio(dqs_360),
      .ddr_dq_io(dq180_w)
  );

  gw2a_ddr3_phy #(
      .WR_PREFETCH(WR_PREFETCH),
      .DDR3_WIDTH (DDR_DQ_WIDTH),
      .ADDR_BITS  (DDR_ROW_BITS),
      .INVERT_MCLK(INVERT_MCLK),
      .INVERT_DCLK(INVERT_DCLK),
      .WRITE_DELAY(2'd1),
      .CLOCK_SHIFT(2'd3)
  ) U_PHY4 (
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
      .dfi_rvld_o(vld_m90),
      .dfi_last_o(),
      .dfi_data_o(dat_m90),

      // For WRITE- & READ- CALIBRATION
      .dfi_align_i(dfi_align),
      .dfi_calib_o(dfi_cal_m90),
      .dfi_shift_o(dfi_sht_m90),  // In 1/4 clock-steps

      .ddr_ck_po(),
      .ddr_ck_no(),
      .ddr_rst_no(),
      .ddr_cke_o(),
      .ddr_cs_no(),
      .ddr_ras_no(),
      .ddr_cas_no(),
      .ddr_we_no(),
      .ddr_odt_o(),
      .ddr_ba_o(),
      .ddr_a_o(),
      .ddr_dm_o(),
      .ddr_dqs_pio(dqs_m90),
      .ddr_dqs_nio(dqs_q90),
      .ddr_dq_io(dqm90_w)
  );

  // -- Invalid Capturing of DDR3 Read Data -- //

  // 90-degrees out-of-phase
  gw2a_ddr3_phy #(
      .WR_PREFETCH(WR_PREFETCH),
      .DDR3_WIDTH (DDR_DQ_WIDTH),
      .ADDR_BITS  (DDR_ROW_BITS),
      .INVERT_MCLK(INVERT_MCLK),
      .INVERT_DCLK(INVERT_DCLK),
      .WRITE_DELAY(2'd1),
      .CLOCK_SHIFT(2'd2)
  ) U_PHY5 (
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
      .dfi_rvld_o(),
      .dfi_last_o(),
      .dfi_data_o(),

      // For WRITE- & READ- CALIBRATION
      .dfi_align_i(dfi_align),
      .dfi_calib_o(),
      .dfi_shift_o(),  // In 1/4 clock-steps

      .ddr_ck_po(),
      .ddr_ck_no(),
      .ddr_rst_no(),
      .ddr_cke_o(),
      .ddr_cs_no(),
      .ddr_ras_no(),
      .ddr_cas_no(),
      .ddr_we_no(),
      .ddr_odt_o(),
      .ddr_ba_o(),
      .ddr_a_o(),
      .ddr_dm_o(),
      .ddr_dqs_pio(dqs_m90),
      .ddr_dqs_nio(dqs_q90),
      .ddr_dq_io(dqm90_w)
  );

  // 180-degrees out-of-phase
  gw2a_ddr3_phy #(
      .WR_PREFETCH(WR_PREFETCH),
      .DDR3_WIDTH (DDR_DQ_WIDTH),
      .ADDR_BITS  (DDR_ROW_BITS),
      .INVERT_MCLK(INVERT_MCLK),
      .INVERT_DCLK(INVERT_DCLK),
      .WRITE_DELAY(2'd1),
      .CLOCK_SHIFT(2'd1)
  ) U_PHY6 (
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
      .dfi_rvld_o(),
      .dfi_last_o(),
      .dfi_data_o(),

      // For WRITE- & READ- CALIBRATION
      .dfi_align_i(dfi_align),
      .dfi_calib_o(),
      .dfi_shift_o(),  // In 1/4 clock-steps

      .ddr_ck_po(),
      .ddr_ck_no(),
      .ddr_rst_no(),
      .ddr_cke_o(),
      .ddr_cs_no(),
      .ddr_ras_no(),
      .ddr_cas_no(),
      .ddr_we_no(),
      .ddr_odt_o(),
      .ddr_ba_o(),
      .ddr_a_o(),
      .ddr_dm_o(),
      .ddr_dqs_pio(dqs_m90),
      .ddr_dqs_nio(dqs_q90),
      .ddr_dq_io(dqm90_w)
  );

  // 270-degrees out-of-phase
  gw2a_ddr3_phy #(
      .WR_PREFETCH(WR_PREFETCH),
      .DDR3_WIDTH (DDR_DQ_WIDTH),
      .ADDR_BITS  (DDR_ROW_BITS),
      .INVERT_MCLK(INVERT_MCLK),
      .INVERT_DCLK(INVERT_DCLK),
      .WRITE_DELAY(2'd1),
      .CLOCK_SHIFT(2'd0)
  ) U_PHY7 (
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
      .dfi_rvld_o(),
      .dfi_last_o(),
      .dfi_data_o(),

      // For WRITE- & READ- CALIBRATION
      .dfi_align_i(dfi_align),
      .dfi_calib_o(),
      .dfi_shift_o(),  // In 1/4 clock-steps

      .ddr_ck_po(),
      .ddr_ck_no(),
      .ddr_rst_no(),
      .ddr_cke_o(),
      .ddr_cs_no(),
      .ddr_ras_no(),
      .ddr_cas_no(),
      .ddr_we_no(),
      .ddr_odt_o(),
      .ddr_ba_o(),
      .ddr_a_o(),
      .ddr_dm_o(),
      .ddr_dqs_pio(dqs_m90),
      .ddr_dqs_nio(dqs_q90),
      .ddr_dq_io(dqm90_w)
  );


endmodule  /* gw2a_ddr3_phy_tb */
