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

  // USB configuration
  localparam FPGA_VENDOR = "gowin";
  localparam FPGA_FAMILY = "gw2a";
  localparam [63:0] SERIAL_NUMBER = "GULP0123";

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


  wire clock, rst_n, reset, locked;
  wire axi_clk, ddr_clk, usb_clk, usb_rst_n;

  assign reset   = ~locked;
  assign axi_clk = clock;


  localparam DDR_FREQ_MHZ = 100;

  localparam IDIV_SEL = 3;
  localparam FBDIV_SEL = 28;
  localparam ODIV_SEL = 4;
  localparam SDIV_SEL = 2;


  // So 27.0 MHz divided by 4, then x29 = 195.75 MHz.
  gw2a_rpll #(
      .FCLKIN("27"),
      .IDIV_SEL(IDIV_SEL),
      .FBDIV_SEL(FBDIV_SEL),
      .ODIV_SEL(ODIV_SEL),
      .DYN_SDIV_SEL(SDIV_SEL)
  ) axis_rpll_inst (
      .clkout(ddr_clk),  // 200 MHz
      .clockd(clock),    // 100 MHz
      .lock  (locked),
      .clkin (clk_26)
  );


  // -- Start-up -- //

  reg rst_nq, ce_q, enab_q, enable;

  always @(posedge clk_26) begin
    rst_nq <= rst_n;
    ce_q   <= locked & rst_nq;
  end

  always @(posedge clock or negedge ce_q) begin
    if (!ce_q) begin
      enab_q <= 1'b0;
      enable <= 1'b0;
    end else begin
      enab_q <= ce_q;
      if (enab_q) begin
        enable <= 1'b1;
      end
    end
  end


  wire s_tvalid, s_tready, s_tlast;
  wire [7:0] s_tdata;

  wire m_tvalid, m_tready, m_tlast;
  wire [ 7:0] m_tdata;

  // Miscellaneous
  reg  [23:0] count;
  wire usb_sof, fifo_in_full, fifo_out_full, fifo_has_data, configured;

  reg ulpi_error_q, ulpi_rx_overflow, ulpi_usb_reset;
  wire flasher;

  // todo: does not work, as I need cross-domain clocking
  assign flasher = ulpi_error_q ? count[11] & count[10] : ~count[13] & ulpi_usb_reset;

  // assign leds = {~count[13], ~configured, ~fifo_in_full, ~fifo_out_full, 2'b11};
  assign leds = {~count[23], ~configured, ~device_usb_idle_w, ~ulpi_error_q, 2'b11};

  // always @(posedge usb_sof) begin
  always @(posedge ulpi_clk) begin
    if (!usb_rst_n) begin
      count <= 0;
    end else begin
      count <= count + 1;
    end
  end


  // -- Some Errors -- //

  always @(posedge usb_clk) begin
    if (!rst_n) begin
      ulpi_error_q <= 1'b0;
    end else if (ulpi_dir && ulpi_stp) begin
      ulpi_error_q <= 1'b1;
    end
  end

/*
  always @(posedge usb_clk) begin
    if (!rst_n) begin
      ulpi_error_q <= 1'b0;
    end else begin
      ulpi_error_q <= ulpi_rx_overflow;
    end
  end
*/


  // -- USB ULPI Bulk transfer endpoint (IN & OUT) -- //

  wire ulpi_data_t;
  wire [7:0] ulpi_data_o;

  assign ulpi_rst = usb_rst_n;
  assign usb_clk  = ~ulpi_clk;


  wire device_usb_idle_w, dev_crc_err_w;

  assign fifo_has_data = configured;

  assign ulpi_usb_reset = dev_crc_err_w;
  assign ulpi_rx_overflow = device_usb_idle_w;


  //
  // Core Under New Tests
  ///
  ulpi_axis #(
      .EP1_CONTROL(0),
      .ENDPOINT1  (0),
      .EP2_CONTROL(0),
      .ENDPOINT2  (0)
  ) U_ULPI_USB0 (
      .areset_n(1'b1), // rst_n),

      .ulpi_clock_i(usb_clk),
      .ulpi_reset_o(usb_rst_n),
      .ulpi_dir_i  (ulpi_dir),
      .ulpi_nxt_i  (ulpi_nxt),
      .ulpi_stp_o  (ulpi_stp),
      .ulpi_data_io(ulpi_data),

      .usb_clock_o(),
      .usb_reset_o(),

      .fifo_in_full_o(fifo_in_full),

      .configured_o(configured),
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


  // Loop-back FIFO for testing
  sync_fifo #(
      .WIDTH (9),
      .ABITS (11),
      .OUTREG(3)
  ) rddata_fifo_inst (
      .clock(usb_clk),
      .reset(~rst_n),

      .valid_i(s_tvalid),
      .ready_o(s_tready),
      .data_i ({s_tlast, s_tdata}),

      .valid_o(m_tvalid),
      .ready_i(m_tready),
      .data_o ({m_tlast, m_tdata})
  );


endmodule  // usb_demo_top
