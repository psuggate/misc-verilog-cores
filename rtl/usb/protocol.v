`timescale 1ns / 100ps
module protocol #(
    parameter [3:0] ENDPOINT1 = 1,
    parameter [3:0] ENDPOINT2 = 2,
    parameter CONFIG_DESC_LEN = 18,
    parameter CONFIG_DESC = {
      /* Interface descriptor */
      8'h00,  /* iInterface */
      8'h00,  /* bInterfaceProtocol */
      8'h00,  /* bInterfaceSubClass */
      8'h00,  /* bInterfaceClass */
      8'h00,  /* bNumEndpoints = 0 */
      8'h00,  /* bAlternateSetting */
      8'h00,  /* bInterfaceNumber = 0 */
      8'h04,  /* bDescriptorType = Interface Descriptor */
      8'h09,  /* bLength = 9 */
      /* Configuration Descriptor */
      8'h32,  /* bMaxPower = 100 mA */
      8'hC0,  /* bmAttributes = Self-powered */
      8'h00,  /* iConfiguration */
      8'h01,  /* bConfigurationValue */
      8'h01,  /* bNumInterfaces = 1 */
      16'h0012,  /* wTotalLength = 18 */
      8'h02,  /* bDescriptionType = Configuration Descriptor */
      8'h09  /* bLength = 9 */
    },
    parameter [15:0] VENDOR_ID = 16'hFACE,
    parameter VENDOR_LENGTH = 7,
    parameter VENDOR_STRING = "Potatoe",
    parameter [15:0] PRODUCT_ID = 16'h0bde,
    parameter PRODUCT_LENGTH = 6,
    parameter PRODUCT_STRING = "Fallow",
    parameter SERIAL_LENGTH = 8,
    parameter SERIAL_STRING = "SN000001"
) (
    input clock,
    input reset,

    // Debug & status signals
    output configured_o,
    output has_telemetry_o,
    output [6:0] usb_addr_o,
    output [7:0] usb_conf_o,
    output usb_sof_o,
    output crc_err_o,
    output timeout_o,

    // USB control & bulk data received from host
    input usb_tvalid_i,
    output usb_tready_o,
    input usb_tlast_i,
    input [7:0] usb_tdata_i,

    // USB control & bulk data transmitted to the host
    output usb_tvalid_o,
    input usb_tready_i,
    output usb_tlast_o,
    output [7:0] usb_tdata_o,

    // USB Bulk Transfer parameters and data-streams
    input blk_in_ready_i,
    input blk_out_ready_i,
    output blk_start_o,
    output blk_cycle_o,
    output [3:0] blk_endpt_o,
    input blk_error_i,

    output blk_tvalid_o,
    input blk_tready_i,
    output blk_tlast_o,
    output [7:0] blk_tdata_o,

    input blk_tvalid_i,
    output blk_tready_o,
    input blk_tlast_i,
    input [7:0] blk_tdata_i
);


  // -- Constants -- //

  localparam HIGH_SPEED = 1;


  // -- Signals and Assignments -- //

  wire usb_enum_w;
  wire [6:0] usb_addr_w;

  wire ctl0_start_w, ctl0_cycle_w, ctl0_error_w;
  wire ctl0_tvalid_w, ctl0_tready_w, ctl0_tlast_w;
  wire [7:0] ctl0_tdata_w;

  wire [3:0] ctl_endpt_w;
  wire [7:0] ctl_rtype_w, ctl_rargs_w;
  wire [15:0] ctl_value_w, ctl_index_w, ctl_length_w;

  wire hsk_rx_recv_w, hsk_tx_send_w, hsk_tx_sent_w;
  wire [1:0] hsk_rx_type_w, hsk_tx_type_w;

  wire tok_rx_recv_w, tok_rx_ping_w;
  wire [1:0] tok_rx_type_w;
  wire [6:0] tok_rx_addr_w;
  wire [3:0] tok_rx_endp_w;

  wire usb_rx_trecv_w, usb_tx_tsend_w, usb_tx_tbusy_w, usb_tx_tdone_w;
  wire [1:0] usb_rx_ttype_w, usb_tx_ttype_w;

  wire usb_rx_tvalid_w, usb_rx_tready_w, usb_rx_tlast_w;
  wire usb_tx_tvalid_w, usb_tx_tready_w, usb_tx_tlast_w;
  wire [7:0] usb_rx_tdata_w, usb_tx_tdata_w;

  reg crc_err_q, ctl_err_q, ctl_sel_q, usb_sof_q;
  wire crc_err_w;


  assign usb_addr_o = usb_addr_w;

  assign crc_err_o  = crc_err_q;


  // -- Status & Debug Flags -- //

  always @(posedge clock) begin
    if (reset) begin
      ctl_err_q <= 1'b0;
      ctl_sel_q <= 1'b0;
      crc_err_q <= 1'b0;
      usb_sof_q <= 1'b0;
    end else begin
      if (ctl0_error_w) begin
        ctl_err_q <= 1'b1;
      end
      if (ctl0_cycle_w) begin
        ctl_sel_q <= 1'b1;
      end
      if (crc_err_w) begin
        crc_err_q <= 1'b1;
      end
      if (usb_sof_o) begin
        usb_sof_q <= 1'b1;
      end
    end
  end


  // -- Bulk IN Status -- //

  reg blk_in_ready_q, tele_sel_q;
  wire [9:0] tele_level_w;

  assign blk_tready_o = ~tele_sel_q & mux_tready_w;

  always @(posedge clock) begin
    tele_sel_q <= blk_endpt_o == ENDPOINT2;
    blk_in_ready_q <= blk_in_ready_i || tele_level_w[9:4] != 0;
  end


  // -- Encode/decode USB packets, over the AXI4 streams -- //

  encode_packet #(
      .TOKEN(0)
  ) U_ENCODER0 (
      .reset(reset),
      .clock(clock),

      .tx_tvalid_o(usb_tvalid_o),
      .tx_tready_i(usb_tready_i),
      .tx_tlast_o (usb_tlast_o),
      .tx_tdata_o (usb_tdata_o),

      .hsk_send_i(hsk_tx_send_w),
      .hsk_done_o(hsk_tx_sent_w),
      .hsk_type_i(hsk_tx_type_w),

      .tok_send_i(1'b0),  // Only used by USB hosts
      .tok_done_o(),
      .tok_type_i(2'bx),
      .tok_data_i(16'bx),

      .trn_tsend_i(usb_tx_tsend_w),
      .trn_ttype_i(usb_tx_ttype_w),
      .enc_busy_o (usb_tx_tbusy_w),
      .trn_tdone_o(usb_tx_tdone_w),

      .trn_tvalid_i(usb_tx_tvalid_w),
      .trn_tready_o(usb_tx_tready_w),
      .trn_tlast_i (usb_tx_tlast_w),
      .trn_tdata_i (usb_tx_tdata_w)
  );

  decode_packet U_DECODER0 (
      .reset(reset),
      .clock(clock),

      .ulpi_tvalid_i(usb_tvalid_i),
      .ulpi_tready_o(usb_tready_o),
      .ulpi_tlast_i (usb_tlast_i),
      .ulpi_tdata_i (usb_tdata_i),

      .usb_sof_o(usb_sof_o),
      .crc_err_o(crc_err_w),

      // Handshake packet information
      .hsk_recv_o(hsk_rx_recv_w),
      .hsk_type_o(hsk_rx_type_w),

      // Indicates that a (OUT/IN/SETUP) token was received
      .tok_recv_o(tok_rx_recv_w),  // Start strobe
      .tok_ping_o(tok_rx_ping_w),  // Special 'PING' token-type
      .tok_type_o(tok_rx_type_w),  // Token-type (OUT/IN/SETUP)
      .tok_addr_o(tok_rx_addr_w),
      .tok_endp_o(tok_rx_endp_w),

      // Data packet (OUT, DATA0/1/2 MDATA) received
      .out_recv_o(usb_rx_trecv_w),
      .out_type_o(usb_rx_ttype_w),

      .out_tvalid_o(usb_rx_tvalid_w),
      .out_tready_i(usb_rx_tready_w),
      .out_tlast_o (usb_rx_tlast_w),
      .out_tdata_o (usb_rx_tdata_w)
  );


  // -- FSM for USB packets, handshakes, etc. -- //

  wire blkx_tvalid_w, blkx_tlast_w, blkx_tready_w;
  wire [7:0] blkx_tdata_w;

  wire tel_tvalid_w, tel_tlast_w, tel_tready_w;
  wire [7:0] tel_tdata_w;


  transactor #(
      .PIPELINED(1)
  ) U_USB_TRN0 (
      .clock(clock),
      .reset(reset),

      .usb_addr_i(usb_addr_w),
      .usb_timeout_error_o(timeout_o),

      // Signals from the USB packet decoder (upstream)
      .tok_recv_i(tok_rx_recv_w),
      .tok_ping_i(tok_rx_ping_w),
      .tok_type_i(tok_rx_type_w),
      .tok_addr_i(tok_rx_addr_w),
      .tok_endp_i(tok_rx_endp_w),

      .hsk_recv_i(hsk_rx_recv_w),
      .hsk_type_i(hsk_rx_type_w),
      .hsk_send_o(hsk_tx_send_w),
      .hsk_sent_i(hsk_tx_sent_w),
      .hsk_type_o(hsk_tx_type_w),

      // DATA0/1 info from the decoder, and to the encoder
      .usb_recv_i(usb_rx_trecv_w),
      .usb_type_i(usb_rx_ttype_w),
      .usb_send_o(usb_tx_tsend_w),
      .usb_busy_i(usb_tx_tbusy_w),
      .usb_sent_i(usb_tx_tdone_w),
      .usb_type_o(usb_tx_ttype_w),

      // USB control & bulk data received from host (via decoder)
      .usb_tvalid_i(usb_rx_tvalid_w),
      .usb_tready_o(usb_rx_tready_w),
      .usb_tlast_i (usb_rx_tlast_w),
      .usb_tdata_i (usb_rx_tdata_w),

      .usb_tvalid_o(usb_tx_tvalid_w),
      .usb_tready_i(usb_tx_tready_w),
      .usb_tlast_o (usb_tx_tlast_w),
      .usb_tdata_o (usb_tx_tdata_w),

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

      .blk_tvalid_o(blk_tvalid_o),
      .blk_tready_i(blk_tready_i),
      .blk_tlast_o (blk_tlast_o),
      .blk_tdata_o (blk_tdata_o),

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

  assign mux_tvalid_w = tele_sel_q ? tel_tvalid_w : blk_tvalid_i;
  assign mux_tlast_w  = tele_sel_q ? tel_tlast_w : blk_tlast_i;
  assign mux_tdata_w  = tele_sel_q ? tel_tdata_w : blk_tdata_i;

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

  assign usb_state_w = U_USB_TRN0.xfer_state_w;
  assign ctl_state_w = U_USB_TRN0.xctrl;
  assign blk_state_w = U_USB_TRN0.xbulk;


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

      .crc_error_i(crc_err_w),
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


endmodule  // protocol
