`timescale 1ns / 100ps
module usb_ulpi_wrapper_tb;

  // Local FIFO address-bits
  localparam FBITS = 11;
  localparam FSB = FBITS - 1;

  initial begin
    $display("USB ULPI Wrapper Testbench");
  end


  // -- Simulation Data -- //

  initial begin
    $dumpfile("usb_ulpi_wrapper_tb.vcd");
    $dumpvars;

    #15000 $finish;
  end


  // -- Globals -- //

  reg clock = 1'b1, clk25 = 1'b1, reset, arst_n;
  wire usb_clock, usb_rst_n, dev_clock, dev_reset;

  always #20 clk25 <= ~clk25;
  always #5 clock <= ~clock;

  initial begin
    reset  <= 1'b1;
    arst_n <= 1'b0;

    #40 arst_n <= 1'b1;
    #20 reset <= 1'b0;
  end


  // -- Simulation Signals -- //

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

  assign usb_idle_w = U_USB1.device_usb_idle_w;


  // -- Initialisation -- //

  initial begin : Stimulus
    @(posedge clock);

    while (reset) begin
      @(posedge clock);
      enumerate <= 1'b0;
    end

    @(posedge clock);
    @(posedge clock);
    while (!usb_idle_w) begin
      @(posedge clock);
    end
    @(posedge clock);

    enumerate <= 1'b1;
    @(posedge clock);

    while (!enum_done || !usb_idle_w) begin
      @(posedge clock);
    end
    enumerate <= 1'b0;
    @(posedge clock);

    #1000 @(posedge clock);
    while (!host_usb_sof_w) begin
      @(posedge clock);
    end

    #4000 @(posedge clock);
    $finish;
  end

  reg enabled = 1'b0;

  always @(posedge clock) begin
    if (reset) begin
      enabled <= 1'b0;
    end else if (usb_idle_w) begin
      enabled <= 1'b1;
    end
  end


  fake_usb_host_ulpi U_FAKE_USB0 (
      .clock (clock),
      .reset (~arst_n),
      .enable(enabled),

      .ulpi_clock_o(usb_clock),
      .ulpi_rst_ni (usb_rst_n),
      .ulpi_dir_o  (ulpi_dir),
      .ulpi_nxt_o  (ulpi_nxt),
      .ulpi_stp_i  (ulpi_stp),
      .ulpi_data_io(ulpi_data),

      .usb_sof_o(host_usb_sof_w),
      .crc_err_o(host_crc_err_w),

      .dev_enum_start_i(enumerate),
      .dev_enum_done_o (enum_done),
      .dev_configured_i(configured)
  );


  // Monitor for ULPI flow-control rules violations
  ulpi_flow_check U_ULPI_FLOW0 (
      .ulpi_clk  (usb_clock),
      .ulpi_rst_n(usb_rst_n),
      .ulpi_dir  (ulpi_dir),
      .ulpi_nxt  (ulpi_nxt),
      .ulpi_stp  (ulpi_stp),
      .ulpi_data (ulpi_data)
  );

  // Check the output from the AXI4-Stream burst-chopper //
  wire ask_tvalid_w = U_USB1.U_ULPI_USB1.ctl0_tvalid_w;
  wire ask_tready_w = U_USB1.U_ULPI_USB1.ctl0_tready_w;
  wire ask_tlast_w = U_USB1.U_ULPI_USB1.ctl0_tlast_w;
  wire [7:0] ask_tdata_w = U_USB1.U_ULPI_USB1.ctl0_tdata_w;

  axis_flow_check U_AXIS_FLOW1 (
      .clock(usb_clock),
      .reset(reset),
      .axis_tvalid(ask_tvalid_w),
      .axis_tready(ask_tready_w),
      .axis_tlast(ask_tlast_w),
      .axis_tdata(ask_tdata_w)
  );

  // Check the output to ULPI-interface module //
  wire ulpi_tx_tvalid_w = U_USB1.U_ULPI_USB1.ulpi_tx_tvalid_w;
  wire ulpi_tx_tready_w = U_USB1.U_ULPI_USB1.ulpi_tx_tready_w;
  wire ulpi_tx_tlast_w = U_USB1.U_ULPI_USB1.ulpi_tx_tlast_w;
  wire [7:0] ulpi_tx_tdata_w = U_USB1.U_ULPI_USB1.ulpi_tx_tdata_w;

  axis_flow_check U_AXIS_FLOW4 (
      .clock(usb_clock),
      .reset(reset),
      .axis_tvalid(ulpi_tx_tvalid_w),
      .axis_tready(ulpi_tx_tready_w),
      .axis_tlast(ulpi_tx_tlast_w),
      .axis_tdata(ulpi_tx_tdata_w)
  );

  // Check the output from ULPI-interface module //
  wire ulpi_rx_tvalid_w = U_USB1.U_ULPI_USB1.ulpi_rx_tvalid_w;
  wire ulpi_rx_tready_w = U_USB1.U_ULPI_USB1.ulpi_rx_tready_w;
  wire ulpi_rx_tlast_w = U_USB1.U_ULPI_USB1.ulpi_rx_tlast_w;
  wire [7:0] ulpi_rx_tdata_w = U_USB1.U_ULPI_USB1.ulpi_rx_tdata_w;

  axis_flow_check U_AXIS_FLOW5 (
      .clock(usb_clock),
      .reset(reset),
      .axis_tvalid(ulpi_rx_tvalid_w),
      .axis_tready(ulpi_rx_tready_w),
      .axis_tlast(ulpi_rx_tlast_w),
      .axis_tdata(ulpi_rx_tdata_w)
  );


  reg [3:0] areset_n;

  always @(posedge usb_clock or negedge arst_n) begin
    if (!arst_n) begin
      areset_n <= 4'h0;
    end else begin
      areset_n <= {areset_n[2:0], 1'b1};
    end
  end


  // -- ULPI Core and BULK IN/OUT SRAM -- //

  reg bulk_in_ready_q, bulk_out_ready_q;
  wire [FSB:0] level_w;

  assign s_tkeep = s_tvalid;

  // Bulk Endpoint Status //
  always @(posedge dev_clock) begin
    if (dev_reset) begin
      bulk_in_ready_q  <= 1'b0;
      bulk_out_ready_q <= 1'b0;
    end else begin
      bulk_in_ready_q  <= configured && level_w > 4;
      bulk_out_ready_q <= configured && level_w < 1024;
    end
  end


  //
  // Cores Under New Tests
  ///
  usb_ulpi_wrapper #(
      .DEBUG(0)
  ) U_USB1 (
      .clk_26(clk25),
      .rst_n (areset_n[3]),

      // USB ULPI pins on the dev-board
      .ulpi_clk (usb_clock),
      .ulpi_rst (usb_rst_n),
      .ulpi_dir (ulpi_dir),
      .ulpi_nxt (ulpi_nxt),
      .ulpi_stp (ulpi_stp),
      .ulpi_data(ulpi_data),

      // Debug UART signals
      .send_ni  (1'b1),
      .uart_rx_i(1'b0),
      .uart_tx_o(),

      .configured_o(configured),
      .status_o(),

      // Same clock-domain as the AXI4-Stream ports
      .usb_clk_o(dev_clock),
      .usb_rst_o(dev_reset),

      // USB BULK endpoint #1 //
      .ep1_in_ready_i (bulk_in_ready_q),
      .ep1_out_ready_i(bulk_out_ready_q),

      .m1_tvalid(m_tvalid),
      .m1_tready(m_tready),
      .m1_tlast (m_tlast),
      .m1_tkeep (m_tkeep),
      .m1_tdata (m_tdata),

      .s1_tvalid(s_tvalid),
      .s1_tready(s_tready),
      .s1_tlast (s_tlast),
      .s1_tkeep (s_tkeep),
      .s1_tdata (s_tdata),

      // USB BULK endpoint #2 //
      .ep2_in_ready_i (1'b0),
      .ep2_out_ready_i(1'b0),

      .m2_tvalid(),
      .m2_tready(1'b0),
      .m2_tlast (),
      .m2_tkeep (),
      .m2_tdata (),

      .s2_tvalid(1'b0),
      .s2_tready(),
      .s2_tlast (1'b0),
      .s2_tkeep (1'b0),
      .s2_tdata (8'bx)
  );


  // Loop-back FIFO for Testing //
  sync_fifo #(
      .WIDTH (9),
      .ABITS (FBITS),
      .OUTREG(3)
  ) rddata_fifo_inst (
      .clock(dev_clock),
      .reset(dev_reset),

      .level_o(level_w),

      .valid_i(m_tvalid),
      .ready_o(m_tready),
      .data_i ({m_tlast, m_tdata}),

      .valid_o(s_tvalid),
      .ready_i(s_tready),
      .data_o ({s_tlast, s_tdata})
  );


endmodule  // usb_core_tb
