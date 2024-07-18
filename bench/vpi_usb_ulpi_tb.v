`timescale 1ns / 100ps
module vpi_usb_ulpi_tb;

  // Local FIFO address-bits
  localparam FBITS = 11;
  localparam FSB = FBITS - 1;

  initial begin
    $display("USB ULPI Wrapper Testbench");
  end


  // -- Globals -- //

  reg clock, clk25, reset, arst_n;
  wire usb_clock, usb_rst_n, dev_clock, dev_reset;

  initial begin
    clock <= 1'b1;
    clk25 <= 1'b1;
  end

  always #20 clk25 <= ~clk25;
  always #5 clock <= ~clock;

  assign usb_clock = clock;

  initial begin
    reset  <= 1'b1;
    arst_n <= 1'b0;

    #40 arst_n <= 1'b1;
    #20 reset <= 1'b0;
  end


  // -- Simulation Data -- //

  initial begin
    $dumpfile("vpi_usb_ulpi_tb.vcd");
    $dumpvars;

    #15000 $finish;
  end


  // -- Simulation Signals -- //

  wire blki_tvalid_w, blki_tready_w, blki_tlast_w, blki_tkeep_w;
  wire blko_tvalid_w, blko_tready_w, blko_tlast_w, blko_tkeep_w;
  wire [7:0] blki_tdata_w, blko_tdata_w;

  wire s_tvalid, s_tlast, s_tkeep, m_tready;
  wire m_tvalid, m_tlast, m_tkeep, s_tready;
  wire [7:0] s_tdata, m_tdata;

  wire ulpi_clock;
  wire ulpi_dir, ulpi_nxt, ulpi_stp;
  wire [7:0] ulpi_data;

  reg enumerate;
  wire enum_done, configured, usb_idle_w;

  wire host_usb_sof_w, host_crc_err_w;
  wire dev_usb_sof_w, dev_crc_err_w;


  reg [3:0] areset_n;
  wire arst_nw = areset_n[3];

  always @(posedge usb_clock or negedge arst_n) begin
    if (!arst_n) begin
      areset_n <= 4'h0;
    end else begin
      areset_n <= {areset_n[2:0], 1'b1};
    end
  end

  // Salad days
  always @(negedge usb_clock) begin
    $ulpi_step(usb_clock, arst_nw, ulpi_dir, ulpi_nxt, ulpi_stp, ulpi_data);
  end


  // -- System Clocks & Resets -- //

/*
  ulpi_reset #(
      .PHASE("0000"),  // Note: timing-constraints used instead
      .PLLEN(0)
  ) U_RESET1 (
      .areset_n  (arst_n),
      .ulpi_clk  (clock),
      .sys_clock (clk25),

      .ulpi_rst_n(reset_no),// Active LO
      .pll_locked(locked),

      // .usb_clock (clock),   // 60 MHz, PLL output, phase-shifted
      .usb_reset (reset),   // Active HI
      .ddr_clock ()         // 120 MHz, PLL output, phase-shifted
  );
*/


  //
  // Cores Under New Tests
  ///

  usb_ulpi_top #(
      .USE_EP2_IN (1),
      .USE_EP1_OUT(1)
  ) U_USB_ULPI_TOP1 (
      .areset_n       (arst_nw),
      .reset_no       (usb_rst_n),

      .ulpi_clock_i   (usb_clock),
      .ulpi_dir_i     (ulpi_dir),
      .ulpi_nxt_i     (ulpi_nxt),
      .ulpi_stp_o     (ulpi_stp),
      .ulpi_data_io   (ulpi_data),

      .usb_clock_o    (dev_clock),
      .usb_reset_o    (dev_reset),

/*
      .configured_o   (configured),
      .usb_idle_o     (usb_idle_w),
      .usb_sof_o      (dev_usb_sof_w),
      .crc_err_o      (dev_crc_err_w),

      .blk_in_ready_i (bulk_in_ready_q), // USB BULK EP control-signals
      .blk_out_ready_i(bulk_out_ready_q),
      .blk_start_o    (bulk_start_w),
      .blk_cycle_o    (bulk_cycle_w),
      .blk_fetch_o    (bulk_fetch_w),
      .blk_store_o    (bulk_store_w),
      .blk_endpt_o    (bulk_endpt_w),
*/
      .blk_error_i    (1'b0),

      .blki_tvalid_i  (blki_tvalid_w),   // USB 'BULK IN' EP data-path
      .blki_tready_o  (blki_tready_w),
      .blki_tlast_i   (blki_tlast_w),
      .blki_tkeep_i   (blki_tkeep_w),
      .blki_tdata_i   (blki_tdata_w),

      .blko_tvalid_o  (blko_tvalid_w),   // USB 'BULK OUT' EP data-path
      .blko_tready_i  (blko_tready_w),
      .blko_tlast_o   (blko_tlast_w),
      .blko_tkeep_o   (blko_tkeep_w),
      .blko_tdata_o   (blko_tdata_w)
  );


endmodule  /* vpi_usb_ulpi_tb */
