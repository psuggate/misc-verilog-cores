`timescale 1ns / 100ps
module usb_ulpi_top #(
    parameter USE_EP2_IN  = 1,
    parameter USE_EP1_OUT = 1,

    parameter integer SERIAL_LENGTH = 8,
    parameter [SERIAL_LENGTH*8-1:0] SERIAL_STRING = "TART0001",

    parameter [15:0] VENDOR_ID = 16'hF4CE,
    parameter integer VENDOR_LENGTH = 19,
    parameter [VENDOR_LENGTH*8-1:0] VENDOR_STRING = "University of Otago",

    parameter [15:0] PRODUCT_ID = 16'h0003,
    parameter integer PRODUCT_LENGTH = 8,
    parameter [PRODUCT_LENGTH*8-1:0] PRODUCT_STRING = "TART USB"
) (
    // Global, asynchronous reset & ULPI PHY reset
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

    output configured_o,
    output [2:0] usb_conf_o,

    // input bulk_in_packet_i,
    // input bulk_out_space_i,

    output blk_start_o,
    output blk_cycle_o,
    output blk_fetch_o,
    output blk_store_o,
    output [3:0] blk_endpt_o,
    input blk_error_i,

    input blki_tvalid_i,
    output blki_tready_o,
    input blki_tlast_i,
    input blki_tkeep_i,
    input [7:0] blki_tdata_i,

    output blko_tvalid_o,
    input blko_tready_i,
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
  localparam integer CONFIG_TOTAL_LEN = CONFIG_DESC_LEN + INTERFACE_DESC_LEN + (EP_NUM * 7);
  localparam [15:0] TOTAL_LEN = CONFIG_TOTAL_LEN;

  localparam [71:0] CONFIG_DESC = {
    8'h32,  // bMaxPower = 100 mA
    8'hC0,  // bmAttributes = Self-powered
    8'h00,  // iConfiguration
    8'h01,  // bConfigurationValue
    8'h01,  // bNumInterfaces = 1
    TOTAL_LEN,  // wTotalLength = 39
    8'h02,  // bDescriptionType = Configuration Descriptor
    8'h09  // bLength = 9
  };

  localparam [71:0] INTERFACE_DESC = {
    8'h00,  // iInterface
    8'h00,  // bInterfaceProtocol
    8'h00,  // bInterfaceSubClass
    8'h00,  // bInterfaceClass
    EP_NUM,  // bNumEndpoints = 2
    8'h00,  // bAlternateSetting
    8'h00,  // bInterfaceNumber = 0
    8'h04,  // bDescriptorType = Interface Descriptor
    8'h09  // bLength = 9
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
    8'h00,  // bInterval
    16'h0200,  // wMaxPacketSize = 512 bytes
    8'h02,  // bmAttributes = Bulk
    8'h82,  // bEndpointAddress = IN2
    8'h05,  // bDescriptorType = Endpoint Descriptor
    8'h07  // bLength = 7
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

  wire parity1_w;  // TODO: remove ...
  wire space_avail_w, has_packet_w, crc_error_w;

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

  wire ep1_tvalid_w, ep1_tready_w, ep1_tkeep_w, ep1_tlast_w;
  wire ep2_tvalid_w, ep2_tready_w, ep2_tkeep_w, ep2_tlast_w;
  wire [3:0] ep2_tuser_w;
  wire [7:0] ep1_tdata_w, ep2_tdata_w;

  wire ep0_end_w;
  wire ep0_par_w, ep1_par_w, ep2_par_w;
  wire ep0_sel_w, ep1_sel_w, ep2_sel_w;


  assign clock = ulpi_clock_i;
  assign reset = usb_reset_w;

  assign usb_clock_o = clock;
  assign usb_reset_o = reset;

  assign ulpi_data_io = ulpi_dir_i ? {8{1'bz}} : ulpi_data_ow;
  assign ulpi_data_iw = ulpi_data_io;


  //
  //  Bulk IN & OUT End-Point selects and ACKs
  ///

  wire ep1_hlt_w, ep2_hlt_w;
  wire bulk_err_w, ack_recv_w, ack_sent_w;

  assign ack_recv_w = blk_cycle_o && hsk_rx_recv_w && ulpi_rx_tuser_w == `USBPID_ACK;
  assign ack_sent_w = blk_cycle_o && hsk_tx_done_w && ulpi_tx_tuser_w == `USBPID_ACK;

  reg ep1_sel_q, ep1_ack_q, ep1_err_q;
  reg ep1_sel_c, ep1_ack_c, ep1_err_c;

  always @* begin
    ep1_sel_c = ep1_sel_q;
    ep1_ack_c = 1'b0;
    ep1_err_c = 1'b0;

    if (USE_EP1_OUT && blk_endpt_o == ENDPOINT1) begin
      if (blk_start_o) begin
        ep1_sel_c = 1'b1;
      end else if (bulk_err_w && ack_recv_w) begin
        ep1_sel_c = 1'b0;
      end
      ep1_ack_c = ep1_sel_q & ack_sent_w;
      ep1_err_c = ep1_sel_q & bulk_err_w;
    end

    if (reset) begin
      {ep1_err_c, ep1_ack_c, ep1_sel_c} = 3'd0;
    end
  end

  reg ep2_sel_q, ep2_ack_q, ep2_err_q;
  reg ep2_sel_c, ep2_ack_c, ep2_err_c;

  always @* begin
    ep2_sel_c = ep2_sel_q;
    ep2_ack_c = 1'b0;
    ep2_err_c = 1'b0;

    if (USE_EP2_IN && blk_endpt_o == ENDPOINT2) begin
      if (blk_start_o) begin
        ep2_sel_c = 1'b1;
      end else if (bulk_err_w && ack_recv_w) begin
        ep2_sel_c = 1'b0;
      end
      ep2_ack_c = ep2_sel_q & ack_recv_w;
      ep2_err_c = ep2_sel_q & bulk_err_w;
    end

    if (reset) begin
      {ep2_err_c, ep2_ack_c, ep2_sel_c} = 3'd0;
    end
  end

  always @(posedge clock) begin
    ep1_sel_q <= ep1_sel_c;
    ep1_ack_q <= ep1_ack_c;
    ep1_err_q <= ep1_err_c;

    ep2_sel_q <= ep2_sel_c;
    ep2_ack_q <= ep2_ack_c;
    ep2_err_q <= ep2_err_c;
  end


  //
  //  Monitors USB 'LineState', and coordinates the high-speed negotiation on
  //  start-up.
  ///

  line_state #(
      .HIGH_SPEED(1)
  ) U_LS1 (
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

      .usb_sof_i    (sof_rx_recv_w),
      .high_speed_o (high_speed_w),
      .usb_reset_o  (usb_reset_w),
      .ulpi_rx_cmd_o(ulpi_rx_cmd_w),
      .phy_state_o  (phy_state_w),

      .phy_write_o(phy_write_w),
      .phy_nopid_o(phy_chirp_w),
      .phy_stop_o (phy_stop_w),
      .phy_busy_i (phy_busy_w),
      .phy_done_i (phy_done_w),
      .phy_addr_o (phy_addr_w),
      .phy_data_o (phy_data_w),

      .pulse_2_5us_o(pulse_2_5us_w),
      .pulse_1_0ms_o(pulse_1_0ms_w)
  );


  // -- ULPI Decoder & Encoder -- //

  ulpi_decoder U_DEC1 (
      .clock(clock),
      .reset(reset),

      .LineState(LineState),

      .ulpi_dir (iob_dir_w),
      .ulpi_nxt (iob_nxt_w),
      .ulpi_data(iob_dat_w),

      .crc_error_o(crc_error_w),
      .sof_recv_o (sof_rx_recv_w),
      .eop_recv_o (eop_rx_recv_w),
      .dec_idle_o (decode_idle_w),

      .tok_recv_o(tok_rx_recv_w),
      .tok_ping_o(tok_rx_ping_w),
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

  ulpi_encoder U_ENC1 (
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
      .PIPELINED(PIPELINED),
      .ENDPOINT1(ENDPOINT1),
      .ENDPOINT2(ENDPOINT2)
  ) U_XACT1 (
      .clock(clock),
      .reset(reset),

      .usb_addr_i         (usb_addr_w),
      // .err_code_o     (err_code_w),
      .usb_timeout_error_o(timeout_w),
      .usb_device_idle_o  (usb_idle_w),

      .parity1_o(parity1_w),

      .usb_state_o(usb_state_w),
      .ctl_state_o(ctl_state_w),
      .blk_state_o(blk_state_w),

      // USB token signals from the USB packet decoder (upstream), and to the
      // packet encoder
      .tok_recv_i(tok_rx_recv_w),
      .tok_ping_i(tok_rx_ping_w),
      .tok_addr_i(tok_addr_w),
      .tok_endp_i(tok_endp_w),

      .hsk_recv_i(hsk_rx_recv_w),
      .hsk_send_o(hsk_tx_send_w),
      .hsk_sent_i(hsk_tx_done_w),

      // DATA0/1 info from the decoder, and to the encoder
      .usb_recv_i(usb_rx_recv_w),
      .eop_recv_i(eop_rx_recv_w),
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
      .blk_in_ready_i (has_packet_w),
      .blk_out_ready_i(space_avail_w),
      // .blk_in_ready_i (bulk_in_packet_i),
      // .blk_out_ready_i(bulk_out_space_i),

      .blk_start_o(blk_start_o),
      .blk_cycle_o(blk_cycle_o),
      .blk_fetch_o(blk_fetch_o),
      .blk_store_o(blk_store_o),
      .blk_error_o(bulk_err_w),
      .blk_endpt_o(blk_endpt_o),
      .blk_error_i(blk_error_i),

      .blk_tvalid_i(ep2_tvalid_w),
      .blk_tready_o(ep2_tready_w),
      .blk_tlast_i (ep2_tlast_w),
      .blk_tkeep_i (ep2_tkeep_w),
      .blk_tdata_i (ep2_tdata_w),

      .blk_tvalid_o(ep1_tvalid_w),
      .blk_tready_i(ep1_tready_w),
      .blk_tlast_o (ep1_tlast_w),
      .blk_tkeep_o (ep1_tkeep_w),
      .blk_tdata_o (ep1_tdata_w),

      // To/from USB control transfer endpoints
      .ctl_start_o(ctl0_start_w),
      .ctl_cycle_o(ctl0_cycle_w),
      .ctl_event_i(ctl0_event_w),
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
      .ctl_tkeep_i (ctl0_tvalid_w),
      .ctl_tdata_i (ctl0_tdata_w)
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
  ) U_CTL0 (
      .clock(clock),
      .reset(reset),

      .start_i (ctl0_start_w),
      .select_i(ctl0_cycle_w),
      .error_o (ctl0_error_w),
      .event_o (ctl0_event_w),

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
      .m_tvalid_o(ctl0_tvalid_w),
      .m_tlast_o (ctl0_tlast_w),
      .m_tdata_o (ctl0_tdata_w),
      .m_tready_i(ctl0_tready_w)
  );


  // -- USB Bulk IN & OUT End-Points -- //

  ep_bulk_out #(
      .ENABLED(USE_EP1_OUT),
      .DUMPSTER(1)  // TODO
  ) U_OUT_EP1 (
      .clock     (clock),
      .reset     (reset),
      .set_conf_i(ctl0_event_w),
      .clr_conf_i(ctl0_error_w),
      // .selected_i(ep1_sel_q),
      .selected_i(ep1_sel_w),
      .ack_sent_i(ep1_ack_q),      // Todo ...
      .rx_error_i(ep1_err_q),
      .ep_ready_o(space_avail_w),
      .stalled_o (ep1_hlt_w),
      .parity_o  (ep1_par_w),
      .s_tvalid  (ep1_tvalid_w),
      .s_tready  (ep1_tready_w),
      .s_tkeep   (ep1_tkeep_w),
      .s_tlast   (ep1_tlast_w),
      .s_tdata   (ep1_tdata_w),
      .m_tvalid  (blko_tvalid_o),
      .m_tready  (blko_tready_i),
      .m_tkeep   (blko_tkeep_o),
      .m_tlast   (blko_tlast_o),
      .m_tdata   (blko_tdata_o)
  );

  // Todo: OBSOLETE
  assign ep2_tuser_w = ep2_par_w ? `USBPID_DATA1 : `USBPID_DATA0;

  ep_bulk_in #(
      .ENABLED(USE_EP2_IN),
      .CONSTANT(1)  // TODO
  ) U_IN_EP2 (
      .clock     (clock),
      .reset     (reset),
      .set_conf_i(ctl0_event_w),
      .clr_conf_i(ctl0_error_w),
      // .selected_i(ep2_sel_q),
      .selected_i(ep2_sel_w),
      .ack_recv_i(ep2_ack_q),
      .timedout_i(ep2_err_q),
      .ep_ready_o(has_packet_w),
      .stalled_o (ep2_hlt_w),
      .parity_o  (ep2_par_w),
      .s_tvalid  (blki_tvalid_i),
      .s_tready  (blki_tready_o),
      .s_tlast   (blki_tlast_i),
      .s_tdata   (blki_tdata_i),
      .m_tvalid  (ep2_tvalid_w),
      .m_tready  (ep2_tready_w),
      .m_tkeep   (ep2_tkeep_w),
      .m_tlast   (ep2_tlast_w),
      .m_tdata   (ep2_tdata_w)
  );

  wire stdreq_select_w, stdreq_parity_w, stdreq_finish_w;
  wire mux_enable_w;
  wire [2:0] mux_select_w;
  wire [3:0] ulpi_tuser_w;

  // Todo: move this into 'ctl_pipe0' or 'stdreq' !?
  reg [6:0] usb_addr_q;
  wire [6:0] ctl_addr_w;

  always @(posedge clock) begin
    if (reset) begin
      usb_addr_q <= 7'd0;
    end else if (stdreq_finish_w) begin
      usb_addr_q <= ctl_addr_w;
    end
  end

  protocol #(
      .BULK_EP1   (1),
      .USE_EP1_IN (0),
      .USE_EP1_OUT(1),
      .BULK_EP2   (2),
      .USE_EP2_IN (1),
      .USE_EP2_OUT(0),
      .BULK_EP3   (0),
      .BULK_EP4   (0)
  ) U_PROTO1 (
      .clock(clock),
      .reset(reset),

      .set_conf_i (ctl0_event_w),
      .clr_conf_i (ctl0_error_w),
      .usb_addr_i (usb_addr_q),
      .crc_error_i(crc_error_w),

      .tok_recv_i(tok_rx_recv_w),
      .tok_ping_i(tok_rx_ping_w),
      .tok_addr_i(tok_addr_w),
      .tok_endp_i(tok_endp_w),

      .hsk_recv_i(hsk_rx_recv_w),
      .hsk_send_o(),
      .hsk_sent_i(hsk_tx_done_w),

      .usb_recv_i(usb_rx_recv_w),
      .eop_recv_i(eop_rx_recv_w),
      .usb_sent_i(usb_tx_done_w),
      .usb_pid_i (ulpi_rx_tuser_w),

      .mux_enable_o(mux_enable_w),
      .mux_select_o(mux_select_w),
      .ulpi_tuser_o(ulpi_tuser_w),

      .ep0_select_i(stdreq_select_w),
      .ep0_parity_i(stdreq_parity_w),
      .ep0_finish_i(stdreq_finish_w),

      .ep1_select_o(ep1_sel_w),
      .ep1_rx_rdy_i(space_avail_w),
      .ep1_tx_rdy_i(1'b0),
      .ep1_parity_i(ep1_par_w),
      .ep1_halted_i(ep1_hlt_w),

      .ep2_select_o(ep2_sel_w),
      .ep2_rx_rdy_i(1'b0),
      .ep2_tx_rdy_i(has_packet_w),
      .ep2_parity_i(ep2_par_w),
      .ep2_halted_i(ep2_hlt_w),

      .ep3_rx_rdy_i(),
      .ep3_tx_rdy_i(),
      .ep3_parity_i(),
      .ep3_halted_i(),
      .ep3_select_o(),

      .ep4_rx_rdy_i(),
      .ep4_tx_rdy_i(),
      .ep4_parity_i(),
      .ep4_halted_i(),
      .ep4_select_o()
  );

  wire unused_tready_w;
  wire dec_tvalid_w, dec_tready_w, dec_tkeep_w, dec_tlast_w;
  // wire [3:0] dec_tuser_w;
  wire [7:0] dec_tdata_w;

  wire req_start_w, req_cycle_w, req_event_w, req_error_w;
  wire [7:0] req_rtype_w, req_rargs_w;
  wire [15:0] req_value_w, req_index_w, req_length_w;

  wire stdreq_tvalid_w, stdreq_tready_w, stdreq_tkeep_w, stdreq_tlast_w;
  wire [3:0] stdreq_tuser_w;
  wire [7:0] stdreq_tdata_w;

  wire [3:0] req_endpt_w = tok_endp_w;  // Todo ...

  assign dec_tready_w   = 1'b1;  // Todo ...

  // assign stdreq_tready_w = 1'b1; // Todo ...
  assign stdreq_tkeep_w = stdreq_tvalid_w;
  assign stdreq_tuser_w = stdreq_parity_w ? `USBPID_DATA1 : `USBPID_DATA0;

  stdreq #(
      .EP0_ONLY(1)
  ) U_STDREQ1 (
      .clock(clock),
      .reset(reset),

      // USB device current configuration
      .enumerated_i(usb_enum_w),
      .configured_i(configured_o),
      .usb_addr_i  (usb_addr_q),

      // Signals from the USB packet decoder (upstream)
      .tok_recv_i(tok_rx_recv_w),
      .tok_addr_i(tok_addr_w),
      .tok_endp_i(tok_endp_w),
      .hsk_recv_i(hsk_rx_recv_w),
      .hsk_sent_i(hsk_tx_done_w),

      .usb_recv_i(usb_rx_recv_w),
      .eop_recv_i(eop_rx_recv_w),
      .usb_sent_i(usb_tx_done_w),

      // To the device control pipe(s)
      .req_start_o (req_start_w),
      .req_cycle_o (req_cycle_w),
      .req_event_i (req_event_w),
      .req_error_i (req_error_w),
      .req_rtype_o (req_rtype_w),
      .req_rargs_o (req_rargs_w),
      .req_value_o (req_value_w),
      .req_index_o (req_index_w),
      .req_length_o(req_length_w),

      // From the USB protocol logic
      .select_o (stdreq_select_w),
      .parity_o (stdreq_parity_w),
      .finish_o (stdreq_finish_w),
      .timeout_i(timeout_w),

      // From the packet decoder
      .s_tvalid(ulpi_rx_tvalid_w),
      .s_tready(),  // Todo ...
      .s_tkeep(ulpi_rx_tkeep_w),
      .s_tlast(ulpi_rx_tlast_w),
      .s_tuser(ulpi_rx_tuser_w),
      .s_tdata(ulpi_rx_tdata_w),

      // To the packet encoder
      .m_tvalid(),
      .m_tready(1'b0),  // Todo ...
      .m_tkeep (),
      .m_tlast (),
      .m_tuser (),
      .m_tdata ()
  );

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
  ) U_CTL1 (
      .clock(clock),
      .reset(reset),

      // .configured_o(configured_o),
      // .usb_conf_o  (usb_conf_o),
      // .usb_enum_o  (usb_enum_w),
      .usb_addr_o(ctl_addr_w),

      .start_i (req_start_w),
      .select_i(req_cycle_w),
      .error_o (req_error_w),
      .event_o (req_event_w),

      .req_endpt_i (req_endpt_w),
      .req_type_i  (req_rtype_w),
      .req_args_i  (req_rargs_w),
      .req_value_i (req_value_w),
      .req_index_i (req_index_w),
      .req_length_i(req_length_w),

      // AXI4-Stream for device descriptors, to ULPI encoder
      .m_tvalid_o(stdreq_tvalid_w),
      .m_tlast_o (stdreq_tlast_w),
      .m_tdata_o (stdreq_tdata_w),
      .m_tready_i(stdreq_tready_w)
  );

  axis_mux #(
      .S_COUNT(3),
      .DATA_WIDTH(8),
      .KEEP_ENABLE(1),
      .KEEP_WIDTH(1),
      .ID_ENABLE(0),
      .ID_WIDTH(1),
      .DEST_ENABLE(0),
      .DEST_WIDTH(1),
      .USER_ENABLE(1),
      .USER_WIDTH(4)
  ) U_MUX1 (
      .clk(clock),
      .rst(reset),

      .enable(mux_enable_w),
      .select(mux_select_w),

      .s_axis_tvalid({ep2_tvalid_w, 1'd0, stdreq_tvalid_w}),
      // .s_axis_tready({ep2_tready_w, unused_tready_w, stdreq_tready_w}),
      .s_axis_tready({unused_tready_w, unused_tready_w, stdreq_tready_w}),
      .s_axis_tkeep ({ep2_tkeep_w, 1'd0, stdreq_tkeep_w}),
      .s_axis_tlast ({ep2_tlast_w, 1'd0, stdreq_tlast_w}),
      .s_axis_tuser ({ep2_tuser_w, 4'd0, stdreq_tuser_w}),
      .s_axis_tid   ('bx),
      .s_axis_tdest ('bx),
      .s_axis_tdata ({ep2_tdata_w, 8'd0, stdreq_tdata_w}),

      .m_axis_tvalid(dec_tvalid_w),
      .m_axis_tready(dec_tready_w),
      .m_axis_tkeep (dec_tkeep_w),
      .m_axis_tlast (dec_tlast_w),
      // .m_axis_tuser (dec_tuser_w),
      .m_axis_tid   (),
      .m_axis_tdest (),
      .m_axis_tdata (dec_tdata_w)
  );


endmodule  /* usb_ulpi_top */
