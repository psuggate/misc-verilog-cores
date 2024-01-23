`timescale 1ns / 100ps
module usb_core_tb;

  parameter [31:0] PHASE = "1000";
  localparam NEGATE_CLOCK = PHASE[31:24] == "1";

  localparam PIPELINED = 1;

  initial begin
    $display("ULPI Reset module:");
    $display(" - Clock-negation: %1d", NEGATE_CLOCK);
  end


  // -- Simulation Data -- //

  initial begin
    $dumpfile("usb_core_tb.vcd");
    $dumpvars(0, usb_core_tb);

    #12000 $finish;  // todo ...
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

  // Check the output from the USB packet decoder //
  wire usb_rx_tvalid_w = U_USB_BRIDGE1.ulpi_rx_tvalid_w;
  wire usb_rx_tready_w = U_USB_BRIDGE1.ulpi_rx_tready_w;
  wire usb_rx_tlast_w = U_USB_BRIDGE1.ulpi_rx_tlast_w;
  wire [7:0] usb_rx_tdata_w = U_USB_BRIDGE1.ulpi_rx_tdata_w;

  axis_flow_check U_AXIS_FLOW2 (
      .clock(usb_clock),
      .reset(reset),
      .axis_tvalid(usb_rx_tvalid_w),
      .axis_tready(usb_rx_tready_w),
      .axis_tlast(usb_rx_tlast_w),
      .axis_tdata(usb_rx_tdata_w)
  );

  /*
  // Check the output to the USB packet encoder //
  wire usb_tx_tvalid_w = U_USB_BRIDGE1.ulpi_tx_tvalid_w;
  wire usb_tx_tready_w = U_USB_BRIDGE1.ulpi_tx_tready_w;
  wire usb_tx_tlast_w = U_USB_BRIDGE1.ulpi_tx_tlast_w;
  wire [7:0] usb_tx_tdata_w = U_USB_BRIDGE1.ulpi_tx_tdata_w;

  axis_flow_check U_AXIS_FLOW3 (
      .clock(usb_clock),
      .reset(reset),
      .axis_tvalid(usb_tx_tvalid_w),
      .axis_tready(usb_tx_tready_w),
      .axis_tlast(usb_tx_tlast_w),
      .axis_tdata(usb_tx_tdata_w)
  );
*/

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


  // -- Loop-back FIFO for Testing -- //

  wire [10:0] flevel;

  sync_fifo #(
      .WIDTH (10),
      .ABITS (11),
      .OUTREG(3)
  ) rddata_fifo_inst (
      .clock(dev_clock),
      .reset(dev_reset),

      .level_o(flevel),

      .valid_i(mvalid),
      .ready_o(mready),
      .data_i ({mkeep, mlast, mdata}),

      .valid_o(svalid),
      .ready_i(sready),
      .data_o ({skeep, slast, sdata})
  );


  reg [3:0] areset_n;

  always @(posedge usb_clock or negedge arst_n) begin
    if (!arst_n) begin
      areset_n <= 4'h0;
    end else begin
      areset_n <= {areset_n[2:0], 1'b1};
    end
  end


  //
  // Cores Under New Tests
  ///
  localparam USE_NEW_BRIDGE = 1;

  wire configured1, device_usb_idle1_w, dev_usb_sof1_w, dev_crc_err1_w;
  wire sready1, mvalid1, mlast1, ulpi_stp1;
  wire [7:0] ulpi_data1, mdata1;

  wire configured2, device_usb_idle2_w, dev_usb_sof2_w, dev_crc_err2_w;
  wire sready2, mvalid2, mlast2, ulpi_stp2;
  wire [7:0] ulpi_data2, mdata2;

  assign ulpi_stp = USE_NEW_BRIDGE ? ulpi_stp1 : ulpi_stp2;
  assign ulpi_data = ulpi_dir ? 8'bz : USE_NEW_BRIDGE ? ulpi_data1 : ulpi_data2;

  assign configured = USE_NEW_BRIDGE ? configured1 : configured2;
  assign usb_idle_w = USE_NEW_BRIDGE ? device_usb_idle1_w : device_usb_idle2_w;

  assign sready = USE_NEW_BRIDGE ? sready1 : sready2;

  assign mvalid = USE_NEW_BRIDGE ? mvalid1 : mvalid2;
  assign mlast = USE_NEW_BRIDGE ? mlast1 : mlast2;
  assign mdata = USE_NEW_BRIDGE ? mdata1 : mdata2;

  assign ulpi_data1 = ulpi_dir ? ulpi_data : 8'bz;
  assign ulpi_data2 = ulpi_dir ? ulpi_data : 8'bz;

  ulpi_axis_bridge #(
      .PIPELINED(PIPELINED),
      .EP1_CONTROL(0),
      .ENDPOINT1  (1),
      .EP2_CONTROL(0),
      .ENDPOINT2  (2)
  ) U_USB_BRIDGE1 (
      // .areset_n(arst_n),
      .areset_n(areset_n[3]),
      .reset_no(usb_rst_n),

      .ulpi_clock_i(usb_clock),
      .ulpi_dir_i  (ulpi_dir),
      .ulpi_nxt_i  (ulpi_nxt),
      .ulpi_stp_o  (ulpi_stp1),
      .ulpi_data_io(ulpi_data1),

      .usb_clock_o(dev_clock),
      .usb_reset_o(dev_reset),

      .configured_o(configured1),
      .usb_idle_o(device_usb_idle1_w),
      .usb_sof_o(dev_usb_sof1_w),
      .crc_err_o(dev_crc_err1_w),

      // USB bulk endpoint data-paths
      .blk_in_ready_i(configured1 && svalid),
      .blk_out_ready_i(configured1 && mready),
      .blk_start_o(),
      .blk_cycle_o(),
      .blk_endpt_o(),
      .blk_error_i(1'b0),

      .s_axis_tvalid_i(svalid),
      .s_axis_tready_o(sready1),
      .s_axis_tlast_i (slast),
      .s_axis_tkeep_i (skeep),
      .s_axis_tdata_i (sdata),

      .m_axis_tvalid_o(mvalid1),
      .m_axis_tready_i(mready),
      .m_axis_tlast_o (mlast1),
      .m_axis_tkeep_o (mkeep),
      .m_axis_tdata_o (mdata1)
  );

  ulpi_axis #(
      .EP1_CONTROL(0),
      .ENDPOINT1  (1),
      .EP2_CONTROL(0),
      .ENDPOINT2  (2)
  ) U_USB_BRIDGE2 (
      .areset_n(areset_n[3]),
      .reset_no(),

      .ulpi_clock_i(usb_clock),
      .ulpi_dir_i  (ulpi_dir),
      .ulpi_nxt_i  (ulpi_nxt),
      .ulpi_stp_o  (ulpi_stp2),
      .ulpi_data_io(ulpi_data2),

      .usb_clock_o(),
      .usb_reset_o(),

      .fifo_in_full_o(),

      .configured_o(configured2),
      .usb_idle_o(device_usb_idle2_w),
      .usb_sof_o(dev_usb_sof2_w),
      .crc_err_o(dev_crc_err2_w),

      // USB bulk endpoint data-paths
      .blk_in_ready_i(configured2 && svalid),
      .blk_out_ready_i(configured2 && mready),
      .blk_start_o(),
      .blk_cycle_o(),
      .blk_endpt_o(),
      .blk_error_i(1'b0),

      .s_axis_tvalid_i(svalid),
      .s_axis_tready_o(sready2),
      .s_axis_tlast_i (slast),
      .s_axis_tdata_i (sdata),

      .m_axis_tvalid_o(mvalid2),
      .m_axis_tready_i(mready),
      .m_axis_tlast_o (mlast2),
      .m_axis_tdata_o (mdata2)
  );


endmodule  // usb_core_tb
