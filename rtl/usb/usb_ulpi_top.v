`timescale 1ns / 100ps
module usb_ulpi_top #(
    parameter USE_EP2_IN  = 1,
    parameter USE_EP1_OUT = 1,
    parameter USE_EP3_IN  = 0,

    parameter [3:0] ENDPOINT1 = 4'd1,
    parameter [3:0] ENDPOINT2 = 4'd2,
    parameter [3:0] ENDPOINT3 = 4'd3,

    parameter integer PACKET_FIFO_DEPTH = 2048,
    parameter integer MAX_PACKET_LENGTH = 512,   // For HS-mode
    parameter integer MAX_CONFIG_LENGTH = 64,    // For HS- & FS- modes

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
    output conf_event_o,
    output [2:0] conf_value_o,

    input blki_tvalid_i,
    output blki_tready_o,
    input blki_tlast_i,
    input blki_tkeep_i,
    input [7:0] blki_tdata_i,

    input blkx_tvalid_i,  // Optional Bulk IN endpoint
    output blkx_tready_o,
    input blkx_tlast_i,
    input blkx_tkeep_i,
    input [7:0] blkx_tdata_i,

    output blko_tvalid_o,
    input blko_tready_i,
    output blko_tlast_o,
    output blko_tkeep_o,
    output [7:0] blko_tdata_o
);

  `include "usb_defs.vh"

  localparam integer PIPELINED = 1;
  localparam [7:0] EP_NUM = USE_EP1_OUT + USE_EP2_IN + USE_EP3_IN;

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
    EP_NUM, // bNumEndpoints <= 3
    8'h00,  // bAlternateSetting
    8'h00,  // bInterfaceNumber = 0
    8'h04,  // bDescriptorType = Interface Descriptor
    8'h09  // bLength = 9
  };

  localparam integer EP1_DESC_LEN = USE_EP1_OUT ? 7 : 0;
  localparam integer EP1_DESC_BITS = EP1_DESC_LEN * 8;
  localparam integer EP2_DESC_LEN = USE_EP2_IN ? 7 : 0;
  localparam integer EP2_DESC_BITS = EP2_DESC_LEN * 8;
  localparam integer EP3_DESC_LEN = USE_EP3_IN ? 7 : 0;
  localparam integer EP3_DESC_BITS = EP3_DESC_LEN * 8;
  localparam integer EP_DESC_LEN = EP1_DESC_LEN + EP2_DESC_LEN + EP3_DESC_LEN;
  localparam integer EP_DESC_BITS = EP1_DESC_BITS + EP2_DESC_BITS + EP3_DESC_BITS;

  localparam [7:0] EP1_OUT_ADDR = 8'h00 | ENDPOINT1;
  localparam [55:0] EP1_OUT_DESC = {
    8'h00,  // bInterval
    16'h0200,  // wMaxPacketSize = 512 bytes
    8'h02,  // bmAttributes = Bulk
    EP1_OUT_ADDR,  // bEndpointAddress = OUT1
    8'h05,  // bDescriptorType = Endpoint Descriptor
    8'h07  // bLength = 7
  };

  localparam [7:0] EP2_IN_ADDR = 8'h80 | ENDPOINT2;
  localparam [55:0] EP2_IN_DESC = {
    8'h00,  // bInterval
    16'h0200,  // wMaxPacketSize = 512 bytes
    8'h02,  // bmAttributes = Bulk
    EP2_IN_ADDR,  // bEndpointAddress = IN2
    8'h05,  // bDescriptorType = Endpoint Descriptor
    8'h07  // bLength = 7
  };

  localparam [7:0] EP3_IN_ADDR = 8'h80 | ENDPOINT3;
  localparam [55:0] EP3_IN_DESC = {
    8'h00,  // bInterval
    16'h0200,  // wMaxPacketSize = 512 bytes
    8'h02,  // bmAttributes = Bulk
    EP3_IN_ADDR,  // bEndpointAddress = IN3
    8'h05,  // bDescriptorType = Endpoint Descriptor
    8'h07  // bLength = 7
  };
  localparam integer EP3_DESC_START = EP1_DESC_BITS+EP2_DESC_BITS;

  function [EP_DESC_BITS-1:0] ep_descriptors;
    begin
      if (EP1_DESC_BITS != 0) begin
        ep_descriptors[EP1_DESC_BITS-1:0] = EP1_OUT_DESC[55:0];
      end
      if (EP2_DESC_BITS != 0) begin
        ep_descriptors[EP1_DESC_BITS+EP2_DESC_BITS-1:EP1_DESC_BITS] = EP2_IN_DESC[55:0];
      end
      if (EP3_DESC_BITS != 0) begin
        ep_descriptors[EP3_DESC_START+EP3_DESC_BITS-1:EP3_DESC_START] = EP3_IN_DESC[55:0];
      end
    end
  endfunction

  localparam integer CONF_DESC_SIZE = CONFIG_DESC_LEN + INTERFACE_DESC_LEN + EP_DESC_LEN;
  localparam integer CONF_DESC_BITS = CONF_DESC_SIZE * 8;
  localparam integer CSB = CONF_DESC_BITS - 1;
  localparam [CSB:0] CONF_DESC_VALS = {ep_descriptors(), INTERFACE_DESC, CONFIG_DESC};

  // -- Encode/decode USB ULPI packets, over the AXI4 streams -- //

  wire space_avail_w, ep2_packet_w, ep3_packet_w, crc_error_w;
  wire conf_event_w, conf_error_w;
  wire [2:0] conf_value_w;

  wire usb_enum_w, locked, clock, reset;
  wire high_speed_w, usb_reset_w, timeout_w;
  wire sof_rx_recv_w, eop_rx_recv_w;
  wire [7:0] ulpi_data_iw, ulpi_data_ow;

  wire [1:0] LineState, VbusState, RxEvent;

  wire iob_dir_w, iob_nxt_w;
  wire [7:0] iob_dat_w;

  wire tok_rx_recv_w, tok_rx_ping_w;
  wire [3:0] tok_endp_w;
  wire [6:0] tok_addr_w, usb_addr_w;

  wire hsk_tx_send_w, hsk_tx_done_w, usb_tx_busy_w, usb_tx_done_w;
  wire hsk_rx_recv_w, usb_rx_recv_w;
  wire dec_tvalid_w, dec_tready_w, dec_tkeep_w, dec_tlast_w;
  wire [3:0] ulpi_tx_tuser_w, dec_tuser_w;
  wire [7:0] dec_tdata_w;

  wire phy_write_w, phy_chirp_w, phy_stop_w, phy_busy_w, phy_done_w;
  wire [7:0] phy_addr_w, phy_data_w;

  wire enc_tvalid_w, enc_tready_w, enc_tkeep_w, enc_tlast_w;
  wire [3:0] enc_tuser_w;
  wire [7:0] enc_tdata_w;

  assign clock = ulpi_clock_i;
  assign reset = usb_reset_w;

  assign usb_clock_o = clock;
  assign usb_reset_o = reset;

  assign ulpi_data_io = ulpi_dir_i ? {8{1'bz}} : ulpi_data_ow;
  assign ulpi_data_iw = ulpi_data_io;

  assign dec_tready_w = 1'b1;

  assign conf_event_o = conf_event_w;
  assign conf_value_o = conf_value_w;


  //
  //  USB PHY, Encoder, Decoder, and Protocol Logic Components
  ///

  // -- USB Line-State and Speed-Negotiation Logic -- //

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
      .ulpi_rx_cmd_o(),
      .phy_state_o  (),

      .phy_write_o(phy_write_w),
      .phy_nopid_o(phy_chirp_w),
      .phy_stop_o (phy_stop_w),
      .phy_busy_i (phy_busy_w),
      .phy_done_i (phy_done_w),
      .phy_addr_o (phy_addr_w),
      .phy_data_o (phy_data_w),

      .pulse_2_5us_o(),
      .pulse_1_0ms_o()
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
      .dec_idle_o (),

      .tok_recv_o(tok_rx_recv_w),
      .tok_ping_o(tok_rx_ping_w),
      .tok_addr_o(tok_addr_w),
      .tok_endp_o(tok_endp_w),
      .hsk_recv_o(hsk_rx_recv_w),
      .usb_recv_o(usb_rx_recv_w),

      .m_tvalid(dec_tvalid_w),
      .m_tready(dec_tready_w),
      .m_tkeep (dec_tkeep_w),
      .m_tlast (dec_tlast_w),
      .m_tuser (dec_tuser_w),
      .m_tdata (dec_tdata_w)
  );

  ulpi_encoder U_ENC1 (
      .clock(clock),
      .reset(~areset_n),

      .high_speed_i (high_speed_w),
      .encode_idle_o(),

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

      .s_tvalid(enc_tvalid_w),
      .s_tready(enc_tready_w),
      .s_tkeep (enc_tkeep_w),
      .s_tlast (enc_tlast_w),
      .s_tuser (enc_tuser_w),
      .s_tdata (enc_tdata_w),

      .ulpi_dir (ulpi_dir_i),
      .ulpi_nxt (ulpi_nxt_i),
      .ulpi_stp (ulpi_stp_o),
      .ulpi_data(ulpi_data_ow)
  );

  // -- FSM for USB packets, handshakes, etc. -- //

  wire unused_tready_w;

  wire stdreq_select_w, stdreq_status_w, stdreq_parity_w, stdreq_finish_w;
  wire stdreq_tvalid_w, stdreq_tready_w, stdreq_tkeep_w, stdreq_tlast_w;
  wire [7:0] stdreq_tdata_w;

  wire req_start_w, req_status_w, req_cycle_w;
  wire [7:0] req_rtype_w, req_rargs_w;
  wire [15:0] req_value_w, req_index_w, req_length_w;
  wire [3:0] req_endpt_w = 4'h0;

  wire ep0_end_w;
  wire ep0_par_w, ep1_par_w, ep2_par_w, ep3_par_w;
  wire ep0_sel_w, ep1_sel_w, ep2_sel_w, ep3_sel_w;

  wire ep1_tvalid_w, ep1_tready_w, ep1_tkeep_w, ep1_tlast_w;
  wire ep2_tvalid_w, ep2_tready_w, ep2_tkeep_w, ep2_tlast_w;
  wire ep3_tvalid_w, ep3_tready_w, ep3_tkeep_w, ep3_tlast_w;
  wire [7:0] ep1_tdata_w, ep2_tdata_w, ep3_tdata_w;

  wire ep1_err_w, ep2_err_w, ep3_err_w;
  wire ep1_ack_w, ep2_ack_w, ep3_ack_w, ep1_hlt_w, ep2_hlt_w, ep3_hlt_w;

  wire mux_enable_w;
  wire [2:0] mux_select_w;

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
      .BULK_EP1   (ENDPOINT1),
      .USE_EP1_IN (0),
      .USE_EP1_OUT(USE_EP1_OUT),
      .BULK_EP2   (ENDPOINT2),
      .USE_EP2_IN (USE_EP2_IN),
      .USE_EP2_OUT(0),
      .BULK_EP3   (ENDPOINT3),
      .USE_EP3_IN (USE_EP3_IN),
      .USE_EP3_OUT(0),
      .BULK_EP4   (0)
  ) U_PROTO1 (
      .clock(clock),
      .reset(reset),

      .RxEvent(RxEvent),
      .timedout_o(timeout_w),

      .set_conf_i (conf_event_w),
      .clr_conf_i (conf_error_w),
      .usb_addr_i (usb_addr_q),
      .crc_error_i(crc_error_w),

      .tok_recv_i(tok_rx_recv_w),
      .tok_ping_i(tok_rx_ping_w),
      .tok_addr_i(tok_addr_w),
      .tok_endp_i(tok_endp_w),

      .hsk_recv_i(hsk_rx_recv_w),
      .hsk_send_o(hsk_tx_send_w),
      .hsk_sent_i(hsk_tx_done_w),

      .usb_recv_i(usb_rx_recv_w),
      .eop_recv_i(eop_rx_recv_w),
      .usb_sent_i(usb_tx_done_w),
      .usb_busy_i(usb_tx_busy_w),
      .usb_pid_i (dec_tuser_w),

      .mux_enable_o(mux_enable_w),
      .mux_select_o(mux_select_w),
      .ulpi_tuser_o(enc_tuser_w),

      .ep0_select_i(stdreq_select_w),
      .ep0_parity_i(stdreq_parity_w),
      .ep0_finish_i(stdreq_finish_w),

      .ep1_select_o(ep1_sel_w),
      .ep1_rx_rdy_i(space_avail_w),
      .ep1_tx_rdy_i(1'b0),
      .ep1_parity_i(ep1_par_w),
      .ep1_finish_o(ep1_ack_w),
      .ep1_cancel_o(ep1_err_w),
      .ep1_halted_i(ep1_hlt_w),

      .ep2_select_o(ep2_sel_w),
      .ep2_rx_rdy_i(1'b0),
      .ep2_tx_rdy_i(ep2_packet_w),
      .ep2_parity_i(ep2_par_w),
      .ep2_finish_o(ep2_ack_w),
      .ep2_cancel_o(ep2_err_w),
      .ep2_halted_i(ep2_hlt_w),

      .ep3_select_o(ep3_sel_w),
      .ep3_rx_rdy_i(1'b0),
      .ep3_tx_rdy_i(ep3_packet_w),
      .ep3_parity_i(ep3_par_w),
      .ep3_finish_o(ep3_ack_w),
      .ep3_cancel_o(ep3_err_w),
      .ep3_halted_i(ep3_hlt_w),

      .ep4_rx_rdy_i(1'b0),
      .ep4_tx_rdy_i(1'b0),
      .ep4_parity_i(1'b0),
      .ep4_select_o(),
      .ep4_cancel_o(),
      .ep4_halted_i(1'b1)
  );


  //
  //  USB End-Points and Datapath
  ///

  axis_mux #(
      .S_COUNT(4),
      .DATA_WIDTH(8),
      .KEEP_ENABLE(1),
      .KEEP_WIDTH(1),
      .ID_ENABLE(0),
      .ID_WIDTH(1),
      .DEST_ENABLE(0),
      .DEST_WIDTH(1),
      .USER_ENABLE(0),
      .USER_WIDTH(1)
  ) U_MUX1 (
      .clk(clock),
      .rst(reset),

      .enable(mux_enable_w),
      .select(mux_select_w[1:0]),

      .s_axis_tvalid({ep3_tvalid_w, ep2_tvalid_w, 1'd0, stdreq_tvalid_w}),
      .s_axis_tready({ep3_tready_w, ep2_tready_w, unused_tready_w, stdreq_tready_w}),
      .s_axis_tkeep ({ep3_tkeep_w, ep2_tkeep_w, 1'd0, stdreq_tkeep_w}),
      .s_axis_tlast ({ep3_tlast_w, ep2_tlast_w, 1'd0, stdreq_tlast_w}),
      .s_axis_tuser (4'bx),
      .s_axis_tid   (4'bx),
      .s_axis_tdest (4'bx),
      .s_axis_tdata ({ep3_tdata_w, ep2_tdata_w, 8'd0, stdreq_tdata_w}),

      .m_axis_tvalid(enc_tvalid_w),
      .m_axis_tready(enc_tready_w),
      .m_axis_tkeep (enc_tkeep_w),
      .m_axis_tlast (enc_tlast_w),
      .m_axis_tuser (),
      .m_axis_tid   (),
      .m_axis_tdest (),
      .m_axis_tdata (enc_tdata_w)
  );

  // -- USB Default (PIPE0) Configuration Endpoint -- //

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
      .req_event_i (conf_event_w),
      .req_error_i (conf_error_w),
      .req_rtype_o (req_rtype_w),
      .req_rargs_o (req_rargs_w),
      .req_value_o (req_value_w),
      .req_index_o (req_index_w),
      .req_length_o(req_length_w),

      // From the USB protocol logic
      .select_o (stdreq_select_w),
      .status_o (stdreq_status_w),
      .parity_o (stdreq_parity_w),
      .finish_o (stdreq_finish_w),
      .timeout_i(timeout_w),

      // From the packet decoder
      .s_tvalid(dec_tvalid_w),
      .s_tready(),  // Todo ...
      .s_tkeep(dec_tkeep_w),
      .s_tlast(dec_tlast_w),
      .s_tuser(dec_tuser_w),
      .s_tdata(dec_tdata_w)
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

      .configured_o(configured_o),
      .usb_conf_o  (conf_value_w),
      .usb_enum_o  (usb_enum_w),
      .usb_addr_o  (ctl_addr_w),

      .start_i (req_start_w),
      .select_i(req_cycle_w),
      .status_i(stdreq_status_w),
      .error_o (conf_error_w),
      .event_o (conf_event_w),

      .req_endpt_i (req_endpt_w),
      .req_type_i  (req_rtype_w),
      .req_args_i  (req_rargs_w),
      .req_value_i (req_value_w),
      .req_index_i (req_index_w),
      .req_length_i(req_length_w),

      // AXI4-Stream for device descriptors, to ULPI encoder
      .m_tvalid_o(stdreq_tvalid_w),
      .m_tready_i(stdreq_tready_w),
      .m_tkeep_o (stdreq_tkeep_w),
      .m_tlast_o (stdreq_tlast_w),
      .m_tdata_o (stdreq_tdata_w)
  );

  // -- USB Bulk IN & OUT End-Points -- //

  ep_bulk_out #(
      .MAX_PACKET_LENGTH(MAX_PACKET_LENGTH),
      .PACKET_FIFO_DEPTH(PACKET_FIFO_DEPTH),
      .ENABLED(USE_EP1_OUT)
  ) U_OUT_EP1 (
      .clock(clock),
      .reset(reset),

      .set_conf_i(conf_event_w),
      .clr_conf_i(conf_error_w),

      .selected_i(ep1_sel_w),
      .ack_sent_i(ep1_ack_w),      // Todo ...
      .rx_error_i(ep1_err_w),
      .ep_ready_o(space_avail_w),
      .stalled_o (ep1_hlt_w),
      .parity_o  (ep1_par_w),

      .s_tvalid(dec_tvalid_w),
      .s_tready(ep1_tready_w),  // Todo: route to protocol, for error-handling
      .s_tkeep (dec_tkeep_w),
      .s_tlast (dec_tlast_w),
      .s_tdata (dec_tdata_w),

      .m_tvalid(blko_tvalid_o),
      .m_tready(blko_tready_i),
      .m_tkeep (blko_tkeep_o),
      .m_tlast (blko_tlast_o),
      .m_tdata (blko_tdata_o)
  );

  ep_bulk_in #(
      .MAX_PACKET_LENGTH(MAX_PACKET_LENGTH),
      .PACKET_FIFO_DEPTH(PACKET_FIFO_DEPTH),
      .ENABLED(USE_EP2_IN)
  ) U_IN_EP2 (
      .clock     (clock),
      .reset     (reset),
      .set_conf_i(conf_event_w),
      .clr_conf_i(conf_error_w),
      .selected_i(ep2_sel_w),
      .ack_recv_i(ep2_ack_w),
      .timedout_i(ep2_err_w),
      .ep_ready_o(ep2_packet_w),
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

  ep_bulk_in #(
      .MAX_PACKET_LENGTH(MAX_PACKET_LENGTH),
      .PACKET_FIFO_DEPTH(PACKET_FIFO_DEPTH),
      .ENABLED(USE_EP3_IN)
  ) U_IN_EP3 (
      .clock     (clock),
      .reset     (reset),
      .set_conf_i(conf_event_w),
      .clr_conf_i(conf_error_w),
      .selected_i(ep3_sel_w),
      .ack_recv_i(ep3_ack_w),
      .timedout_i(ep3_err_w),
      .ep_ready_o(ep3_packet_w),
      .stalled_o (ep3_hlt_w),
      .parity_o  (ep3_par_w),
      .s_tvalid  (blkx_tvalid_i),
      .s_tready  (blkx_tready_o),
      .s_tlast   (blkx_tlast_i),
      .s_tdata   (blkx_tdata_i),
      .m_tvalid  (ep3_tvalid_w),
      .m_tready  (ep3_tready_w),
      .m_tkeep   (ep3_tkeep_w),
      .m_tlast   (ep3_tlast_w),
      .m_tdata   (ep3_tdata_w)
  );

  // initial #10340 $finish;

endmodule  /* usb_ulpi_top */
