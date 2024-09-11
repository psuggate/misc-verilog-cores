`timescale 1ns / 100ps
module vpi_usb_ulpi_tb;

  localparam DEBUG = 1;
  localparam MAX_PACKET_LENGTH = 512;
  // localparam MAX_PACKET_LENGTH = 16;

  localparam ENDPOINT1 = 4'd2;
  localparam ENDPOINT2 = 4'd1;
  localparam ENDPOINT3 = 4'd3;

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

    // #38000 $finish;
    #3800000 $finish;
  end

  // -- Simulation Signals -- //

  wire blki_tvalid_w, blki_tready_w, blki_tlast_w;
  wire blko_tvalid_w, blko_tready_w, blko_tlast_w;
  wire [7:0] blki_tdata_w, blko_tdata_w;

  wire ulpi_clock;
  wire ulpi_dir, ulpi_nxt, ulpi_stp;
  wire [7:0] ulpi_data;

  wire configured, conf_event;
  wire ddr3_conf_w, sys_clk, sys_rst;
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

  `define __use_small_packets

  wire x_tvalid, x_tready, x_tlast;
  wire [7:0] x_tdata;

  usb_ulpi_top #(
      .MAX_PACKET_LENGTH(MAX_PACKET_LENGTH),
      .DEBUG            (DEBUG),
      .ENDPOINT1        (ENDPOINT1),
      .ENDPOINT2        (ENDPOINT2),
      .USE_EP2_IN       (1),
      .USE_EP3_IN       (1),
      .USE_EP1_OUT      (1)
  ) U_USB1 (
      .areset_n(~reset),
      // .areset_n(usb_rst_n),

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

`ifdef __use_small_packets
      .blki_tvalid_i(blki_tvalid_w),  // USB 'BULK IN' EP data-path
      .blki_tready_o(blki_tready_w),
      .blki_tlast_i (blki_tlast_w),
      .blki_tdata_i (blki_tdata_w),
`else  /* !__use_small_packets */
      .blki_tvalid_i(blko_tvalid_w),  // USB 'BULK IN' EP data-path
      .blki_tready_o(blko_tready_w),
      .blki_tlast_i (blko_tlast_w),
      .blki_tdata_i (blko_tdata_w),
`endif  /* !__use_small_packets */

      .blkx_tvalid_i(DEBUG ? x_tvalid : blko_tvalid_w),  // USB 'BULK IN' EP data-path
      .blkx_tready_o(x_tready),
      .blkx_tlast_i (DEBUG ? x_tlast : blko_tlast_w),
      .blkx_tdata_i (DEBUG ? x_tdata : blko_tdata_w),

      .blko_tvalid_o(blko_tvalid_w),  // USB 'BULK OUT' EP data-path
`ifdef __use_small_packets
      .blko_tready_i(DEBUG ? 1'b1 : x_tready),
`else  /* !__use_small_packets */
      .blko_tready_i(DEBUG ? blko_tready_w : x_tready),
`endif  /* !__use_small_packets */
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

  `define __all_in_one_usb_ulpi_core
`ifdef __all_in_one_usb_ulpi_core

  wire core_clk, core_rst, core_dir, core_nxt, core_stp;
  wire [7:0] core_dat;

  wire core_tready_w;
  wire io_tvalid, io_tready, io_tlast;
  wire [7:0] io_tdata;

  assign core_clk = clock;
  assign core_dir = ulpi_dir;
  assign core_nxt = ulpi_nxt;
  assign core_dat = ulpi_dir ? ulpi_data : 8'bz;

  usb_ulpi_core #(
      .MAX_PACKET_LENGTH(MAX_PACKET_LENGTH),
      .ENDPOINT1(ENDPOINT1),
      .ENDPOINT2(ENDPOINT2),
      .DEBUG(DEBUG),
      .USE_UART(0),
      .ENDPOINTD(ENDPOINT3)
  ) U_CORE1 (
      .clk_26(clk25),
      .arst_n(arst_n),
      // .arst_n(usb_rst_n),

      .ulpi_clk (core_clk),
      .ulpi_rst (core_rst),
      .ulpi_dir (core_dir),
      .ulpi_nxt (core_nxt),
      .ulpi_stp (core_stp),
      .ulpi_data(core_dat),

      // Todo: debug UART signals ...
      .send_ni  (1'b1),
      .uart_rx_i(1'b1),
      .uart_tx_o(),

      .usb_clock_o(),
      .usb_reset_o(),

      .configured_o(),
      .conf_event_o(),
      .conf_value_o(),
      .crc_error_o (),

`ifdef __use_small_packets
      .blki_tvalid_i(blki_tvalid_w),  // USB 'BULK IN' EP data-path
      .blki_tready_o(core_tready_w),
      .blki_tlast_i(blki_tlast_w),
      .blki_tdata_i(blki_tdata_w),
`else  /* !__use_small_packets */
      .blki_tvalid_i(io_tvalid),  // USB 'BULK IN' EP data-path
      .blki_tready_o(io_tready),
      .blki_tlast_i(io_tlast),
      .blki_tdata_i(io_tdata),
`endif  /* !__use_small_packets */

      .blkx_tvalid_i(1'b0),
      .blkx_tready_o(),
      .blkx_tlast_i (1'b0),
      .blkx_tdata_i (8'bx),

      .blko_tvalid_o(io_tvalid),  // USB 'BULK OUT' EP data-path
      .blko_tready_i(io_tready),
      .blko_tlast_o (io_tlast),
      .blko_tdata_o (io_tdata)
  );

`endif  /* !__all_in_one_usb_ulpi_core */


  //
  //  DDR3 Cores Under Next-generation Tests
  ///

`ifdef __use_ddr3_because_reasons

  wire ddr_rst_n, ddr_ck_p, ddr_ck_n, ddr_cke, ddr_odt;
  wire ddr_cs_n, ddr_ras_n, ddr_cas_n, ddr_we_n;
  wire [1:0] ddr_dm, ddr_dqs_p, ddr_dqs_n;
  wire [ 2:0] ddr_ba;
  wire [12:0] ddr_a;
  wire [15:0] ddr_dq;

  assign m_tkeep = m_tvalid;  // Todo ...
  wire u_tready;

  ddr3_top #(
      .SRAM_BYTES (2048),
      .DATA_WIDTH (32),
      .LOW_LATENCY(LOW_LATENCY)
  ) ddr_core_inst (
      .clk_26(clk25),  // Dev-board clock
      .rst_n (rst_n),  // 'S2' button for async-reset

      .bus_clock(clock),
      .bus_reset(reset),

      .ddr3_conf_o(ddr3_conf_w),
      .ddr_clock_o(sys_clk),
      .ddr_reset_o(sys_rst),

      // From USB or SPI
      .s_tvalid(LOOPBACK ? 1'b0 : m_tvalid),
      .s_tready(m_tready),
      .s_tkeep (LOOPBACK ? 1'b0 : m_tkeep),
      .s_tlast (LOOPBACK ? 1'b0 : m_tlast),
      .s_tdata (m_tdata),

      // To USB or SPI
      .m_tvalid(s_tvalid),
      .m_tready(LOOPBACK ? 1'b0 : s_tready),
      .m_tkeep (s_tkeep),
      .m_tlast (s_tlast),
      .m_tdata (s_tdata),

      // 1Gb DDR3 SDRAM pins
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

`else  /* !__use_ddr3_because_reasons */

  assign ddr3_conf_w = 1'b0;
  assign sys_clk = clk25;
  assign sys_rst = 1'b0;

`endif  /* !__use_ddr3_because_reasons */


endmodule  /* vpi_usb_ulpi_tb */
