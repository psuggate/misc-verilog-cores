`timescale 1ns / 100ps
module usb_demo_top (
    // Clock and reset from the dev-board
    clk_26,
    rst_n,

    leds,

    // USB ULPI pins on the dev-board
    ulpi_clk,
    ulpi_rst,
    ulpi_dir,
    ulpi_nxt,
    ulpi_stp,
    ulpi_data
);

  // -- Constants -- //

  parameter integer SERIAL_LENGTH = 8;
  parameter [SERIAL_LENGTH*8-1:0] SERIAL_STRING = "TART0001";
  // localparam [63:0] SERIAL_NUMBER = "GULP0123";

  parameter [15:0] VENDOR_ID = 16'hF4CE;
  parameter integer VENDOR_LENGTH = 19;
  parameter [VENDOR_LENGTH*8-1:0] VENDOR_STRING = "University of Otago";

  parameter [15:0] PRODUCT_ID = 16'h0003;
  parameter integer PRODUCT_LENGTH = 8;
  parameter [PRODUCT_LENGTH*8-1:0] PRODUCT_STRING = "TART USB";

  // USB configuration
  localparam FPGA_VENDOR = "gowin";
  localparam FPGA_FAMILY = "gw2a";

  localparam HIGH_SPEED = 1'b1;


  input clk_26;
  input rst_n;

  output [5:0] leds;

  input ulpi_clk;
  output ulpi_rst;
  input ulpi_dir;
  input ulpi_nxt;
  output ulpi_stp;
  inout [7:0] ulpi_data;


  // -- Signals -- //

  // todo: what? how? where?
  // GSR GSR ();

  // Globalists //
  reg [4:0] rst_cnt = 0;
  wire clock, usb_clock, usb_reset;

  assign clock = ~ulpi_clk;

  always @(posedge clock or negedge rst_n) begin
    if (!rst_n) begin
      rst_cnt <= 5'd0;
    end else begin
      if (!rst_cnt[4]) begin
        rst_cnt <= rst_cnt + 5'd1;
      end
    end
  end

  // Local Signals //
  wire device_usb_idle_w, dev_crc_err_w, usb_hs_enabled_w;
  wire usb_sof, configured;

  // Data-path //
  wire s_tvalid, s_tready, s_tlast;
  wire [7:0] s_tdata;

  wire m_tvalid, m_tready, m_tlast;
  wire [7:0] m_tdata;


  // -- USB ULPI Bulk transfer endpoint (IN & OUT) -- //

  //
  // Core Under New Tests
  ///
  ulpi_axis #(
      .VENDOR_ID(VENDOR_ID),
      .VENDOR_LENGTH(VENDOR_LENGTH),
      .VENDOR_STRING(VENDOR_STRING),
      .PRODUCT_ID(PRODUCT_ID),
      .PRODUCT_LENGTH(PRODUCT_LENGTH),
      .PRODUCT_STRING(PRODUCT_STRING),
      .SERIAL_LENGTH(SERIAL_LENGTH),
      .SERIAL_STRING(SERIAL_STRING),
      .EP1_CONTROL(0),
      .ENDPOINT1(0),
      .EP2_CONTROL(0),
      .ENDPOINT2(0)
  ) U_ULPI_USB0 (
      .areset_n(rst_cnt[4]),

      .ulpi_clock_i(clock),
      .ulpi_reset_o(ulpi_rst),
      .ulpi_dir_i  (ulpi_dir),
      .ulpi_nxt_i  (ulpi_nxt),
      .ulpi_stp_o  (ulpi_stp),
      .ulpi_data_io(ulpi_data),

      .usb_clock_o(usb_clock),
      .usb_reset_o(usb_reset),

      .configured_o(configured),
      .usb_hs_enabled_o(usb_hs_enabled_w),
      .usb_idle_o(device_usb_idle_w),
      .usb_sof_o(usb_sof),
      .crc_err_o(dev_crc_err_w),

      .s_axis_tvalid_i(m_tvalid),
      .s_axis_tready_o(m_tready),
      .s_axis_tlast_i (m_tlast),
      .s_axis_tdata_i (m_tdata),

      .m_axis_tvalid_o(s_tvalid),
      .m_axis_tready_i(s_tready),
      .m_axis_tlast_o (s_tlast),
      .m_axis_tdata_o (s_tdata)
  );


  // -- Loop-back FIFO for Testing -- //

  sync_fifo #(
      .WIDTH (9),
      .ABITS (11),
      .OUTREG(3)
  ) rddata_fifo_inst (
      .clock(usb_clock),
      .reset(usb_reset),

      .valid_i(s_tvalid),
      .ready_o(s_tready),
      .data_i ({s_tlast, s_tdata}),

      .valid_o(m_tvalid),
      .ready_i(m_tready),
      .data_o ({m_tlast, m_tdata})
  );


  // -- LEDs Stuffs -- //

  localparam [1:0] TOK_SETUP = 2'b11;

  wire [ 3:0] cbits;

  // assign cbits = {dev_crc_err_w, U_ULPI_USB0.U_USB_CTRL0.U_USB_TRN0.state[2:0]};
  // assign cbits = U_ULPI_USB0.U_USB_CTRL0.U_USB_TRN0.xctrl[3:0];
  // assign cbits = U_ULPI_USB0.tx_counter[6:3];
  // assign cbits = U_ULPI_USB0.rx_counter[9:6];

  // Miscellaneous
  reg  [23:0] count;
  reg sof_q, ctl_latch_q = 0;
  reg [2:0] err_code_q;

  wire tok_setup_w = U_ULPI_USB0.U_USB_CTRL0.tok_rx_recv_w && U_ULPI_USB0.U_USB_CTRL0.tok_rx_type_w == TOK_SETUP;
  reg [6:0] usb_addr_q;
  always @(posedge usb_clock) begin
    if (usb_reset) begin
      usb_addr_q <= 7'h7c;
    end else begin
      if (tok_setup_w) begin
        usb_addr_q <= U_ULPI_USB0.U_USB_CTRL0.tok_rx_addr_w;
      end
    end
  end


  // wire ctl_select_w = U_ULPI_USB0.U_USB_CTRL0.U_USB_TRN0.state[1];
  wire ctl_select_w = U_ULPI_USB0.U_USB_CTRL0.U_USB_TRN0.err_start_q;

  // assign leds = {~count[10], ~ctl_latch_q, ~device_usb_idle_w, ~usb_hs_enabled_w, 2'b11};
  // assign leds = {~count[7], ~configured, ~device_usb_idle_w, ~flag_hsk_sent_w, 2'b11};
  // assign leds = {~count[7], ~flag_tok_recv_w, ~flag_hsk_recv_w, ~flag_hsk_sent_w, 2'b11};
  assign leds  = {~cbits[3:0], 2'b11};
  assign cbits = {ctl_latch_q, err_code_q};
  /*
                  U_ULPI_USB0.U_USB_CTRL0.ctl_sel_q,
                  // U_ULPI_USB0.U_USB_CTRL0.usb_sof_q,
                  U_ULPI_USB0.U_USB_CTRL0.hsk_recv_q,
                  U_ULPI_USB0.U_USB_CTRL0.hsk_sent_q
                  };

  always @(posedge usb_clock) begin
    if (ctl_select_w) begin
      ctl_latch_q <= 1'b1;
      err_code_q <= U_ULPI_USB0.U_USB_CTRL0.U_USB_TRN0.err_code_q;
    end
  end
*/

  reg lst_reset;
  always @(posedge usb_clock) begin
    lst_reset <= usb_reset;

    if (usb_reset && !lst_reset) begin
      {ctl_latch_q, err_code_q} <= U_ULPI_USB0.U_USB_CTRL0.U_USB_TRN0.xctrl;
    end
  end

  // always @(posedge usb_sof) begin
  always @(posedge usb_clock) begin
    if (usb_reset) begin
      count <= 0;
      sof_q <= 1'b0;
    end else begin
      sof_q <= usb_sof;

      if (usb_sof && !sof_q) begin
        count <= count + 1;
      end
    end
  end


endmodule  // usb_demo_top
