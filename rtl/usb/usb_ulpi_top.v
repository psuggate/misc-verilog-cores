`timescale 1ns / 100ps
module usb_ulpi_top
  #( parameter USE_EP2_IN = 1,
     parameter USE_EP1_OUT = 1,

    parameter integer SERIAL_LENGTH = 8,
    parameter [SERIAL_LENGTH*8-1:0] SERIAL_STRING = "TART0001",

    parameter [15:0] VENDOR_ID = 16'hF4CE,
    parameter integer VENDOR_LENGTH = 19,
    parameter [VENDOR_LENGTH*8-1:0] VENDOR_STRING = "University of Otago",

    parameter [15:0] PRODUCT_ID = 16'h0003,
    parameter integer PRODUCT_LENGTH = 8,
    parameter [PRODUCT_LENGTH*8-1:0] PRODUCT_STRING = "TART USB"
     )
  (
    // Global, asynchronous reset & ULPI PHY reset
    input  areset_n,
    output reset_no,

    // UTMI Low Pin Interface (ULPI)
    input  ulpi_clock_i,
    input  ulpi_dir_i,
    input  ulpi_nxt_i,
    output ulpi_stp_o,
    inout [7:0] ulpi_data_io,

    // USB clock-domain clock & reset
    output usb_clock_o,
    output usb_reset_o,  // USB core is in reset state

    output configured_o,
    output [2:0] usb_conf_o,

    input bulk_in_packet_i,
    input bulk_out_space_i,

    output blk_start_o,
    output blk_cycle_o,
    output blk_fetch_o,
    output blk_store_o,
    output [3:0] blk_endpt_o,
    input blk_error_i,

    input  blki_tvalid_i,
    output blki_tready_o,
    input  blki_tlast_i,
    input  blki_tkeep_i,
    input [7:0] blki_tdata_i,

    output blko_tvalid_o,
    input  blko_tready_i,
    output blko_tlast_o,
    output blko_tkeep_o,
    output [7:0] blko_tdata_o
   );

  localparam integer PIPELINED = 1;
  localparam [3:0] ENDPOINT1 = 4'd1;
  localparam [3:0] ENDPOINT2 = 4'd2;

  localparam [7:0] EP_NUM = USE_EP1_OUT + USE_EP2_IN;

  localparam integer CONFIG_DESC_LEN = 9;
  localparam integer INTERFACE_DESC_LEN = 9;
  localparam integer CONFIG_TOTAL_LEN = CONFIG_DESC_LEN + INTERFACE_DESC_LEN + (EP_NUM*7);
  localparam [15:0] TOTAL_LEN = CONFIG_TOTAL_LEN;

  localparam [71:0] CONFIG_DESC = {
    8'h32,     // bMaxPower = 100 mA
    8'hC0,     // bmAttributes = Self-powered
    8'h00,     // iConfiguration
    8'h01,     // bConfigurationValue
    8'h01,     // bNumInterfaces = 1
    TOTAL_LEN, // wTotalLength = 39
    8'h02,     // bDescriptionType = Configuration Descriptor
    8'h09      // bLength = 9
  };

  localparam [71:0] INTERFACE_DESC = {
    8'h00,  // iInterface
    8'h00,  // bInterfaceProtocol
    8'h00,  // bInterfaceSubClass
    8'h00,  // bInterfaceClass
    EP_NUM, // bNumEndpoints = 2
    8'h00,  // bAlternateSetting
    8'h00,  // bInterfaceNumber = 0
    8'h04,  // bDescriptorType = Interface Descriptor
    8'h09   // bLength = 9
  };

  localparam integer EP1_DESC_LEN = USE_EP1_OUT ? 7 : 0;
  localparam integer EP1_DESC_BITS = EP1_DESC_LEN * 8;
  localparam integer EP2_DESC_LEN = USE_EP2_IN ? 7 : 0;
  localparam integer EP2_DESC_BITS = EP2_DESC_LEN * 8;
  localparam integer EP_DESC_LEN = EP1_DESC_LEN + EP2_DESC_LEN;
  localparam integer EP_DESC_BITS = EP1_DESC_BITS + EP2_DESC_BITS;

  localparam [55:0] EP1_OUT_DESC = {
    8'h00,  // bInterval
    16'h0200,  // wMaxPacketSize = 512 bytes
    8'h02,  // bmAttributes = Bulk
    8'h01,  // bEndpointAddress = OUT1
    8'h05,  // bDescriptorType = Endpoint Descriptor
    8'h07  // bLength = 7
  };

  localparam [55:0] EP2_IN_DESC = {
    8'h00,    // bInterval
    16'h0200, // wMaxPacketSize = 512 bytes
    8'h02,    // bmAttributes = Bulk
    8'h82,    // bEndpointAddress = IN2
    8'h05,    // bDescriptorType = Endpoint Descriptor
    8'h07     // bLength = 7
  };

  function [EP_DESC_BITS-1:0] ep_descriptors;
    begin
      if (EP1_DESC_BITS != 0) begin
        ep_descriptors[EP1_DESC_BITS-1:0] = EP1_OUT_DESC[55:0];
      end
      if (EP2_DESC_BITS != 0) begin
        ep_descriptors[EP1_DESC_BITS+EP2_DESC_BITS-1:EP1_DESC_BITS] = EP2_IN_DESC[55:0];
      end
    end
  endfunction

  localparam integer CONF_DESC_SIZE = CONFIG_DESC_LEN + INTERFACE_DESC_LEN + EP_DESC_LEN;
  localparam integer CONF_DESC_BITS = CONF_DESC_SIZE * 8;
  localparam integer CSB = CONF_DESC_BITS - 1;
  localparam [CSB:0] CONF_DESC_VALS = {ep_descriptors(), INTERFACE_DESC, CONFIG_DESC};

  // -- Encode/decode USB ULPI packets, over the AXI4 streams -- //

  wire parity1_w; // TODO: remove ...

  wire usb_idle_w, usb_enum_w, locked, clock, reset;
  wire high_speed_w, encode_idle_w, decode_idle_w, usb_reset_w, timeout_w;
  wire sof_rx_recv_w, eop_rx_recv_w, ulpi_rx_cmd_w;
  wire [3:0] phy_state_w, usb_state_w, ctl_state_w;
  wire [7:0] blk_state_w, ulpi_data_iw, ulpi_data_ow;

  wire [1:0] LineState, VbusState, RxEvent;

  wire iob_dir_w, iob_nxt_w;
  wire [7:0] iob_dat_w;

  wire tok_rx_recv_w, tok_rx_ping_w;
  wire [3:0] tok_endp_w;
  wire [6:0] tok_addr_w, usb_addr_w;

  wire hsk_tx_send_w, hsk_tx_done_w, usb_tx_busy_w, usb_tx_done_w;
  wire hsk_rx_recv_w, usb_rx_recv_w;
  wire ulpi_tx_tvalid_w, ulpi_tx_tready_w, ulpi_tx_tkeep_w, ulpi_tx_tlast_w;
  wire ulpi_rx_tvalid_w, ulpi_rx_tready_w, ulpi_rx_tkeep_w, ulpi_rx_tlast_w;
  wire [3:0] ulpi_tx_tuser_w, ulpi_rx_tuser_w;
  wire [7:0] ulpi_tx_tdata_w, ulpi_rx_tdata_w;

  wire pulse_2_5us_w, pulse_1_0ms_w;
  wire phy_write_w, phy_chirp_w, phy_stop_w, phy_busy_w, phy_done_w;
  wire [7:0] phy_addr_w, phy_data_w;

  wire blko_tvalid_w, blko_tready_w, blko_tlast_w, blko_tkeep_w;
  wire blki_tvalid_w, blki_tready_w, blki_tlast_w, blki_tkeep_w;
  wire [7:0] blko_tdata_w, blki_tdata_w;

  wire ctl0_start_w, ctl0_cycle_w, ctl0_event_w, ctl0_error_w;
  wire ctl0_tvalid_w, ctl0_tready_w, ctl0_tlast_w;
  wire [7:0] ctl0_tdata_w;
  wire [3:0] ctl_endpt_w;
  wire [7:0] ctl_rtype_w, ctl_rargs_w;
  wire [15:0] ctl_index_w, ctl_value_w, ctl_length_w;


  assign clock = ulpi_clock_i;
  assign reset = usb_reset_w;

  assign usb_clock_o = clock;
  assign usb_reset_o = reset;

  assign ulpi_data_io = ulpi_dir_i ? {8{1'bz}} : ulpi_data_ow;
  assign ulpi_data_iw = ulpi_data_io;


  //
  //  Monitors USB 'LineState', and coordinates the high-speed negotiation on
  //  start-up.
  ///

  line_state #(
      .HIGH_SPEED(1)
  ) U_LINESTATE1 (
      .clock        (clock),
      .reset        (~areset_n),

      .LineState    (LineState),
      .VbusState    (VbusState),
      .RxEvent      (RxEvent),

      .ulpi_dir     (ulpi_dir_i),
      .ulpi_nxt     (ulpi_nxt_i),
      .ulpi_stp     (ulpi_stp_o),
      .ulpi_data    (ulpi_data_iw),

      .iob_dir_o    (iob_dir_w),
      .iob_nxt_o    (iob_nxt_w),
      .iob_dat_o    (iob_dat_w),

      .usb_sof_i    (sof_rx_recv_w),
      .high_speed_o (high_speed_w),
      .usb_reset_o  (usb_reset_w),
      .ulpi_rx_cmd_o(ulpi_rx_cmd_w),
      .phy_state_o  (phy_state_w),

      .phy_write_o  (phy_write_w),
      .phy_nopid_o  (phy_chirp_w),
      .phy_stop_o   (phy_stop_w),
      .phy_busy_i   (phy_busy_w),
      .phy_done_i   (phy_done_w),
      .phy_addr_o   (phy_addr_w),
      .phy_data_o   (phy_data_w),

      .pulse_2_5us_o(pulse_2_5us_w),
      .pulse_1_0ms_o(pulse_1_0ms_w)
  );


  // -- ULPI Decoder & Encoder -- //

  ulpi_decoder U_DECODER1 (
      .clock      (clock),
      .reset      (reset),

      .LineState  (LineState),

      .ulpi_dir   (iob_dir_w),
      .ulpi_nxt   (iob_nxt_w),
      .ulpi_data  (iob_dat_w),

      // .crc_error_o(crc_err_o),
      // .crc_valid_o(crc_vld_o),
      .sof_recv_o (sof_rx_recv_w),
      .eop_recv_o (eop_rx_recv_w),
      .dec_idle_o (decode_idle_w),

      .tok_recv_o (tok_rx_recv_w),
      .tok_ping_o (tok_rx_ping_w),
      .tok_addr_o (tok_addr_w),
      .tok_endp_o (tok_endp_w),
      .hsk_recv_o (hsk_rx_recv_w),
      .usb_recv_o (usb_rx_recv_w),

      .m_tvalid   (ulpi_rx_tvalid_w),
      .m_tready   (ulpi_rx_tready_w),
      .m_tkeep    (ulpi_rx_tkeep_w),
      .m_tlast    (ulpi_rx_tlast_w),
      .m_tuser    (ulpi_rx_tuser_w),
      .m_tdata    (ulpi_rx_tdata_w)
  );

  ulpi_encoder U_ENCODER1 (
      .clock      (clock),
      .reset      (~areset_n),

      .high_speed_i (high_speed_w),
      .encode_idle_o(encode_idle_w),

      .LineState  (LineState),
      .VbusState  (VbusState),

      // Signals for controlling the ULPI PHY
      .phy_write_i(phy_write_w),
      .phy_nopid_i(phy_chirp_w),
      .phy_stop_i (phy_stop_w),
      .phy_busy_o (phy_busy_w),
      .phy_done_o (phy_done_w),
      .phy_addr_i (phy_addr_w),
      .phy_data_i (phy_data_w),

      .hsk_send_i (hsk_tx_send_w),
      .hsk_done_o (hsk_tx_done_w),
      .usb_busy_o (usb_tx_busy_w),
      .usb_done_o (usb_tx_done_w),

      .s_tvalid   (ulpi_tx_tvalid_w),
      .s_tready   (ulpi_tx_tready_w),
      .s_tkeep    (ulpi_tx_tkeep_w),
      .s_tlast    (ulpi_tx_tlast_w),
      .s_tuser    (ulpi_tx_tuser_w),
      .s_tdata    (ulpi_tx_tdata_w),

      .ulpi_dir   (ulpi_dir_i),
      .ulpi_nxt   (ulpi_nxt_i),
      .ulpi_stp   (ulpi_stp_o),
      .ulpi_data  (ulpi_data_ow)
  );


  // -- FSM for USB packets, handshakes, etc. -- //

  transactor #(
      .PIPELINED      (PIPELINED),
      .ENDPOINT1      (ENDPOINT1),
      .ENDPOINT2      (ENDPOINT2)
  ) U_TRANSACT1 (
      .clock          (clock),
      .reset          (reset),

      .usb_addr_i     (usb_addr_w),
      // .err_code_o     (err_code_w),
      .usb_timeout_error_o(timeout_w),
      .usb_device_idle_o(usb_idle_w),

      .parity1_o      (parity1_w),

      .usb_state_o    (usb_state_w),
      .ctl_state_o    (ctl_state_w),
      .blk_state_o    (blk_state_w),

      // Signals from the USB packet decoder (upstream)
      .tok_recv_i     (tok_rx_recv_w),
      .tok_ping_i     (tok_rx_ping_w),
      .tok_addr_i     (tok_addr_w),
      .tok_endp_i     (tok_endp_w),

      .hsk_recv_i     (hsk_rx_recv_w),
      .hsk_send_o     (hsk_tx_send_w),
      .hsk_sent_i     (hsk_tx_done_w),

      // DATA0/1 info from the decoder, and to the encoder
      .usb_recv_i     (usb_rx_recv_w),
      .eop_recv_i     (eop_rx_recv_w),
      .usb_busy_i     (usb_tx_busy_w),
      .usb_sent_i     (usb_tx_done_w),

      // USB control & bulk data received from host (via decoder)
      .usb_tvalid_i   (ulpi_rx_tvalid_w),
      .usb_tready_o   (ulpi_rx_tready_w),
      .usb_tkeep_i    (ulpi_rx_tkeep_w),
      .usb_tlast_i    (ulpi_rx_tlast_w),
      .usb_tuser_i    (ulpi_rx_tuser_w),
      .usb_tdata_i    (ulpi_rx_tdata_w),

      .usb_tvalid_o   (ulpi_tx_tvalid_w),
      .usb_tready_i   (ulpi_tx_tready_w),
      .usb_tkeep_o    (ulpi_tx_tkeep_w),
      .usb_tlast_o    (ulpi_tx_tlast_w),
      .usb_tuser_o    (ulpi_tx_tuser_w),
      .usb_tdata_o    (ulpi_tx_tdata_w),

      // USB bulk endpoint data-paths
      .blk_in_ready_i (bulk_in_packet_i),
      .blk_out_ready_i(bulk_out_space_i),

      .blk_start_o    (blk_start_o),
      .blk_cycle_o    (blk_cycle_o),
      .blk_fetch_o    (blk_fetch_o),
      .blk_store_o    (blk_store_o),
      .blk_endpt_o    (blk_endpt_o),
      .blk_error_i    (blk_error_i),

      .blk_tvalid_i   (blki_tvalid_i),
      .blk_tready_o   (blki_tready_o),
      .blk_tlast_i    (blki_tlast_i),
      .blk_tkeep_i    (blki_tkeep_i),
      .blk_tdata_i    (blki_tdata_i),

      .blk_tvalid_o   (blko_tvalid_o),
      .blk_tready_i   (blko_tready_i),
      .blk_tlast_o    (blko_tlast_o),
      .blk_tkeep_o    (blko_tkeep_o),
      .blk_tdata_o    (blko_tdata_o),

      // To/from USB control transfer endpoints
      .ctl_start_o    (ctl0_start_w),
      .ctl_cycle_o    (ctl0_cycle_w),
      .ctl_event_i    (ctl0_event_w),
      .ctl_error_i    (ctl0_error_w),

      .ctl_endpt_o    (ctl_endpt_w),
      .ctl_rtype_o    (ctl_rtype_w),
      .ctl_rargs_o    (ctl_rargs_w),
      .ctl_value_o    (ctl_value_w),
      .ctl_index_o    (ctl_index_w),
      .ctl_length_o   (ctl_length_w),

      .ctl_tvalid_o   (),
      .ctl_tready_i   (1'b1),
      .ctl_tlast_o    (),
      .ctl_tdata_o    (),

      .ctl_tvalid_i   (ctl0_tvalid_w),
      .ctl_tready_o   (ctl0_tready_w),
      .ctl_tlast_i    (ctl0_tlast_w),
      .ctl_tkeep_i    (ctl0_tvalid_w),
      .ctl_tdata_i    (ctl0_tdata_w)
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
      .CONFIG_DESC_LEN(CONF_DESC_SIZE),
      .CONFIG_DESC(CONF_DESC_VALS),

      // Product info
      .VENDOR_ID (VENDOR_ID),
      .PRODUCT_ID(PRODUCT_ID)
  ) U_CFG_PIPE0 (
      .clock       (clock),
      .reset       (reset),

      .start_i     (ctl0_start_w),
      .select_i    (ctl0_cycle_w),
      .error_o     (ctl0_error_w),
      .event_o     (ctl0_event_w),

      .configured_o(configured_o),
      .usb_conf_o  (usb_conf_o),
      .usb_enum_o  (usb_enum_w),
      .usb_addr_o  (usb_addr_w),

      .req_endpt_i (ctl_endpt_w),
      .req_type_i  (ctl_rtype_w),
      .req_args_i  (ctl_rargs_w),
      .req_value_i (ctl_value_w),
      .req_index_i (ctl_index_w),
      .req_length_i(ctl_length_w),

      // AXI4-Stream for device descriptors
      .m_tvalid_o  (ctl0_tvalid_w),
      .m_tlast_o   (ctl0_tlast_w),
      .m_tdata_o   (ctl0_tdata_w),
      .m_tready_i  (ctl0_tready_w)
  );


endmodule  /* usb_ulpi_top */
