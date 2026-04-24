`timescale 1ns / 100ps
module usbaxi_top_tb;

  reg usb_clock = 1'b1;
  reg clk_26 = 1'b1;
  reg arst_n;

  always #8 usb_clock <= ~usb_clock;
  always #18 clk_26 <= ~clk_26;

  initial begin
    #10 arst_n <= 1'b0;
    #60 arst_n <= 1'b1;
  end

  // -- Simulation Data -- //

  initial begin
    $dumpfile("usbaxi_top_tb.vcd");
    $dumpvars;
  end

  // initial #690000 $finish;
  // initial #200000 $finish;

  initial begin
    #3800000 $finish;
  end

  // -- Simulation Signals -- //

  wire usb_rst_n, ulpi_dir, ulpi_nxt, ulpi_stp;
  wire [7:0] ulpi_data;

  wire ddr_rst_n, ddr_ck_p, ddr_ck_n, ddr_cke, ddr_cs_n;
  wire ddr_ras_n, ddr_cas_n, ddr_we_n, ddr_odt;
  wire [15:0] ddr_dq;
  wire [1:0] ddr_dqs_p, ddr_dqs_n, ddr_dm;
  wire [ 2:0] ddr_ba;
  wire [12:0] ddr_a;

  //
  //  Simulation Stimulus
  ///
`ifdef __icarus

  /**
   * Wrapper to the VPI model of a USB host, for providing the stimulus.
   */
  ulpi_shell U_ULPI_HOST1 (
      .clock(usb_clock),
      .rst_n(usb_rst_n),
      .dir  (ulpi_dir),
      .nxt  (ulpi_nxt),
      .stp  (ulpi_stp),
      .data (ulpi_data)
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
  //  Core Under New Tests
  ///

  wire [5:0] leds;

  usbaxi_top U_TOP1 (
      .clk_26(clk_26),
      .rst_n(arst_n),
      .send_n(1'b1),
      .uart_rx(1'b1),
      .uart_tx(),
      .leds(leds),

      .ulpi_clk (usb_clock),
      .ulpi_rst (usb_rst_n),
      .ulpi_dir (ulpi_dir),
      .ulpi_nxt (ulpi_nxt),
      .ulpi_stp (ulpi_stp),
      .ulpi_data(ulpi_data),

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

`endif  /* !__icarus */

endmodule  /* usbaxi_top_tb */
