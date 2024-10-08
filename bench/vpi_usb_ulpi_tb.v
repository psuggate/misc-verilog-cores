`timescale 1ns / 100ps
`define __use_ddr3_because_reasons
`define __gowin_for_the_win
module vpi_usb_ulpi_tb;

  localparam DEBUG = 1;
  localparam LOGGER = 0;

  localparam DATA_FIFO_BYPASS = 1;
  localparam DDR_FREQ_MHZ = 100;

  // DDR3 settings
  localparam WR_PREFETCH = 0;
`ifdef __spaghetti_concatenate
  localparam RD_FASTPATH = 1;
`else  /* !__spaghetti_concatenate */
  localparam RD_FASTPATH = 0;
`endif  /* !__spaghetti_concatenate */
  localparam LOW_LATENCY = 1;
  localparam WRITE_DELAY = 2'b01;  // Default value (sim)
  localparam CLOCK_SHIFT = 2'b01;  // Default value
`ifdef __gowin_for_the_win
  localparam PHY_WR_DELAY = 3;
  // localparam PHY_RD_DELAY = 2; // Default (100 MHz)
  localparam PHY_RD_DELAY = 3;  // 125 MHz
`else  /* !__gowin_for_the_win */
  localparam PHY_WR_DELAY = 1;
  localparam PHY_RD_DELAY = 1;
