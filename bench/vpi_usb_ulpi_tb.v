`timescale 1ns / 100ps
module vpi_usb_ulpi_tb;

  // Local FIFO address-bits
  localparam FBITS = 11;
  localparam FSB = FBITS - 1;

  initial begin
    $display("USB ULPI Wrapper Testbench");
  end


  // -- Globals -- //

  reg clock, clk25, arst_n;
  wire usb_clock, usb_rst_n, dev_clock, dev_reset, reset, locked;

  initial begin
    clock <= 1'b1;
    clk25 <= 1'b1;
  end

  always #20 clk25 <= ~clk25;
  always #5 clock <= ~clock;

  assign usb_clock = clock;

  initial begin
    arst_n <= 1'b0;
    #40 arst_n <= 1'b1;
  end


  // -- Simulation Data -- //

  initial begin
    $dumpfile("vpi_usb_ulpi_tb.vcd");
    $dumpvars;

    #35000 $finish;
  end


  // -- Simulation Signals -- //

  wire bulk_start_w, bulk_cycle_w, bulk_fetch_w, bulk_store_w;
  wire [3:0] bulk_endpt_w;

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
  wire enum_done, configured, conf_event, usb_idle_w;
  wire [2:0] usb_config;

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


  //
  //  Some Logics
  ///

  reg tvalid_q, tlast_q, tstart_q;
  reg [7:0] tdata_q;

  assign blki_tvalid_w = tvalid_q;
  assign blki_tlast_w  = tlast_q;
  assign blki_tkeep_w  = 1'b1;
  assign blki_tdata_w  = tdata_q;

  assign blko_tready_w = 1'b1; // Todo ...

  always @(posedge usb_clock) begin
    if (!usb_rst_n) begin
      tvalid_q <= 1'b0;
      tstart_q <= 1'b0;
      tlast_q  <= 1'b0;
    end else begin
      tstart_q <= configured && usb_config != 3'd0;

      if (blki_tready_w && tvalid_q && !tlast_q) begin
        tlast_q <= 1'b1;
        tdata_q <= $random;
      end else if (blki_tready_w && tvalid_q && tlast_q) begin
        tvalid_q <= 1'b0;
        tlast_q  <= 1'b0;
      end else if (tstart_q && blki_tready_w) begin
        tvalid_q <= 1'b1;
        tlast_q  <= 1'b0;
        tdata_q  <= $random;
      end
    end
  end


  /**
   * Wrapper to the VPI model of a USB host, for providing the stimulus.
   */
  ulpi_shell U_ULPI_HOST1
    ( .clock(usb_clock),
      .rst_n(usb_rst_n),
      .dir(ulpi_dir),
      .nxt(ulpi_nxt),
      .stp(ulpi_stp),
      .data(ulpi_data)
      );


  // -- System Clocks & Resets -- //

  ulpi_reset #(
      .PHASE("0000"),  // Note: timing-constraints used instead
      .PLLEN(0)
  ) U_RESET1 (
      .areset_n  (arst_n),
      .ulpi_clk  (clock),
      .sys_clock (clk25),

      .ulpi_rst_n(usb_rst_n),// Active LO
      .pll_locked(locked),

      // .usb_clock (clock),   // 60 MHz, PLL output, phase-shifted
      .usb_reset (reset),   // Active HI
      .ddr_clock ()         // 120 MHz, PLL output, phase-shifted
  );


  //
  // Cores Under New Tests
  ///

`define __swap_endpoint_directions
`ifdef  __swap_endpoint_directions
  localparam ENDPOINT1 = 4'd2;
  localparam ENDPOINT2 = 4'd1;
`else   /* !__swap_endpoint_directions */
  localparam ENDPOINT1 = 4'd1;
  localparam ENDPOINT2 = 4'd2;
`endif  /* !__swap_endpoint_directions */

  usb_ulpi_top #(
      .ENDPOINT1(ENDPOINT1),
      .ENDPOINT2(ENDPOINT2),
      .USE_EP2_IN (1),
      .USE_EP1_OUT(1)
  ) U_USB1 (
      .areset_n       (usb_rst_n),

      .ulpi_clock_i   (usb_clock),
      .ulpi_dir_i     (ulpi_dir),
      .ulpi_nxt_i     (ulpi_nxt),
      .ulpi_stp_o     (ulpi_stp),
      .ulpi_data_io   (ulpi_data),

      .usb_clock_o    (dev_clock),
      .usb_reset_o    (dev_reset),

      .configured_o   (configured),
      .conf_event_o   (conf_event),
      .conf_value_o   (usb_config),

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
