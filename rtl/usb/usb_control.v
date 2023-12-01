`timescale 1ns / 100ps
module usb_control (
    clock,
    reset,

    configured_o,
    usb_addr_o,
    usb_conf_o,
    usb_sof_o,
    crc_err_o,

   flag_tok_recv_o,
   flag_hsk_recv_o,
   flag_hsk_sent_o,

    usb_tvalid_i,
    usb_tready_o,
    usb_tlast_i,
    usb_tdata_i,

    usb_tvalid_o,
    usb_tready_i,
    usb_tlast_o,
    usb_tdata_o,

    ctl_start_o,
    ctl_rtype_o,
    ctl_rargs_o,
    ctl_value_o,
    ctl_index_o,
    ctl_length_o,

    ctl_tvalid_i,
    ctl_tready_o,
    ctl_tlast_i,
    ctl_tdata_i,

    ctl_tvalid_o,
    ctl_tready_i,
    ctl_tlast_o,
    ctl_tdata_o,

    blk_start_o,
    blk_dtype_o,
    blk_muxsel_o,
    blk_tvalid_o,
    blk_tlast_o,
    blk_tdata_o,
    blk_tready_o,

    blk_done1_i,
    blk_done2_i,
    blk_tready_i,
    blk_tvalid_i,
    blk_tlast_i,
    blk_tdata_i
);

  parameter EP1_BULK_IN = 1;
  parameter EP1_BULK_OUT = 1;
  parameter EP1_CONTROL = 0;

  parameter EP2_BULK_IN = 1;
  parameter EP2_BULK_OUT = 0;
  parameter EP2_CONTROL = 1;

  parameter ENDPOINT1 = 1;  // set to '0' to disable
  parameter ENDPOINT2 = 2;  // set to '0' to disable

  parameter VENDOR_ID = 16'hFACE;
  parameter VENDOR_LENGTH = 0;
  parameter VENDOR_STRING = "";
  parameter PRODUCT_ID = 16'h0bde;
  parameter PRODUCT_LENGTH = 0;
  parameter PRODUCT_STRING = "";
  parameter SERIAL_LENGTH = 8;
  parameter SERIAL_STRING = "SN000001";


  input clock;
  input reset;

  output configured_o;
  output [6:0] usb_addr_o;
  output [7:0] usb_conf_o;
  output usb_sof_o;
  output crc_err_o;

  output flag_tok_recv_o;
  output flag_hsk_recv_o;
  output flag_hsk_sent_o;

  // USB control & bulk data received from host
  input usb_tvalid_i;
  output usb_tready_o;
  input usb_tlast_i;
  input [7:0] usb_tdata_i;

  // USB control & bulk data transmitted to the host
  output usb_tvalid_o;
  input usb_tready_i;
  output usb_tlast_o;
  output [7:0] usb_tdata_o;

  // USB Control Transfer parameters and data-streams
  output ctl_start_o;
  output [7:0] ctl_rtype_o;  // todo:
  output [7:0] ctl_rargs_o;  // todo:
  output [15:0] ctl_value_o;
  output [15:0] ctl_index_o;
  output [15:0] ctl_length_o;

  output ctl_tvalid_o;
  input ctl_tready_i;
  output ctl_tlast_o;
  output [7:0] ctl_tdata_o;

  input ctl_tvalid_i;
  output ctl_tready_o;
  input ctl_tlast_i;
  input [7:0] ctl_tdata_i;

  // USB Bulk Transfer parameters and data-streams
  output blk_start_o;
  output blk_dtype_o;  // todo: OUT/IN, DATA0/1
  input blk_done1_i;  // todo: smrat ??
  input blk_done2_i;  // todo: smrat ??
  output blk_muxsel_o;  // todo: smrat ??

  output blk_tvalid_o;  // todo: not needed, as can use stream from the decoder !?
  input blk_tready_i;
  output blk_tlast_o;
  output [7:0] blk_tdata_o;

  input blk_tvalid_i;  // todo: not needed, as can use external MUX to encoder !?
  output blk_tready_o;
  input blk_tlast_i;
  input [7:0] blk_tdata_i;


  // -- Constants -- //

  localparam HIGH_SPEED = 1;


  // -- Signals and Assignments -- //

  wire ctl0_select_w, ctl0_accept_w, ctl0_error_w;
  wire [6:0] usb_addr_w;

  wire rx_hrecv_w, tx_hsend_w, tx_hsent_w;
  wire [1:0] rx_htype_w, tx_htype_w;

  wire enc_busy_w, trn_send_w, trn_done_w;
  wire [1:0] trn_type_w;

  wire tok_rx_recv_w;
  wire [1:0] tok_rx_type_w;
  wire [6:0] tok_rx_addr_w;
  wire [3:0] tok_rx_endp_w;

  wire ctl0_tvalid_w, ctl0_tready_w, ctl0_tlast_w, ctl0_done_w;
  wire [7:0] ctl0_tdata_w;

  wire cfgi_tvalid_w, cfgi_tready_w, cfgi_tlast_w;
  wire [7:0] cfgi_tdata_w;

  wire usb_rx_trecv_w, usb_tx_tsend_w, usb_tx_tsent_w;
  wire [1:0] usb_rx_ttype_w, usb_tx_ttype_w;

  wire usb_rx_tvalid_w, usb_rx_tready_w, usb_rx_tlast_w;
  wire usb_tx_tvalid_w, usb_tx_tready_w, usb_tx_tlast_w;
  wire [7:0] usb_rx_tdata_w, usb_tx_tdata_w;

  wire ctlo_tvalid_w, ctlo_tready_w, ctlo_tlast_w;
  wire ctli_tvalid_w, ctli_tready_w, ctli_tlast_w;
  wire [7:0] ctlo_tdata_w, ctli_tdata_w;

  wire blko_tvalid_w, blko_tready_w, blko_tlast_w;
  wire blki_tvalid_w, blki_tready_w, blki_tlast_w;
  wire [7:0] blko_tdata_w, blki_tdata_w;

  wire ulpi_rx_tvalid_w, ulpi_rx_tready_w, ulpi_rx_tlast_w;
  wire ulpi_tx_tvalid_w, ulpi_tx_tready_w, ulpi_tx_tlast_w;
  wire [7:0] ulpi_rx_tdata_w, ulpi_tx_tdata_w;

  wire ctl_start_w, ctl_done_w;
  wire [7:0] ctl_rtype_w, ctl_rargs_w;
  wire [15:0] ctl_value_w, ctl_index_w, ctl_length_w;


  assign usb_addr_o = usb_addr_w;

  assign ctl_tvalid_o = ctlo_tvalid_w;
  assign ctlo_tready_w = ctl_tready_i;  // todo:
  assign ctl_tlast_o = ctlo_tlast_w;
  assign ctl_tdata_o = ctlo_tdata_w;

  assign usb_tready_o = 1'b1;  // todo: usb_rx_tready_w;


  // -- Status & Debug Flags -- //

  reg tok_recv_q, hsk_recv_q, hsk_sent_q;

  assign flag_tok_recv_o = tok_recv_q;
  assign flag_hsk_recv_o = hsk_recv_q;
  assign flag_hsk_sent_o = hsk_sent_q;

  always @(posedge clock) begin
    if (reset) begin
      {tok_recv_q, hsk_recv_q, hsk_sent_q} <= 3'h0;
    end else begin
      tok_recv_q <= tok_recv_q | tok_rx_recv_w;
      hsk_recv_q <= hsk_recv_q | rx_hrecv_w;
      hsk_sent_q <= hsk_sent_q | tx_hsent_w;
    end
  end


  // -- Encode/decode USB packets, over the AXI4 streams -- //

  encode_packet #(
      .TOKEN(0)
  ) U_ENCODER0 (
      .reset(reset),
      .clock(clock),

      .enc_busy_o(enc_busy_w),

      .tx_tvalid_o(usb_tvalid_o),
      .tx_tready_i(usb_tready_i),
      .tx_tlast_o (usb_tlast_o),
      .tx_tdata_o (usb_tdata_o),

      .hsk_send_i(tx_hsend_w),
      .hsk_done_o(tx_hsent_w),
      .hsk_type_i(tx_htype_w),

      .tok_send_i(1'b0),  // Only used by USB hosts
      .tok_done_o(),
      .tok_type_i(2'bx),
      .tok_data_i(16'bx),

      .trn_tsend_i(trn_send_w),
      .trn_ttype_i(trn_type_w),
      .trn_tdone_o(trn_done_w),

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
      .crc_err_o(crc_err_o),

      // Handshake packet information
      .hsk_recv_o(rx_hrecv_w),
      .hsk_type_o(rx_htype_w),

      // Indicates that a (OUT/IN/SETUP) token was received
      .tok_recv_o(tok_rx_recv_w),  // Start strobe
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

  control_transfer
  U_USB_TRN0 (
      .clock(clock),
      .reset(reset),

      .usb_addr_i(usb_addr_w),
/*
   .fsm_ctrl_i(fsm_ctrl_w),
   .fsm_idle_i(fsm_idle_w),
   // .ctl_done_o(ctl_done_w),
*/

      // Signals from the USB packet decoder (upstream)
      .tok_recv_i(tok_rx_recv_w),
      .tok_type_i(tok_rx_type_w),
      .tok_addr_i(tok_rx_addr_w),
      .tok_endp_i(tok_rx_endp_w),

      .hsk_recv_i(rx_hrecv_w),
      .hsk_type_i(rx_htype_w),
      .hsk_send_o(tx_hsend_w),
      .hsk_sent_i(tx_hsent_w),
      .hsk_type_o(tx_htype_w),

      // DATA0/1 info from the decoder, and to the encoder
      .usb_recv_i(usb_rx_trecv_w),
      .usb_type_i(usb_rx_ttype_w),
      .usb_send_o(usb_tx_tsend_w),
      .usb_sent_i(usb_tx_tsent_w),
      .usb_type_o(usb_tx_ttype_w),

      // USB control & bulk data received from host (via decoder)
      .usb_tvalid_i(usb_rx_tvalid_w),
      .usb_tready_o(usb_rx_tready_w),
      .usb_tlast_i (usb_rx_tlast_w),
      .usb_tdata_i (usb_rx_tdata_w),

      // USB control & bulk data transmitted to host (via encoder)
      .trn_send_o(trn_send_w),
      .trn_type_o(trn_type_w),
      .trn_busy_i(enc_busy_w),
      .trn_done_i(trn_done_w),

      .usb_tvalid_o(usb_tx_tvalid_w),
      .usb_tready_i(usb_tx_tready_w),
      .usb_tlast_o (usb_tx_tlast_w),
      .usb_tdata_o (usb_tx_tdata_w),

      // To/from USB control transfer endpoints
      .ctl_start_o (ctl_start_w),
      .ctl_cycle_o (ctl0_select_w),
      .ctl_done_i  (ctl0_done_w),
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

/*
  transaction #(
      .EP1_BULK_IN(EP1_BULK_IN),  // IN- & OUT- for TART raw (antenna) samples
      .EP1_BULK_OUT(EP1_BULK_OUT),
      .EP1_CONTROL(EP1_CONTROL),
      .ENDPOINT1(ENDPOINT1),
      .EP2_BULK_IN(EP2_BULK_IN),  // IN-only for TART correlated values
      .EP2_BULK_OUT(EP2_BULK_OUT),
      .EP2_CONTROL(EP2_CONTROL),  // Control EP for configuring TART
      .ENDPOINT2(ENDPOINT2),
      .HIGH_SPEED(HIGH_SPEED)
  ) U_USB_TRN0 (
      .clock(clock),
      .reset(reset),

      .usb_addr_i(usb_addr_w),

      // Signals from the USB packet decoder (upstream)
      .tok_recv_i(tok_rx_recv_w),
      .tok_type_i(tok_rx_type_w),
      .tok_addr_i(tok_rx_addr_w),
      .tok_endp_i(tok_rx_endp_w),

      .hsk_recv_i(rx_hrecv_w),
      .hsk_type_i(rx_htype_w),
      .hsk_send_o(tx_hsend_w),
      .hsk_sent_i(tx_hsent_w),
      .hsk_type_o(tx_htype_w),

      // DATA0/1 info from the decoder, and to the encoder
      .usb_recv_i(usb_rx_trecv_w),
      .usb_type_i(usb_rx_ttype_w),
      .usb_send_o(usb_tx_tsend_w),
      .usb_sent_i(usb_tx_tsent_w),
      .usb_type_o(usb_tx_ttype_w),

      // USB control & bulk data received from host (via decoder)
      .usb_tvalid_i(usb_rx_tvalid_w),
      .usb_tready_o(usb_rx_tready_w),
      .usb_tlast_i (usb_rx_tlast_w),
      .usb_tdata_i (usb_rx_tdata_w),

      // USB control & bulk data transmitted to host (via encoder)
      .trn_send_o(trn_send_w),
      .trn_type_o(trn_type_w),
      .trn_busy_i(enc_busy_w),
      .trn_done_i(trn_done_w),

      .usb_tvalid_o(usb_tx_tvalid_w),
      .usb_tready_i(usb_tx_tready_w),
      .usb_tlast_o (usb_tx_tlast_w),
      .usb_tdata_o (usb_tx_tdata_w),

      .ep0_ce_o(ctl0_select_w),
      .ep1_ce_o(),
      .ep2_ce_o(),

      // To/from USB bulk transfer endpoints
      .blk_start_o (),
      .blk_dtype_o (),
      .blk_done1_i (1'b0),
      .blk_done2_i (1'b0),
      .blk_muxsel_o(),

      .blk_tvalid_o(blko_tvalid_w),
      .blk_tready_i(blko_tready_w),
      .blk_tlast_o (blko_tlast_w),
      .blk_tdata_o (blko_tdata_w),

      .blk_tvalid_i(blki_tvalid_w),
      .blk_tready_o(blki_tready_w),
      .blk_tlast_i (blki_tlast_w),
      .blk_tdata_i (blki_tdata_w),

      // To/from USB control transfer endpoints
      .ctl_start_o (ctl_start_w),
      .ctl_done_i  (ctl_done_w),
      .ctl_rtype_o (ctl_rtype_w),
      .ctl_rargs_o (ctl_rargs_w),
      .ctl_value_o (ctl_value_w),
      .ctl_index_o (ctl_index_w),
      .ctl_length_o(ctl_length_w),

      .ctl_tvalid_o(ctlo_tvalid_w),
      .ctl_tready_i(ctlo_tready_w),
      .ctl_tlast_o (ctlo_tlast_w),
      .ctl_tdata_o (ctlo_tdata_w),

      .ctl_tvalid_i(ctli_tvalid_w),
      .ctl_tready_o(ctli_tready_w),
      .ctl_tlast_i (ctli_tlast_w),
      .ctl_tdata_i (ctli_tdata_w)
  );

  generate
    if (EP1_CONTROL || EP2_CONTROL) begin : g_yes_mux_control

      // todo: 2:1 AXI4-Stream MUX (from Alex Forencich)

    end else begin : g_no_mux_control

      assign ctl_done_w = ctl0_done_w;

      assign ctli_tvalid_w = ctl0_tvalid_w;
      assign ctl0_tready_w = ctli_tready_w;
      assign ctli_tlast_w = ctl0_tlast_w;
      assign ctli_tdata_w = ctl0_tdata_w;

    end
  endgenerate
*/


  // -- USB Default (PIPE0) Configuration Endpoint -- //

  ctl_pipe0 #(
      .VENDOR_ID(VENDOR_ID),
      .PRODUCT_ID(PRODUCT_ID),
      .MANUFACTURER_LEN(VENDOR_LENGTH),
      .MANUFACTURER(VENDOR_STRING),
      .PRODUCT_LEN(PRODUCT_LENGTH),
      .PRODUCT(PRODUCT_STRING),
      .SERIAL_LEN(SERIAL_LENGTH),
      .SERIAL(SERIAL_STRING),
      .HIGH_SPEED(HIGH_SPEED)
  ) U_CFG_PIPE0 (
      .reset(reset),
      .clock(clock),

      .select_i(ctl0_select_w),
      .start_i (ctl_start_w),
      .accept_o(ctl0_accept_w),
      .done_o  (ctl0_done_w),

      .error_o(ctl0_error_w),
      .configured_o(configured_o),
      .usb_conf_o(usb_conf_o[7:0]),

      .usb_addr_o (usb_addr_w),
      .req_type_i (ctl_rtype_w),
      .req_args_i (ctl_rargs_w),
      .req_value_i(ctl_value_w),

      // AXI4-Stream for device descriptors
      .m_tvalid_o(ctl0_tvalid_w),
      .m_tready_i(ctl0_tready_w),
      .m_tlast_o (ctl0_tlast_w),
      .m_tdata_o (ctl0_tdata_w)
  );


endmodule  // usb_control