`endif  /* !__gowin_for_the_win */

  localparam ADDRS = 27;
  localparam REQID = 4;

  // initial #759010 $finish;

  // USB settings
  localparam MAX_PACKET_LENGTH = 512;
  localparam MAX_CONFIG_LENGTH = 64;

  localparam ENDPOINT1 = 4'd2;
  localparam ENDPOINT2 = 4'd1;
  localparam ENDPOINT3 = 4'd3;
  localparam ENDPOINT4 = 4'd5;

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
  always #6 clock <= ~clock;

  assign usb_clock = clock;

  initial begin
    arst_n <= 1'b0;
    #40 arst_n <= 1'b1;
  end

  // -- Simulation Data -- //

  initial begin
    #659000 $dumpfile("vpi_usb_ulpi_tb.vcd");
    // $dumpfile("vpi_usb_ulpi_tb.vcd");
    $dumpvars;
  end

  // initial #670000 $finish;

  initial begin
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

  // -- Simulation Stimulus -- //

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

  //
  // Cores Under New Tests
  ///

  wire io_tvalid, io_tready, io_tlast;
  wire x_tvalid, x_tready, x_tkeep, x_tlast;
  wire y_tvalid, y_tready, y_tkeep, y_tlast;
  wire [7:0] x_tdata, y_tdata, io_tdata;

  usb_ulpi_core #(
      .MAX_PACKET_LENGTH(MAX_PACKET_LENGTH),
      .MAX_CONFIG_LENGTH(MAX_CONFIG_LENGTH),
      .ENDPOINT1        (ENDPOINT1),
      .ENDPOINT2        (ENDPOINT2),
      .ENDPOINTD        (ENDPOINT3),
      .ENDPOINT4        (ENDPOINT4),
      .USE_EP4_OUT      (1),
      .DEBUG            (DEBUG),
      .LOGGER           (LOGGER),
      .USE_UART         (0)
  ) U_USB1 (
      .osc_in(clk25),
      .arst_n(arst_n),

      .ulpi_clk (usb_clock),
      .ulpi_rst (usb_rst_n),
      .ulpi_dir (ulpi_dir),
      .ulpi_nxt (ulpi_nxt),
      .ulpi_stp (ulpi_stp),
      .ulpi_data(ulpi_data),

      // Todo: debug UART signals ...
      .send_ni  (1'b1),
      .uart_rx_i(1'b1),
      .uart_tx_o(),

      .usb_clock_o(dev_clock),
      .usb_reset_o(dev_reset),

      .configured_o(configured),
      .conf_event_o(conf_event),
      .conf_value_o(usb_config),
      .crc_error_o (),

      .blki_tvalid_i(io_tvalid),  // USB 'BULK IN' EP data-path
      .blki_tready_o(io_tready),
      .blki_tlast_i (io_tlast),
      .blki_tdata_i (io_tdata),

      .blko_tvalid_o(io_tvalid),  // USB 'BULK OUT' EP data-path
      .blko_tready_i(io_tready),
      .blko_tlast_o (io_tlast),
      .blko_tdata_o (io_tdata),

      .blkx_tvalid_i(x_tvalid),  // DDR3 -> USB 'BULK IN' EP
      .blkx_tready_o(x_tready),
      .blkx_tlast_i (x_tlast),
      .blkx_tdata_i (x_tdata),

      .blky_tvalid_o(y_tvalid),  // USB 'BULK OUT' EP -> DDR3
      .blky_tready_i(y_tready),
      .blky_tlast_o (y_tlast),
      .blky_tdata_o (y_tdata)
  );


  //
  //  DDR3 Cores Under Next-generation Tests
  ///

`ifdef __use_ddr3_because_reasons

  reg drst_n = 1'b1, send_q = 1'b1;
  wire drst_w = ~drst_n;

  wire ddr_rst_n, ddr_ck_p, ddr_ck_n, ddr_cke, ddr_odt;
  wire ddr_cs_n, ddr_ras_n, ddr_cas_n, ddr_we_n;
  wire [1:0] ddr_dm, ddr_dqs_p, ddr_dqs_n;
  wire [ 2:0] ddr_ba;
  wire [12:0] ddr_a;
  wire [15:0] ddr_dq;

  assign y_tkeep = y_tvalid;  // Todo ...

  initial begin
    drst_n <= 1'b0;
    send_q <= 1'b1;
    #500000 drst_n <= 1'b1;
    #250000 send_q <= 1'b0;
    #30 send_q <= 1'b1;
  end

  ddr3_top #(
      .DDR_FREQ_MHZ(DDR_FREQ_MHZ),
      .SRAM_BYTES  (2048),
      .DATA_WIDTH  (32),
      .DFIFO_BYPASS(DATA_FIFO_BYPASS),
      .PHY_WR_DELAY(PHY_WR_DELAY),
      .PHY_RD_DELAY(PHY_RD_DELAY),
      .WRITE_DELAY (WRITE_DELAY),
      .CLOCK_SHIFT (CLOCK_SHIFT),
      .RD_FASTPATH (RD_FASTPATH),
      .WR_PREFETCH (WR_PREFETCH),
      .LOW_LATENCY (LOW_LATENCY)
  ) U_DDRC1 (
      .osc_in(clk25),  // Dev-board clock
      .arst_n(drst_n), // 'S2' button for async-reset

      .bus_clock(clock),
      .bus_reset(drst_w),

      .ddr3_conf_o(ddr3_conf_w),
      .ddr_clock_o(sys_clk),
      .ddr_reset_o(sys_rst),

      // From USB or SPI
      .s_tvalid(y_tvalid),
      .s_tready(y_tready),
      .s_tkeep (y_tkeep),
      .s_tlast (y_tlast),
      .s_tdata (y_tdata),

      // To USB or SPI
      .m_tvalid(x_tvalid),
      .m_tready(x_tready),
      .m_tkeep (x_tkeep),
      .m_tlast (x_tlast),
      .m_tdata (x_tdata),

      // Fast-read channels [optional]
      .byp_arvalid_i(1'b0),
      .byp_arready_o(),
      .byp_araddr_i({ADDRS{1'b0}}),
      .byp_arid_i({REQID{1'b0}}),
      .byp_arlen_i(8'd0),
      .byp_arburst_i(2'd0),

      .byp_rvalid_o(),
      .byp_rready_i(1'b1),
      .byp_rlast_o(),
      .byp_rresp_o(),
      .byp_rid_o(),
      .byp_rdata_o(),

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
