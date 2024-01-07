`timescale 1ns / 100ps
module ulpi_axis_bridge #(
    parameter EP1_BULK_IN  = 1,
    parameter EP1_BULK_OUT = 1,
    parameter EP1_CONTROL  = 0,

    parameter EP2_BULK_IN  = 1,
    parameter EP2_BULK_OUT = 0,
    parameter EP2_CONTROL  = 0,

    parameter ENDPOINT1 = 1,  // todo: set to '0' to disable
    parameter ENDPOINT2 = 2,  // todo: set to '0' to disable

    parameter integer SERIAL_LENGTH = 8,
    parameter [SERIAL_LENGTH*8-1:0] SERIAL_STRING = "TART0001",

    parameter [15:0] VENDOR_ID = 16'hF4CE,
    parameter integer VENDOR_LENGTH = 19,
    parameter [VENDOR_LENGTH*8-1:0] VENDOR_STRING = "University of Otago",

    parameter [15:0] PRODUCT_ID = 16'h0003,
    parameter integer PRODUCT_LENGTH = 8,
    parameter [PRODUCT_LENGTH*8-1:0] PRODUCT_STRING = "TART USB"
) (
    // Global, asynchronous reset
    input  areset_n,
    output reset_no,

    // UTMI Low Pin Interface (ULPI)
    input ulpi_clock_i,
    input ulpi_dir_i,
    input ulpi_nxt_i,
    output ulpi_stp_o,
    inout [7:0] ulpi_data_io,

    // USB clock-domain clock & reset
    output usb_clock_o,
    output usb_reset_o,  // USB core is in reset state

    // Status flags for IN/OUT FIFOs, and the USB core
    output fifo_in_full_o,
    output fifo_out_full_o,
    output fifo_out_overflow_o,
    output fifo_has_data_o,

    output configured_o,
    output has_telemetry_o,
    output [7:0] usb_conf_o,
    output usb_sof_o,
    output crc_err_o,
    output crc_vld_o,
    output timeout_o,
    output usb_vbus_valid_o,
    output usb_hs_enabled_o,
    output usb_idle_o,  // USB core is idling
    output usb_suspend_o,  // USB core has been suspended
    output ulpi_rx_overflow_o,

    // USB Bulk Transfer parameters and data-streams
    input blk_in_ready_i,
    input blk_out_ready_i,
    output blk_start_o,
    output blk_cycle_o,
    output [3:0] blk_endpt_o,
    input blk_error_i,

    // AXI4-stream slave-port signals (IN: EP -> host)
    // Note: USB clock-domain
    input s_axis_tvalid_i,
    output s_axis_tready_o,
    input s_axis_tlast_i,
    input [7:0] s_axis_tdata_i,

    // AXI4-stream master-port signals (OUT: host -> EP)
    // Note: USB clock-domain
    output m_axis_tvalid_o,
    input m_axis_tready_i,
    output m_axis_tlast_o,
    output [7:0] m_axis_tdata_o
);


  // -- Constants -- //

  localparam HIGH_SPEED = 1;

  localparam CONFIG_DESC_LEN = 9;
  localparam INTERFACE_DESC_LEN = 9;
  localparam EP1_IN_DESC_LEN = 7;
  localparam EP1_OUT_DESC_LEN = 7;
  localparam EP2_IN_DESC_LEN = 7;

  localparam CONFIG_DESC = {
    8'h32,  // bMaxPower = 100 mA
    8'hC0,  // bmAttributes = Self-powered
    8'h00,  // iConfiguration
    8'h01,  // bConfigurationValue
    8'h01,  // bNumInterfaces = 1
    16'h0027,  // wTotalLength = 39
    8'h02,  // bDescriptionType = Configuration Descriptor
    8'h09  // bLength = 9
  };

  localparam INTERFACE_DESC = {
    8'h00,  // iInterface
    8'h00,  // bInterfaceProtocol
    8'h00,  // bInterfaceSubClass
    8'h00,  // bInterfaceClass
    8'h03,  // bNumEndpoints = 2
    8'h00,  // bAlternateSetting
    8'h00,  // bInterfaceNumber = 0
    8'h04,  // bDescriptorType = Interface Descriptor
    8'h09  // bLength = 9
  };

  localparam EP1_IN_DESC = {
    8'h00,  // bInterval
    16'h0200,  // wMaxPacketSize = 512 bytes
    8'h02,  // bmAttributes = Bulk
    8'h81,  // bEndpointAddress = IN1
    8'h05,  // bDescriptorType = Endpoint Descriptor
    8'h07  // bLength = 7
  };

  localparam EP1_OUT_DESC = {
    8'h00,  // bInterval
    16'h0200,  // wMaxPacketSize = 512 bytes
    8'h02,  // bmAttributes = Bulk
    8'h01,  // bEndpointAddress = OUT1
    8'h05,  // bDescriptorType = Endpoint Descriptor
    8'h07  // bLength = 7
  };

  localparam EP2_IN_DESC = {
    8'h00,  // bInterval
    16'h0200,  // wMaxPacketSize = 512 bytes
    8'h02,  // bmAttributes = Bulk
    8'h82,  // bEndpointAddress = IN2
    8'h05,  // bDescriptorType = Endpoint Descriptor
    8'h07  // bLength = 7
  };

  localparam integer CONF_DESC_SIZE = CONFIG_DESC_LEN + INTERFACE_DESC_LEN + EP1_IN_DESC_LEN + EP1_OUT_DESC_LEN + EP2_IN_DESC_LEN;
  localparam integer CONF_DESC_BITS = CONF_DESC_SIZE * 8;
  localparam integer CSB = CONF_DESC_BITS - 1;
  localparam [CSB:0] CONF_DESC_VALS = {
    EP2_IN_DESC, EP1_OUT_DESC, EP1_IN_DESC, INTERFACE_DESC, CONFIG_DESC
  };


  // -- Global Signals and Assignments -- //

  wire usb_reset_w, ulpi_rst_nw;

  reg rst_nq, rst_nr, rst_n1, rst_n0;
  wire clock, reset;

  reg blk_in_ready_q, tele_sel_q;
  wire [9:0] tele_level_w;

  reg usb_idle_q;

  assign usb_idle_o = usb_idle_q;

  assign s_axis_tready_o = ~tele_sel_q & mux_tready_w;

  assign usb_clock_o = clock;
  assign usb_reset_o = reset;

  assign clock = ulpi_clock_i;
  assign reset = ~rst_nq;
  assign ulpi_rst_nw = rst_n1;
  assign reset_no = ulpi_rst_nw;

  // Compute the reset signals
  always @(posedge clock or negedge areset_n) begin
    if (!areset_n) begin
      {rst_nq, rst_nr, rst_n1, rst_n0} <= 4'h0;
    end else begin
      {rst_nq, rst_nr, rst_n1, rst_n0} <= {rst_nr & ~usb_reset_w, rst_n1, rst_n0, areset_n};
    end
  end

  // ULPI signals
  wire [7:0] ulpi_data_iw, ulpi_data_ow;

  assign ulpi_data_io = ulpi_dir_i ? {8{1'bz}} : ulpi_data_ow;
  assign ulpi_data_iw = ulpi_data_io;


  // -- Local Signals and Assignments -- //

  wire ulpi_rx_tvalid_w, ulpi_rx_tready_w, ulpi_rx_tkeep_w, ulpi_rx_tlast_w;
  wire ulpi_tx_tvalid_w, ulpi_tx_tready_w, ulpi_tx_tkeep_w, ulpi_tx_tlast_w;
  wire [3:0] ulpi_rx_tuser_w, ulpi_tx_tuser_w;
  wire [7:0] ulpi_rx_tdata_w, ulpi_tx_tdata_w;

  wire [6:0] tok_addr_w;
  wire [3:0] tok_endp_w;


  // -- Signals and Assignments -- //

  // Signals for sending initialisation commands & settings to the PHY.
  wire phy_write_w, phy_stop_w, phy_chirp_w, phy_busy_w, phy_done_w;
  wire [7:0] phy_addr_w, phy_data_w;

  wire [1:0] LineState, VbusState, RxEvent;
  wire high_speed_w, encode_idle_w, decode_idle_w;
  wire pulse_2_5us_w, pulse_1_0ms_w;

  wire iob_dir_w, iob_nxt_w;
  wire [7:0] iob_dat_w;

  wire usb_enum_w;
  wire [6:0] usb_addr_w;

  wire ctl0_start_w, ctl0_cycle_w, ctl0_error_w;
  wire ctl0_tvalid_w, ctl0_tready_w, ctl0_tlast_w;
  wire [7:0] ctl0_tdata_w;

  wire [3:0] ctl_endpt_w;
  wire [7:0] ctl_rtype_w, ctl_rargs_w;
  wire [15:0] ctl_value_w, ctl_index_w, ctl_length_w;

  wire hsk_rx_recv_w, hsk_tx_send_w, hsk_tx_done_w;
  wire usb_rx_recv_w, usb_tx_busy_w, usb_tx_done_w;
  wire tok_rx_recv_w, tok_rx_ping_w;
  wire [1:0] tok_rx_type_w;
  wire [6:0] tok_rx_addr_w;
  wire [3:0] tok_rx_endp_w;

  wire blkx_tvalid_w, blkx_tlast_w, blkx_tready_w;
  wire [7:0] blkx_tdata_w;

  wire tel_tvalid_w, tel_tlast_w, tel_tready_w;
  wire [7:0] tel_tdata_w;


  // -- Status & Debug Flags -- //

  reg ctl_err_q, ctl_sel_q, usb_sof_q;

  always @(posedge clock) begin
    if (reset) begin
      ctl_err_q <= 1'b0;
      ctl_sel_q <= 1'b0;
      usb_sof_q <= 1'b0;
    end else begin
      if (ctl0_error_w) begin
        ctl_err_q <= 1'b1;
      end
      if (ctl0_cycle_w) begin
        ctl_sel_q <= 1'b1;
      end
      if (usb_sof_o) begin
        usb_sof_q <= 1'b1;
      end
    end
  end


  // -- Bulk IN Status -- //

  always @(posedge clock) begin
    tele_sel_q <= blk_endpt_o == ENDPOINT2;
    blk_in_ready_q <= blk_in_ready_i || tele_level_w[9:4] != 0;
  end


  // -- USB/ULPI Idle State -- //

  always @(posedge clock) begin
    if (!areset_n) begin
      usb_idle_q <= 1'b0;
    end else begin
      usb_idle_q <= ~ulpi_dir_i & high_speed_w & encode_idle_w & decode_idle_w;
    end
  end


  // -- Encode/decode USB ULPI packets, over the AXI4 streams -- //

  //
  //  Monitors USB 'LineState', and coordinates the high-speed negotiation on
  //  start-up.
  ///
  line_state #(
      .HIGH_SPEED(1)
  ) U_LINESTATE1 (
      .clock(clock),
      .reset(~areset_n),

      .LineState(LineState),
      .VbusState(VbusState),
      .RxEvent  (RxEvent),

      .ulpi_dir (ulpi_dir_i),
      .ulpi_nxt (ulpi_nxt_i),
      .ulpi_stp (ulpi_stp_o),
      .ulpi_data(ulpi_data_iw),

      .iob_dir_o(iob_dir_w),
      .iob_nxt_o(iob_nxt_w),
      .iob_dat_o(iob_dat_w),

      .high_speed_o(high_speed_w),

      .phy_write_o(phy_write_w),
      .phy_nopid_o(phy_chirp_w),
      .phy_stop_o (phy_stop_w),
      .phy_done_i (phy_done_w),
      .phy_addr_o (phy_addr_w),
      .phy_data_o (phy_data_w),

      .kj_start_i(1'b0),  // todo: for timing chirp minimum periods

      .pulse_2_5us_o(pulse_2_5us_w),
      .pulse_1_0ms_o(pulse_1_0ms_w)
  );


  // -- ULPI Decoder & Encoder -- //

  ulpi_decoder U_DECODER1 (
      .clock(clock),
      .reset(~areset_n),
      // .reset(reset),

      .LineState(LineState),
      .VbusState(VbusState),
      .RxEvent  (RxEvent),

      .ibuf_dir(ulpi_dir_i),
      .ibuf_nxt(ulpi_nxt_i),

      .ulpi_dir (iob_dir_w),
      .ulpi_nxt (iob_nxt_w),
      .ulpi_data(iob_dat_w),

      .crc_error_o  (crc_err_o),
      .crc_valid_o  (crc_vld_o),
      .decode_idle_o(decode_idle_w),

      .tok_recv_o(tok_rx_recv_w),
      .tok_addr_o(tok_addr_w),
      .tok_endp_o(tok_endp_w),
      .hsk_recv_o(hsk_rx_recv_w),
      .usb_recv_o(usb_rx_recv_w),

      .m_tvalid(ulpi_rx_tvalid_w),
      .m_tready(ulpi_rx_tready_w),
      .m_tkeep (ulpi_rx_tkeep_w),
      .m_tlast (ulpi_rx_tlast_w),
      .m_tuser (ulpi_rx_tuser_w),
      .m_tdata (ulpi_rx_tdata_w)
  );

  ulpi_encoder U_ENCODER1 (
      .clock(clock),
      .reset(~areset_n),

      .high_speed_i (high_speed_w),
      .encode_idle_o(encode_idle_w),

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

      .hsk_send_i(hsk_tx_send_w),
      .hsk_done_o(hsk_tx_done_w),
      .usb_busy_o(usb_tx_busy_w),
      .usb_done_o(usb_tx_done_w),

      .s_tvalid(ulpi_tx_tvalid_w),
      .s_tready(ulpi_tx_tready_w),
      .s_tkeep (ulpi_tx_tkeep_w),
      .s_tlast (ulpi_tx_tlast_w),
      .s_tuser (ulpi_tx_tuser_w),
      .s_tdata (ulpi_tx_tdata_w),

      .ulpi_dir (ulpi_dir_i),
      .ulpi_nxt (ulpi_nxt_i),
      .ulpi_stp (ulpi_stp_o),
      .ulpi_data(ulpi_data_ow)
  );


  // -- FSM for USB packets, handshakes, etc. -- //

  transactor #(
      .PIPELINED(1)
  ) U_TRANSACT1 (
      .clock(clock),
      .reset(reset),

      .usb_addr_i(usb_addr_w),
      .usb_timeout_error_o(timeout_o),

      // Signals from the USB packet decoder (upstream)
      .tok_recv_i(tok_rx_recv_w),
      .tok_ping_i(tok_rx_ping_w),
      .tok_type_i(ulpi_rx_tuser_w[3:2]),
      .tok_addr_i(tok_addr_w),
      .tok_endp_i(tok_endp_w),

      .hsk_recv_i(hsk_rx_recv_w),
      .hsk_type_i(ulpi_rx_tuser_w[3:2]),
      .hsk_send_o(hsk_tx_send_w),
      .hsk_sent_i(hsk_tx_done_w),

      /*
      .hsk_recv_i(hsk_rx_recv_w),
      .hsk_type_i(hsk_rx_type_w),
      .hsk_sent_i(hsk_tx_sent_w),
      .hsk_type_o(hsk_tx_type_w),

      .usb_recv_i(usb_rx_trecv_w),
      .usb_type_i(usb_rx_ttype_w),
      .usb_send_o(usb_tx_tsend_w),
      .usb_type_o(usb_tx_ttype_w),
*/

      // DATA0/1 info from the decoder, and to the encoder
      .usb_recv_i(usb_rx_recv_w),
      .usb_type_i(ulpi_rx_tuser_w[3:2]),
      .usb_busy_i(usb_tx_busy_w),
      .usb_sent_i(usb_tx_done_w),

      // USB control & bulk data received from host (via decoder)
      .usb_tvalid_i(ulpi_rx_tvalid_w),
      .usb_tready_o(ulpi_rx_tready_w),
      .usb_tkeep_i (ulpi_rx_tkeep_w),
      .usb_tlast_i (ulpi_rx_tlast_w),
      .usb_tuser_i (ulpi_rx_tuser_w),
      .usb_tdata_i (ulpi_rx_tdata_w),

      .usb_tvalid_o(ulpi_tx_tvalid_w),
      .usb_tready_i(ulpi_tx_tready_w),
      .usb_tkeep_o (ulpi_tx_tkeep_w),
      .usb_tlast_o (ulpi_tx_tlast_w),
      .usb_tuser_o (ulpi_tx_tuser_w),
      .usb_tdata_o (ulpi_tx_tdata_w),

      // USB bulk endpoint data-paths
      .blk_in_ready_i(blk_in_ready_q),
      .blk_out_ready_i(blk_out_ready_i),
      .blk_start_o(blk_start_o),
      .blk_cycle_o(blk_cycle_o),
      .blk_endpt_o(blk_endpt_o),
      .blk_error_i(blk_error_i),

      .blk_tvalid_i(blkx_tvalid_w),
      .blk_tready_o(blkx_tready_w),
      .blk_tlast_i (blkx_tlast_w),
      .blk_tdata_i (blkx_tdata_w),

      .blk_tvalid_o(m_axis_tvalid_o),
      .blk_tready_i(m_axis_tready_i),
      .blk_tlast_o (m_axis_tlast_o),
      .blk_tdata_o (m_axis_tdata_o),

      // To/from USB control transfer endpoints
      .ctl_start_o(ctl0_start_w),
      .ctl_cycle_o(ctl0_cycle_w),
      .ctl_error_i(ctl0_error_w),

      .ctl_endpt_o (ctl_endpt_w),
      .ctl_rtype_o (ctl_rtype_w),
      .ctl_rargs_o (ctl_rargs_w),
      .ctl_value_o (ctl_value_w),
      .ctl_index_o (ctl_index_w),
      .ctl_length_o(ctl_length_w),

      .ctl_tvalid_o(),
      .ctl_tready_i(1'b1),
      .ctl_tlast_o (),
      .ctl_tdata_o (),

      .ctl_tvalid_i(ctl0_tvalid_w),
      .ctl_tready_o(ctl0_tready_w),
      .ctl_tlast_i (ctl0_tlast_w),
      .ctl_tdata_i (ctl0_tdata_w)
  );


  // -- 2:1 MUX for Bulk IN vs Control Transfers -- //

  wire mux_tvalid_w, mux_tlast_w, mux_tready_w;
  wire [7:0] mux_tdata_w;

  assign mux_tvalid_w = tele_sel_q ? tel_tvalid_w : s_axis_tvalid_i;
  assign mux_tlast_w  = tele_sel_q ? tel_tlast_w : s_axis_tlast_i;
  assign mux_tdata_w  = tele_sel_q ? tel_tdata_w : s_axis_tdata_i;

  assign tel_tready_w = tele_sel_q & mux_tready_w;


  axis_skid #(
      .WIDTH (8),
      .BYPASS(1)
  ) U_AXIS_SKID2 (
      .clock(clock),
      .reset(reset),

      .s_tvalid(mux_tvalid_w),
      .s_tready(mux_tready_w),
      .s_tlast (mux_tlast_w),
      .s_tdata (mux_tdata_w),

      .m_tvalid(blkx_tvalid_w),
      .m_tready(blkx_tready_w),
      .m_tlast (blkx_tlast_w),
      .m_tdata (blkx_tdata_w)
  );


  // -- USB Default (PIPE0) Configuration Endpoint -- //

  ctl_pipe0 #(
      // Device string descriptors [Optional]
      .MANUFACTURER_LEN(VENDOR_LENGTH),
      .MANUFACTURER(VENDOR_STRING),
      .PRODUCT_LEN(PRODUCT_LENGTH),
      .PRODUCT(PRODUCT_STRING),
      .SERIAL_LEN(SERIAL_LENGTH),
      .SERIAL(SERIAL_STRING),

      // Configuration for the device endpoints
      .CONFIG_DESC_LEN(CONFIG_DESC_LEN),
      .CONFIG_DESC(CONFIG_DESC),

      // Product info
      .VENDOR_ID (VENDOR_ID),
      .PRODUCT_ID(PRODUCT_ID),

      // Of course
      .HIGH_SPEED(HIGH_SPEED)
  ) U_CFG_PIPE0 (
      .clock(clock),
      .reset(reset),

      .start_i (ctl0_start_w),
      .select_i(ctl0_cycle_w),
      .error_o (ctl0_error_w),

      .configured_o(configured_o),
      .usb_conf_o  (usb_conf_o[7:0]),
      .usb_enum_o  (usb_enum_w),
      .usb_addr_o  (usb_addr_w),

      .req_endpt_i (ctl_endpt_w),
      .req_type_i  (ctl_rtype_w),
      .req_args_i  (ctl_rargs_w),
      .req_value_i (ctl_value_w),
      .req_index_i (ctl_index_w),
      .req_length_i(ctl_length_w),

      // AXI4-Stream for device descriptors
      .m_tvalid_o(ctl0_tvalid_w),
      .m_tlast_o (ctl0_tlast_w),
      .m_tdata_o (ctl0_tdata_w),
      .m_tready_i(ctl0_tready_w)
  );


  // -- USB Telemetry Control Endpoint -- //

  wire [3:0] usb_state_w, ctl_state_w;
  wire [7:0] blk_state_w;


  assign has_telemetry_o = tele_level_w[9:2] != 0;

  assign usb_state_w = U_TRANSACT1.xfer_state_w;
  assign ctl_state_w = U_TRANSACT1.xctrl;
  assign blk_state_w = U_TRANSACT1.xbulk;


  // Capture telemetry, so that it can be read back from EP1
  bulk_telemetry #(
      .ENDPOINT(ENDPOINT2)
  ) U_TELEMETRY2 (
      .clock(clock),
`ifdef __icarus
      .reset(reset),
      .usb_enum_i(usb_enum_w),
`else
      .reset(1'b0),
      .usb_enum_i(1'b1),
`endif

      .crc_error_i(crc_err_o),
      .usb_state_i(usb_state_w),
      .ctl_state_i(ctl_state_w),
      .blk_state_i(blk_state_w),

      .start_i (blk_start_o),
      .select_i(blk_cycle_o),
      .endpt_i (blk_endpt_o),
      .error_o (),
      .level_o (tele_level_w),

      // Unused
      .s_tvalid(1'b0),
      .s_tready(),
      .s_tlast (1'b0),
      .s_tdata (8'hx),

      // AXI4-Stream for telemetry data
      .m_tvalid(tel_tvalid_w),
      .m_tlast (tel_tlast_w),
      .m_tdata (tel_tdata_w),
      .m_tready(tel_tready_w)
  );



endmodule  // ulpi_axis_bridge
