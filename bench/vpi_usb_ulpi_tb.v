`timescale 1ns / 100ps
module vpi_usb_ulpi_tb;

  localparam DEBUG = 1;

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

    #38000 $finish;
  end


  // -- Simulation Signals -- //

  wire blki_tvalid_w, blki_tready_w, blki_tlast_w;
  wire blko_tvalid_w, blko_tready_w, blko_tlast_w;
  wire [7:0] blki_tdata_w, blko_tdata_w;

  wire ulpi_clock;
  wire ulpi_dir, ulpi_nxt, ulpi_stp;
  wire [7:0] ulpi_data;

  wire configured, conf_event;
  wire [2:0] usb_config;

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
  assign blki_tdata_w  = tdata_q;

  assign blko_tready_w = 1'b1;  // Todo ...

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
  ulpi_shell U_ULPI_HOST1 (
      .clock(usb_clock),
      .rst_n(usb_rst_n),
      .dir  (ulpi_dir),
      .nxt  (ulpi_nxt),
      .stp  (ulpi_stp),
      .data (ulpi_data)
  );


  // -- System Clocks & Resets -- //

  ulpi_reset #(
      .PHASE("0000"),  // Note: timing-constraints used instead
      .PLLEN(0)
  ) U_RESET1 (
      .areset_n (arst_n),
      .ulpi_clk (clock),
      .sys_clock(clk25),

      .ulpi_rst_n(usb_rst_n),  // Active LO
      .pll_locked(locked),

      // .usb_clock (clock),   // 60 MHz, PLL output, phase-shifted
      .usb_reset(reset),  // Active HI
      .ddr_clock()        // 120 MHz, PLL output, phase-shifted
  );


  //
  // Cores Under New Tests
  ///

  wire x_tvalid, x_tready, x_tlast;
  wire [7:0] x_tdata;

  `define __swap_endpoint_directions
`ifdef __swap_endpoint_directions
  localparam ENDPOINT1 = 4'd2;
  localparam ENDPOINT2 = 4'd1;
`else  /* !__swap_endpoint_directions */
  localparam ENDPOINT1 = 4'd1;
  localparam ENDPOINT2 = 4'd2;
`endif  /* !__swap_endpoint_directions */

  usb_ulpi_top #(
      .DEBUG      (DEBUG),
      .ENDPOINT1  (ENDPOINT1),
      .ENDPOINT2  (ENDPOINT2),
      .USE_EP2_IN (1),
      .USE_EP3_IN (1),
      .USE_EP1_OUT(1)
  ) U_USB1 (
      .areset_n(usb_rst_n),

      .ulpi_clock_i(usb_clock),
      .ulpi_dir_i  (ulpi_dir),
      .ulpi_nxt_i  (ulpi_nxt),
      .ulpi_stp_o  (ulpi_stp),
      .ulpi_data_io(ulpi_data),

      .usb_clock_o(dev_clock),
      .usb_reset_o(dev_reset),

      .configured_o(configured),
      .conf_event_o(conf_event),
      .conf_value_o(usb_config),

      .blki_tvalid_i(blki_tvalid_w),  // USB 'BULK IN' EP data-path
      .blki_tready_o(blki_tready_w),
      .blki_tlast_i (blki_tlast_w),
      .blki_tdata_i (blki_tdata_w),

      .blkx_tvalid_i(DEBUG ? x_tvalid : blko_tvalid_w),  // USB 'BULK IN' EP data-path
      .blkx_tready_o(x_tready),
      .blkx_tlast_i (DEBUG ? x_tlast : blko_tlast_w),
      .blkx_tdata_i (DEBUG ? x_tdata : blko_tdata_w),

      .blko_tvalid_o(blko_tvalid_w),  // USB 'BULK OUT' EP data-path
      .blko_tready_i(DEBUG ? 1'b1 : x_tready),
      .blko_tlast_o(blko_tlast_w),
      .blko_tdata_o(blko_tdata_w)
  );

  // -- Debug Telemetry Logging and Output -- //

  wire [10:0] sof_w = U_USB1.sof_count_w;

  wire err_w = U_USB1.crc_error_w;
  wire [19:0] sig_w;
  wire [11:0] ign_w;
  wire [3:0] ep1_w, ep2_w, ep3_w, pid_w;
  wire [2:0] st_w = U_USB1.stout_w;
  wire re_w = U_USB1.RxEvent == 2'b01;

  assign ep1_w = {U_USB1.ep1_err_w, U_USB1.ep1_sel_w, U_USB1.ep1_par_w, U_USB1.ep1_rdy_w};
  assign ep2_w = {U_USB1.ep2_err_w, U_USB1.ep2_sel_w, U_USB1.ep2_par_w, U_USB1.ep2_rdy_w};
  assign ep3_w = {U_USB1.ep3_err_w, U_USB1.ep3_sel_w, U_USB1.ep3_par_w, U_USB1.ep3_rdy_w};
  assign pid_w = U_USB1.U_PROTO1.pid_q;

  assign sig_w = {ep3_w, ep2_w, ep1_w, pid_w, re_w, st_w};  // 20b
  assign ign_w = {err_w, sof_w};  // 12b

  // Capture telemetry, so that it can be read back from EP1
  axis_logger #(
      .SRAM_BYTES(2048),
      .FIFO_WIDTH(32),
      .SIG_WIDTH(20),
      .PACKET_SIZE(8)  // Note: 8x 32b words per USB (BULK IN) packet
  ) U_TELEMETRY1 (
      .clock(dev_clock),
      .reset(dev_reset),

      .enable_i(configured),
      .change_i(sig_w),
      .ignore_i(ign_w),
      .level_o (),

      .m_tvalid(x_tvalid),  // AXI4-Stream for telemetry data
      .m_tready(DEBUG ? x_tready : 1'b0),
      .m_tkeep(),
      .m_tlast(x_tlast),
      .m_tdata(x_tdata)
  );


endmodule  /* vpi_usb_ulpi_tb */
