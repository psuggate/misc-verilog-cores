`timescale 1ns / 100ps
module usb_ulpi_top
  #( parameter USE_EP2_IN = 1,
     parameter USE_EP1_OUT = 1
     )
  (
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
    output usb_reset_o  // USB core is in reset state
   );



  // -- Encode/decode USB ULPI packets, over the AXI4 streams -- //

  wire usb_idle_w;
  wire [3:0] phy_state_w, usb_state_w, ctl_state_w;
  wire [7:0] blk_state_w;


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

  ulpi_decoder U_DECODER1 (
      .clock(clock),
      .reset(reset),

      .LineState(LineState),

      .ulpi_dir (iob_dir_w),
      .ulpi_nxt (iob_nxt_w),
      .ulpi_data(iob_dat_w),

      .crc_error_o(crc_err_o),
      .crc_valid_o(crc_vld_o),
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

  wire blko_tvalid_w, blko_tready_w, blko_tlast_w, blko_tkeep_w;
  wire [7:0] blko_tdata_w;

  transactor #(
      .PIPELINED(PIPELINED),
      .ENDPOINT1(ENDPOINT1),
      .ENDPOINT2(ENDPOINT2)
  ) U_TRANSACT1 (
      .clock(clock),
      .reset(reset),

      .usb_addr_i(usb_addr_w),
      .err_code_o(err_code_w),
      .usb_timeout_error_o(timeout_w),
      .usb_device_idle_o(usb_idle_w),

      .parity1_o(parity1_w),

      .usb_state_o(usb_state_w),
      .ctl_state_o(ctl_state_w),
      .blk_state_o(blk_state_w),

      // Signals from the USB packet decoder (upstream)
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
      .blk_in_ready_i(blk_in_ready_q),
      .blk_out_ready_i(blk_out_ready_i),
      .blk_start_o(blk_start_o),
      .blk_cycle_o(blk_cycle_o),
      .blk_fetch_o(blk_fetch_o),
      .blk_store_o(blk_store_o),
      .blk_endpt_o(blk_endpt_o),
      .blk_error_i(blk_error_i),

      .blk_tvalid_i(blkx_tvalid_w),
      .blk_tready_o(blkx_tready_w),
      .blk_tlast_i (blkx_tlast_w),
      .blk_tkeep_i (blkx_tkeep_w),
      .blk_tdata_i (blkx_tdata_w),

      .blk_tvalid_o(blko_tvalid_w),
      .blk_tready_i(blko_tready_w),
      .blk_tlast_o (blko_tlast_w),
      .blk_tkeep_o (blko_tkeep_w),
      .blk_tdata_o (blko_tdata_w),

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
  ) U_CFG_PIPE0 (
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


endmodule  /* usb_ulpi_top */
