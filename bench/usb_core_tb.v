`timescale 1ns / 100ps
module usb_core_tb;


  // -- Simulation Data -- //

  initial begin
    $dumpfile("usb_core_tb.vcd");
    $dumpvars;

    #8000 $finish;  // todo ...
  end


  // -- Globals -- //

  reg clock = 1'b1, reset, arst_n;
  wire usb_clock, usb_rst_n, dev_clock, dev_reset;

  always #3 clock <= ~clock;

  initial begin
    reset  <= 1'b1;
    arst_n <= 1'b0;

    #20 arst_n <= 1'b1;
    #10 reset <= 1'b0;
  end


  // -- Simulation Signals -- //

  reg svalid, slast, mready;
  reg [7:0] sdata;
  wire mvalid, mlast, sready;
  wire [7:0] mdata;

  wire ulpi_dir_w, ulpi_nxt_w, ulpi_stp_w;
  wire [7:0] ulpi_data_w;

  reg enumerate;
  wire enum_done, device_usb_idle_w;

  wire host_usb_sof_w, host_crc_err_w;
  wire dev_usb_sof_w, dev_crc_err_w, fifo_in_full_w;


  // -- Initialisation -- //

  initial begin : Stimulus
    @(posedge clock);

    while (reset) begin
      @(posedge clock);

      svalid <= 1'b0;
      slast <= 1'b0;
      mready <= 1'b0;

      enumerate <= 1'b0;
    end

    @(posedge clock);
    @(posedge clock);

    enumerate <= 1'b1;
    @(posedge clock);

    while (!enum_done || !device_usb_idle_w) begin
      @(posedge clock);
    end
    enumerate <= 1'b0;
    @(posedge clock);

    #40 @(posedge clock);
    $finish;
  end


  fake_usb_host_ulpi U_FAKE_USB0 (
      .clock(clock),
      .reset(reset),

      .ulpi_clock_o(usb_clock),
      .ulpi_rst_ni (usb_rst_n),
      .ulpi_dir_o  (ulpi_dir_w),
      .ulpi_nxt_o  (ulpi_nxt_w),
      .ulpi_stp_i  (ulpi_stp_w),
      .ulpi_data_io(ulpi_data_w),

      .usb_sof_o(host_usb_sof_w),
      .crc_err_o(host_crc_err_w),

      .dev_enum_start_i(enumerate),
      .dev_enum_done_o (enum_done)
  );


  //
  // Core Under New Tests
  ///
  ulpi_axis U_ULPI_USB0 (
      .areset_n(arst_n),
      .ulpi_clock_i(usb_clock),
      .ulpi_reset_o(usb_rst_n),
      .ulpi_dir_i(ulpi_dir_w),
      .ulpi_nxt_i(ulpi_nxt_w),
      .ulpi_stp_o(ulpi_stp_w),
      .ulpi_data_io(ulpi_data_w),

      .usb_clock_o(dev_clock),
      .usb_reset_o(dev_reset),

      .fifo_in_full_o(fifo_in_full_w),

      .usb_idle_o(device_usb_idle_w),
      .usb_sof_o (dev_usb_sof_w),
      .crc_err_o (dev_crc_err_w),

      .s_axis_tvalid_i(svalid),
      .s_axis_tready_o(sready),
      .s_axis_tlast_i (slast),
      .s_axis_tdata_i (sdata),

      .m_axis_tvalid_o(mvalid),
      .m_axis_tready_i(mready),
      .m_axis_tlast_o (mlast),
      .m_axis_tdata_o (mdata)
  );


endmodule  // usb_core_tb
