`timescale 1ns / 100ps
module usb_core_tb;

  parameter [31:0] PHASE = "1000";
  localparam NEGATE_CLOCK = PHASE[31:24] == "1";

  localparam integer PIPELINED = 1;
  localparam integer ENDPOINT1 = 1;
  localparam integer ENDPOINT2 = 2;

  // USB BULK IN/OUT SRAM parameters
  parameter USE_SYNC_FIFO = 1;
  localparam integer FIFO_LEVEL_BITS = USE_SYNC_FIFO ? 11 : 12;
  localparam integer FSB = FIFO_LEVEL_BITS - 1;
  localparam integer BULK_FIFO_SIZE = 2048;

  initial begin
    $display("ULPI Reset module:");
    $display(" - Clock-negation: %1d", NEGATE_CLOCK);
  end


  // -- Simulation Data -- //

  initial begin
    $dumpfile("usb_core_tb.vcd");
    $dumpvars(0, usb_core_tb);

    #15000 $finish;  // todo ...
  end


  // -- Globals -- //

  reg clock = 1'b1, reset, arst_n;
  wire usb_clock, usb_rst_n, dev_clock, dev_reset;

  always #5 clock <= ~clock;

  initial begin
    reset  <= 1'b1;
    arst_n <= 1'b0;

    #40 arst_n <= 1'b1;
    #20 reset <= 1'b0;
  end


  // -- Simulation Signals -- //

  wire svalid, slast, skeep, mready;
  wire mvalid, mlast, mkeep, sready;
  wire [7:0] sdata, mdata;

  wire ulpi_clock;
  wire ulpi_dir, ulpi_nxt, ulpi_stp;
  wire [7:0] ulpi_data;

  reg enumerate;
  wire enum_done, configured, usb_idle_w;

  wire host_usb_sof_w, host_crc_err_w;
  wire dev_usb_sof_w, dev_crc_err_w;


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


  // Check the output from the Control PIPE0 //
  wire ctl0_tvalid_w = U_USB_BRIDGE1.U_CFG_PIPE0.get_desc_q;
  wire ctl0_tready_w = U_USB_BRIDGE1.U_CFG_PIPE0.chop_ready_w;
  wire ctl0_tlast_w = U_USB_BRIDGE1.U_CFG_PIPE0.chop_last_w;
  wire [7:0] ctl0_tdata_w = U_USB_BRIDGE1.U_CFG_PIPE0.chop_data_w;

  axis_flow_check U_AXIS_FLOW0 (
      .clock(usb_clock),
      .reset(reset),
      .axis_tvalid(ctl0_tvalid_w),
      .axis_tready(ctl0_tready_w),
      .axis_tlast(ctl0_tlast_w),
      .axis_tdata(ctl0_tdata_w)
  );

  // Check the output from the AXI4-Stream burst-chopper //
  wire ask_tvalid_w = U_USB_BRIDGE1.ctl0_tvalid_w;
  wire ask_tready_w = U_USB_BRIDGE1.ctl0_tready_w;
  wire ask_tlast_w = U_USB_BRIDGE1.ctl0_tlast_w;
  wire [7:0] ask_tdata_w = U_USB_BRIDGE1.ctl0_tdata_w;

  axis_flow_check U_AXIS_FLOW1 (
      .clock(usb_clock),
      .reset(reset),
      .axis_tvalid(ask_tvalid_w),
      .axis_tready(ask_tready_w),
      .axis_tlast(ask_tlast_w),
      .axis_tdata(ask_tdata_w)
  );

  // Check the output to ULPI-interface module //
  wire ulpi_tx_tvalid_w = U_USB_BRIDGE1.ulpi_tx_tvalid_w;
  wire ulpi_tx_tready_w = U_USB_BRIDGE1.ulpi_tx_tready_w;
  wire ulpi_tx_tlast_w = U_USB_BRIDGE1.ulpi_tx_tlast_w;
  wire [7:0] ulpi_tx_tdata_w = U_USB_BRIDGE1.ulpi_tx_tdata_w;

  axis_flow_check U_AXIS_FLOW4 (
      .clock(usb_clock),
      .reset(reset),
      .axis_tvalid(ulpi_tx_tvalid_w),
      .axis_tready(ulpi_tx_tready_w),
      .axis_tlast(ulpi_tx_tlast_w),
      .axis_tdata(ulpi_tx_tdata_w)
  );

  // Check the output from ULPI-interface module //
  wire ulpi_rx_tvalid_w = U_USB_BRIDGE1.ulpi_rx_tvalid_w;
  wire ulpi_rx_tready_w = U_USB_BRIDGE1.ulpi_rx_tready_w;
  wire ulpi_rx_tlast_w = U_USB_BRIDGE1.ulpi_rx_tlast_w;
  wire [7:0] ulpi_rx_tdata_w = U_USB_BRIDGE1.ulpi_rx_tdata_w;

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
  wire bulk_start_w, bulk_cycle_w, bulk_fetch_w, bulk_store_w;
  wire [3:0] bulk_endpt_w;
  wire bsvalid_w, bsready_w, bmvalid_w, bmready_w;
  wire [FSB:0] level_w;

  // Bulk Endpoint Status //
  always @(posedge usb_clock) begin
    if (reset || dev_reset) begin
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
  assign bsready_w = mready && bulk_store_w && bulk_endpt_w == ENDPOINT1;
  assign bmvalid_w = svalid && bulk_fetch_w && bulk_endpt_w == ENDPOINT1;

  assign skeep = svalid;

/*
  // Salad days
  always @(negedge usb_clock) begin
    $ulpi_step(usb_clock, usb_rst_n, ulpi_dir, ulpi_nxt, ulpi_stp, ulpi_data);
  end
*/

  ulpi_axis_bridge #(
      .PIPELINED  (PIPELINED),
      .EP1_CONTROL(0),
      .ENDPOINT1  (ENDPOINT1),
      .EP2_CONTROL(0),
      .ENDPOINT2  (ENDPOINT2)
  ) U_USB_BRIDGE1 (
      .areset_n(areset_n[3]),
      .reset_no(usb_rst_n),

      .ulpi_clock_i(usb_clock),
      .ulpi_dir_i  (ulpi_dir),
      .ulpi_nxt_i  (ulpi_nxt),
      .ulpi_stp_o  (ulpi_stp),
      .ulpi_data_io(ulpi_data),

      .usb_clock_o(dev_clock),
      .usb_reset_o(dev_reset),

      .configured_o(configured),
      .usb_idle_o(usb_idle_w),
      .usb_sof_o(dev_usb_sof_w),
      .crc_err_o(dev_crc_err_w),

      .blk_in_ready_i(bulk_in_ready_q),  // USB BULK EP control-signals
      .blk_out_ready_i(bulk_out_ready_q),
      .blk_start_o(bulk_start_w),
      .blk_cycle_o(bulk_cycle_w),
      .blk_fetch_o(bulk_fetch_w),
      .blk_store_o(bulk_store_w),
      .blk_endpt_o(bulk_endpt_w),
      .blk_error_i(1'b0),

      .s_axis_tvalid_i(bmvalid_w),  // USB 'BULK IN' EP data-path
      .s_axis_tready_o(sready),
      .s_axis_tlast_i (slast),
      .s_axis_tkeep_i (skeep),
      .s_axis_tdata_i (sdata),

      .m_axis_tvalid_o(mvalid),  // USB 'BULK OUT' EP data-path
      .m_axis_tready_i(bsready_w),
      .m_axis_tlast_o(mlast),
      .m_axis_tkeep_o(mkeep),
      .m_axis_tdata_o(mdata)
  );


  // -- Loop-back FIFO for Testing -- //

  assign bsvalid_w = mvalid && bulk_store_w && bulk_endpt_w == ENDPOINT1;
  assign bmready_w = sready && bulk_fetch_w && bulk_endpt_w == ENDPOINT1;

  wire xvalid, xready, xlast;
  wire [7:0] xdata;

  axis_clean #(
      .WIDTH(8),
      .DEPTH(16)
  ) U_AXIS_CLEAN2 (
      .clock(dev_clock),
      .reset(dev_reset),

      .s_tvalid(bsvalid_w),
      .s_tready(mready),
      .s_tlast (mlast),
      .s_tkeep (mkeep),
      .s_tdata (mdata),

      .m_tvalid(xvalid),
      .m_tready(xready),
      .m_tlast (xlast),
      .m_tkeep (),
      .m_tdata (xdata)
  );

  // Loop-back FIFO for Testing //
  generate
    if (USE_SYNC_FIFO) begin : g_sync_fifo

      sync_fifo #(
          .WIDTH (9),
          .ABITS (11),
          .OUTREG(3)
      ) rddata_fifo_inst (
          .clock(dev_clock),
          .reset(dev_reset),

          .level_o(level_w),

          .valid_i(xvalid),
          .ready_o(xready),
          .data_i ({xlast, xdata}),

          .valid_o(svalid),
          .ready_i(bmready_w),
          .data_o ({slast, sdata})
      );

    end else begin : g_axis_fifo

      axis_fifo #(
          .DEPTH(BULK_FIFO_SIZE),
          .DATA_WIDTH(8),
          .KEEP_ENABLE(0),
          .KEEP_WIDTH(1),
          .LAST_ENABLE(1),
          .ID_ENABLE(0),
          .ID_WIDTH(1),
          .DEST_ENABLE(0),
          .DEST_WIDTH(1),
          .USER_ENABLE(0),
          .USER_WIDTH(1),
          .RAM_PIPELINE(1),
          .OUTPUT_FIFO_ENABLE(0),
          .FRAME_FIFO(0),
          .USER_BAD_FRAME_VALUE(0),
          .USER_BAD_FRAME_MASK(0),
          .DROP_BAD_FRAME(0),
          .DROP_WHEN_FULL(0)
      ) U_BULK_FIFO0 (
          .clk(dev_clock),
          .rst(dev_reset),

          .s_axis_tdata (xdata),  // AXI4-Stream input
          .s_axis_tkeep (xvalid),
          .s_axis_tvalid(xvalid),
          .s_axis_tready(xready),
          .s_axis_tlast (xlast),
          .s_axis_tid   (1'b0),
          .s_axis_tdest (1'b0),
          .s_axis_tuser (1'b0),

          .pause_req(1'b0),

          .m_axis_tdata(sdata),  // AXI4-Stream output
          .m_axis_tkeep(),
          .m_axis_tvalid(svalid),
          .m_axis_tready(bmready_w),
          .m_axis_tlast(slast),
          .m_axis_tid(),
          .m_axis_tdest(),
          .m_axis_tuser(),

          .status_depth(level_w),  // Status
          .status_overflow(),
          .status_bad_frame(),
          .status_good_frame()
      );

    end
  endgenerate


endmodule  // usb_core_tb
