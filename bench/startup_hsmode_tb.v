`timescale 1ns / 100ps
module startup_hsmode_tb;


  // -- Simulation Data -- //

  initial begin
    $dumpfile("startup_hsmode_tb.vcd");
    $dumpvars;

    #2000 $finish;  // todo ...
  end


  // -- Globals -- //

  reg clock = 1'b1, reset, arst_n;
  wire ulpi_clock;
  wire usb_clock, usb_rst_n, dev_clock, dev_reset;

  always #5 clock <= ~clock;

  initial begin
    reset  <= 1'b1;
    arst_n <= 1'b0;

    #40 arst_n <= 1'b1;
    #20 reset <= 1'b0;
  end


  // -- Simulation Signals -- //

  wire [1:0] LineState, VbusState, RxEvent;
  wire pulse_2_5us_w, pulse_1_0ms_w;
  wire ulpi_dir, ulpi_nxt, ulpi_stp;
  wire [7:0] ulpi_data;

  wire usb_tx_tvalid_w, usb_tx_tready_w, usb_tx_tlast_w;
  wire ulpi_rx_tvalid_w, ulpi_rx_tready_w, ulpi_rx_tlast_w;
  wire [7:0] usb_tx_tdata_w, ulpi_rx_tdata_w, ulpi_data_p, ulpi_data_w;

  wire high_speed_w, usb_busy_w, usb_done_w;
  wire phy_write_w, phy_chirp_w, phy_stop_w, phy_busy_w, phy_done_w;
  wire [7:0] phy_addr_w, phy_data_w;

  assign usb_tx_tvalid_w  = 1'b0;
  assign ulpi_rx_tready_w = 1'b0;

  fake_ulpi_phy U_ULPI_PHY0 (
      .clock(clock),
      .reset(reset),

      .ulpi_clock_o(ulpi_clock),
      .ulpi_rst_ni (arst_n),
      .ulpi_dir_o  (ulpi_dir),
      .ulpi_nxt_o  (ulpi_nxt),
      .ulpi_stp_i  (ulpi_stp),
      .ulpi_data_io(ulpi_data_p),

      // From the USB packet encoder
      .usb_tvalid_i(usb_tx_tvalid_w),
      .usb_tready_o(usb_tx_tready_w),
      .usb_tlast_i (usb_tx_tlast_w),
      .usb_tdata_i (usb_tx_tdata_w),

      // To the USB packet decoder
      .usb_tvalid_o(ulpi_rx_tvalid_w),
      .usb_tready_i(ulpi_rx_tready_w),
      .usb_tlast_o (ulpi_rx_tlast_w),
      .usb_tdata_o (ulpi_rx_tdata_w)
  );


  // -- Cores Under New Tests -- //

  // ULPI signals
  assign ulpi_data   = ulpi_dir ? ulpi_data_p : ulpi_data_w;
  assign ulpi_data_w = ulpi_dir ? ulpi_data_p : {8{1'bz}};
  assign ulpi_data_p = ulpi_dir ? {8{1'bz}} : ulpi_data_w;

  ulpi_encoder U_ENCODER1 (
      .clock(clock),
      .reset(~arst_n),

      .high_speed_i(high_speed_w),

      .LineState(LineState),
      .VbusState(VbusState),

      // Signals for controlling the ULPI PHY
      .phy_write_i(phy_write_w),
      .phy_nopid_i(phy_chirp_w),
      .phy_stop_i (phy_stop_w),
      .phy_busy_o (phy_busy_w),
      .phy_done_o (phy_done_w),
      .phy_addr_i (phy_addr_w),
      .phy_data_i (phy_data_w),

      .hsk_send_i(1'b0),
      .usb_busy_o(usb_busy_w),
      .usb_done_o(usb_done_w),

      .s_tvalid(1'b0),
      .s_tready(),
      .s_tkeep (1'b0),
      .s_tlast (1'b0),
      .s_tuser (4'h0),
      .s_tdata (8'hx),

      .ulpi_dir (ulpi_dir),
      .ulpi_nxt (ulpi_nxt),
      .ulpi_stp (ulpi_stp),
      .ulpi_data(ulpi_data_w)
  );

  line_state #(
      .HIGH_SPEED(1)
  ) U_LINESTATE1 (
      .clock(clock),
      .reset(~arst_n),

      .LineState(LineState),
      .VbusState(VbusState),
      .RxEvent  (RxEvent),

      .ulpi_dir (ulpi_dir),
      .ulpi_nxt (ulpi_nxt),
      .ulpi_stp (ulpi_stp),
      .ulpi_data(ulpi_data),

      .iob_dir_o(),
      .iob_nxt_o(),
      .iob_dat_o(),

      .high_speed_o(high_speed_w),

      .pulse_2_5us_o(pulse_2_5us_w),
      .pulse_1_0ms_o(pulse_1_0ms_w),

      .phy_write_o(phy_write_w),
      .phy_nopid_o(phy_chirp_w),
      .phy_stop_o (phy_stop_w),
      .phy_busy_i (phy_busy_w),
      .phy_done_i (phy_done_w),
      .phy_addr_o (phy_addr_w),
      .phy_data_o (phy_data_w)
  );


endmodule  // startup_hsmode_tb
